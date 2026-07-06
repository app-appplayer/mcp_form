import 'package:mcp_bundle/mcp_bundle.dart';

import '../core/template/layout_extensions.dart';
import 'block_style.dart';
import 'style_sheet.dart';
import 'text_run_style.dart';

/// A block's style resolved to concrete values, ready for a renderer.
class ResolvedStyle {
  ResolvedStyle({
    required this.base,
    required this.align,
    required this.lineHeightMul,
    required this.overflow,
    required this.theme,
    this.boxHeightPt,
    this.spaceBefore,
    this.spaceAfter,
    this.indentPt = 0,
    this.paddingPt = 0,
    this.border,
    this.backgroundHex,
    this.numberFormat,
    this.listStyle,
  });

  /// Concrete base inline style (font family, size and block-level marks set).
  final TextRunStyle base;
  final FormTextAlign align;
  final double lineHeightMul;
  final BlockOverflow overflow;

  /// Theme kept so renderers can resolve run-level colour tokens.
  final FormTheme theme;

  final double? boxHeightPt;
  final double? spaceBefore;
  final double? spaceAfter;
  final double indentPt;
  final double paddingPt;
  final BlockBorder? border;
  final String? backgroundHex;
  final String? numberFormat;
  final String? listStyle;

  /// Resolve a (possibly token) colour against the theme palette.
  String resolveColor(String value) => theme.resolveColor(value);
}

/// Resolve a block's `style` map into a [ResolvedStyle], applying precedence:
/// layout defaults → theme → named style (`styleRef`) → block inline style.
ResolvedStyle resolveStyle({
  required Map<String, dynamic>? blockStyle,
  required FormLayoutPolicy layout,
  FormStyleSheet? sheet,
  double? defaultSizePt,
  bool heading = false,
  int headingLevel = 1,
}) {
  final theme = sheet?.theme ?? FormTheme.empty;
  final inline = BlockStyle.fromMap(blockStyle);
  final named = sheet?.named(inline.styleRef);
  final box = (named ?? BlockStyle.empty).merge(inline);

  final fallbackSize = defaultSizePt ??
      (heading
          ? layout.fontPolicy.headingSizeForLevel(headingLevel)
          : layout.fontPolicy.bodySize.toDouble());

  final family = box.text.fontFamily ??
      (heading ? theme.headingFont : theme.bodyFont) ??
      layout.fontFamily;

  final rawColor = box.text.color;
  final color = rawColor == null ? null : theme.resolveColor(rawColor);
  final rawHighlight = box.text.highlight;
  final highlight =
      rawHighlight == null ? null : theme.resolveColor(rawHighlight);
  final boxBorder = box.border;
  final resolvedBorder =
      boxBorder?.copyWith(color: theme.resolveColor(boxBorder.color));
  final rawBackground = box.background;
  final backgroundHex =
      rawBackground == null ? null : theme.resolveColor(rawBackground);

  final base = box.text.copyWith(
    fontFamily: family,
    fontSize: box.text.fontSize ?? fallbackSize,
    color: color,
    highlight: highlight,
  );

  return ResolvedStyle(
    base: base,
    align: box.align ?? FormTextAlign.left,
    lineHeightMul: box.lineHeight ?? 1.4,
    overflow: box.overflow ?? BlockOverflow.grow,
    theme: theme,
    boxHeightPt: box.height,
    spaceBefore: box.spaceBefore,
    spaceAfter: box.spaceAfter,
    indentPt: box.indent ?? 0,
    paddingPt: box.padding ?? 0,
    border: resolvedBorder,
    backgroundHex: backgroundHex,
    numberFormat: box.numberFormat,
    listStyle: box.listStyle,
  );
}
