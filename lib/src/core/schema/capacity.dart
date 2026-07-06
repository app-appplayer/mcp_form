/// Per-field capacity estimation — the copy-fit feed-forward.
///
/// Copy-fit already shrinks / clips / summarises content that overruns a fixed
/// box *after* generation. This estimates, *before* generation, roughly how many
/// characters a fixed-height field box holds, so the hint can be handed to the
/// LLM (or folded into the JSON Schema as `maxLength`) and the model writes to
/// fit — the way a person sizes prose to the space available.
library;

import 'package:mcp_bundle/mcp_bundle.dart';

import '../../style/font_metrics.dart';
import '../template/layout_extensions.dart';

/// Approximate text capacity of a box.
class FieldCapacity {
  const FieldCapacity({
    required this.maxChars,
    required this.lines,
    required this.charsPerLine,
  });

  /// Approximate maximum characters that fit (lines × charsPerLine).
  final int maxChars;

  /// Whole lines that fit the box height.
  final int lines;

  /// Approximate characters per line at the box width.
  final int charsPerLine;
}

const double _mmToPt = 2.8346;

/// Estimate how much text fits a box of [widthPt] × [heightPt] at [fontSizePt].
FieldCapacity estimateCapacity({
  required double widthPt,
  required double heightPt,
  required double fontSizePt,
  double lineHeightMul = 1.4,
  FontMetrics metrics = defaultMetrics,
}) {
  final lineHeight = fontSizePt * lineHeightMul;
  final lines = lineHeight > 0 ? (heightPt / lineHeight).floor() : 0;
  // Average advance from a representative lowercase sample (real metrics).
  const sample = 'abcdefghijklmnopqrstuvwxyz ';
  final avg = measureText(sample, fontSizePt, metrics: metrics) / sample.length;
  final charsPerLine = avg > 0 ? (widthPt / avg).floor() : 0;
  final maxChars = (lines * charsPerLine).clamp(0, 1 << 30);
  return FieldCapacity(
    maxChars: maxChars,
    lines: lines < 0 ? 0 : lines,
    charsPerLine: charsPerLine < 0 ? 0 : charsPerLine,
  );
}

/// Capacity per field name for every fixed-height field box in [template].
///
/// Only `FormFieldBlock`s with a fixed `style.height` are included (an unbounded
/// box has no capacity limit). Width follows the block's `colSpan` over the
/// content width; font size follows `style.size` or the body size.
Map<String, FieldCapacity> estimateFieldCapacities(
  FormTemplate template, {
  FontMetrics metrics = defaultMetrics,
}) {
  final result = <String, FieldCapacity>{};
  final contentWidthPt = template.layoutPolicy.contentWidth * _mmToPt;
  final bodySize = template.layoutPolicy.fontPolicy.bodySize.toDouble();

  void walk(FormBlock block) {
    switch (block) {
      case FormFieldBlock():
        final height = (block.style?['height'] as num?)?.toDouble();
        if (height != null && height > 0) {
          final span =
              ((block.style?['colSpan'] as num?)?.toInt() ?? 12).clamp(1, 12);
          final width = contentWidthPt * span / 12;
          final size = (block.style?['size'] as num?)?.toDouble() ?? bodySize;
          result[block.fieldName] = estimateCapacity(
            widthPt: width,
            heightPt: height,
            fontSizePt: size,
            metrics: metrics,
          );
        }
      case FormRepeatableBlock():
        for (final b in block.itemTemplate) {
          walk(b);
        }
      case FormConditionalBlock():
        walk(block.thenBlock);
        if (block.elseBlock != null) walk(block.elseBlock!);
      default:
        break;
    }
  }

  for (final section in template.defaultSections) {
    for (final block in section.blocks) {
      walk(block);
    }
  }
  return result;
}
