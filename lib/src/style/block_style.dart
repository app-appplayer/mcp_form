import 'package:meta/meta.dart';

import 'text_run_style.dart';

/// Horizontal alignment of a block's text.
enum FormTextAlign {
  left,
  center,
  right,
  justify;

  static FormTextAlign? fromString(String? v) {
    switch (v) {
      case 'left':
        return FormTextAlign.left;
      case 'center':
      case 'centre':
        return FormTextAlign.center;
      case 'right':
        return FormTextAlign.right;
      case 'justify':
        return FormTextAlign.justify;
      default:
        return null;
    }
  }

  String get token => name;
}

/// What to do when a box has a fixed [BlockStyle.height] and its content does
/// not fit. See `doc/design/styling-and-copyfit.md`.
enum BlockOverflow {
  /// Flow freely; page pagination splits at line boundaries (default).
  grow,

  /// Reduce font size down to the policy minimum until the content fits.
  shrinkToFit,

  /// Keep the lines that fit; drop the rest.
  clip,

  /// Keep all content but report a target character budget so an upstream
  /// LLM / binding can condense the value (copyfit, the way people edit).
  summarize,

  /// Box may break across pages (same as [grow] at the page level).
  split;

  static BlockOverflow? fromString(String? v) {
    switch (v) {
      case 'grow':
        return BlockOverflow.grow;
      case 'shrink':
      case 'shrinkToFit':
      case 'shrink-to-fit':
        return BlockOverflow.shrinkToFit;
      case 'clip':
        return BlockOverflow.clip;
      case 'summarize':
      case 'summarise':
        return BlockOverflow.summarize;
      case 'split':
        return BlockOverflow.split;
      default:
        return null;
    }
  }

  String get token => switch (this) {
        BlockOverflow.shrinkToFit => 'shrink',
        _ => name,
      };
}

/// An outline drawn around a block's content box (e.g. a résumé frame). When a
/// bordered box splits across pages the open edges are suppressed at the break
/// so the frame reads as one continuous outline.
@immutable
class BlockBorder {
  const BlockBorder({
    this.width = 1.0,
    this.color = '#000000',
    this.radius = 0.0,
  });

  /// Stroke width in points.
  final double width;

  /// Stroke colour — `'#RRGGBB'` or a theme colour token.
  final String color;

  /// Corner radius in points (renderers that cannot round fall back to square).
  final double radius;

  BlockBorder copyWith({double? width, String? color, double? radius}) =>
      BlockBorder(
        width: width ?? this.width,
        color: color ?? this.color,
        radius: radius ?? this.radius,
      );

  Map<String, dynamic> toMap() => {
        'width': width,
        'color': color,
        if (radius != 0) 'radius': radius,
      };

  @override
  bool operator ==(Object other) =>
      other is BlockBorder &&
      other.width == width &&
      other.color == color &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(width, color, radius);
}

/// Block ("box-level") styling: alignment, spacing, indentation, a fixed box
/// height with an overflow policy, an optional border, plus the block's default
/// inline run style ([text]). Built from a `FormBlock.style` map.
@immutable
class BlockStyle {
  const BlockStyle({
    this.styleRef,
    this.align,
    this.text = TextRunStyle.empty,
    this.background,
    this.lineHeight,
    this.spaceBefore,
    this.spaceAfter,
    this.indent,
    this.height,
    this.overflow,
    this.border,
    this.padding,
    this.listStyle,
    this.numberFormat,
  });

  /// Build from a `FormBlock.style` map. Inline marks (`bold`, `color`, …) are
  /// read into [text]; box keys are read into the block fields.
  factory BlockStyle.fromMap(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) return empty;
    double? dbl(String k) => (m[k] as num?)?.toDouble();

    BlockBorder? border;
    final rawBorder = m['border'];
    if (rawBorder is Map) {
      final bm = rawBorder.cast<String, dynamic>();
      border = BlockBorder(
        width: (bm['width'] as num?)?.toDouble() ?? 1.0,
        color: bm['color'] as String? ?? '#000000',
        radius: (bm['radius'] as num?)?.toDouble() ?? 0.0,
      );
    } else if (rawBorder == true ||
        m['borderWidth'] != null ||
        m['borderColor'] != null) {
      border = BlockBorder(
        width: dbl('borderWidth') ?? 1.0,
        color: m['borderColor'] as String? ?? '#000000',
        radius: dbl('borderRadius') ?? 0.0,
      );
    }

    return BlockStyle(
      styleRef: m['styleRef'] as String?,
      align: FormTextAlign.fromString(m['align'] as String?),
      text: TextRunStyle.fromMap(m),
      background: m['background'] as String?,
      lineHeight: dbl('lineHeight'),
      spaceBefore: dbl('spaceBefore'),
      spaceAfter: dbl('spaceAfter'),
      indent: dbl('indent'),
      height: dbl('height'),
      overflow: BlockOverflow.fromString(m['overflow'] as String?),
      border: border,
      padding: dbl('padding'),
      listStyle: m['listStyle'] as String?,
      numberFormat: m['numberFormat'] as String?,
    );
  }

  /// Name of a style in the active [FormStyleSheet] to inherit from.
  final String? styleRef;

  /// Horizontal text alignment.
  final FormTextAlign? align;

  /// Default inline style applied to the block's runs.
  final TextRunStyle text;

  /// Box background colour — `'#RRGGBB'` or a theme colour token.
  final String? background;

  /// Line-height multiplier of the font size (null → policy default).
  final double? lineHeight;

  /// Space before the block in points.
  final double? spaceBefore;

  /// Space after the block in points.
  final double? spaceAfter;

  /// Left indentation in points.
  final double? indent;

  /// Fixed box height in points. When set, the overflow policy applies.
  final double? height;

  /// Overflow behaviour when content exceeds [height].
  final BlockOverflow? overflow;

  /// Optional outline around the content box.
  final BlockBorder? border;

  /// Inner padding in points (used with [border] / [background]).
  final double? padding;

  /// List marker style (`'bullet'` | `'decimal'` | `'none'`).
  final String? listStyle;

  /// Heading numbering format (e.g. `'1.1'`).
  final String? numberFormat;

  static const BlockStyle empty = BlockStyle();

  /// Non-null block fields of [other] override this one; inline [text] merges.
  BlockStyle merge(BlockStyle? other) {
    if (other == null) return this;
    return BlockStyle(
      styleRef: other.styleRef ?? styleRef,
      align: other.align ?? align,
      text: text.merge(other.text),
      background: other.background ?? background,
      lineHeight: other.lineHeight ?? lineHeight,
      spaceBefore: other.spaceBefore ?? spaceBefore,
      spaceAfter: other.spaceAfter ?? spaceAfter,
      indent: other.indent ?? indent,
      height: other.height ?? height,
      overflow: other.overflow ?? overflow,
      border: other.border ?? border,
      padding: other.padding ?? padding,
      listStyle: other.listStyle ?? listStyle,
      numberFormat: other.numberFormat ?? numberFormat,
    );
  }

  /// Serialise the set fields back to a map.
  Map<String, dynamic> toMap() => {
        if (styleRef != null) 'styleRef': styleRef,
        if (align != null) 'align': align!.token,
        ...text.toMap(),
        if (background != null) 'background': background,
        if (lineHeight != null) 'lineHeight': lineHeight,
        if (spaceBefore != null) 'spaceBefore': spaceBefore,
        if (spaceAfter != null) 'spaceAfter': spaceAfter,
        if (indent != null) 'indent': indent,
        if (height != null) 'height': height,
        if (overflow != null) 'overflow': overflow!.token,
        if (border != null) 'border': border!.toMap(),
        if (padding != null) 'padding': padding,
        if (listStyle != null) 'listStyle': listStyle,
        if (numberFormat != null) 'numberFormat': numberFormat,
      };
}
