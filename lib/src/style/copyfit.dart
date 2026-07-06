import 'block_style.dart';
import 'font_metrics.dart';
import 'inline_run.dart';
import 'text_measure.dart';
import 'text_run_style.dart';

/// Outcome of fitting rich content into a (possibly fixed-height) box.
class FitResult {
  FitResult({
    required this.lines,
    required this.scale,
    required this.overflowed,
    this.droppedLines = 0,
    this.targetChars,
  });

  /// Lines to draw (already wrapped and, for `clip`, truncated).
  final List<TextLine> lines;

  /// Font scale that was applied (`1.0` unless `shrinkToFit` reduced it).
  final double scale;

  /// True when content exceeded the box at the natural size.
  final bool overflowed;

  /// Lines removed by `clip`.
  final int droppedLines;

  /// For `summarize`: a suggested character budget for the box, which an
  /// upstream LLM / binding can use to condense the value. Null otherwise.
  final int? targetChars;
}

/// Fit [rich] into a box [widthPt] wide using [base] as the resolved style.
///
/// When [maxHeightPt] is null the box grows freely (only wrapping applies).
/// Otherwise the [overflow] policy decides what happens when the wrapped
/// content is taller than the box. [minSize] bounds `shrinkToFit`.
FitResult fitText(
  FormRichText rich,
  double widthPt,
  TextRunStyle base, {
  double? maxHeightPt,
  double lineHeightMul = 1.4,
  double minSize = 8,
  BlockOverflow overflow = BlockOverflow.grow,
  bool wrap = true,
  FontMetrics metrics = defaultMetrics,
}) {
  List<TextLine> measure([double scale = 1.0]) => wrapRichText(rich, widthPt,
      base, scale: scale, wrap: wrap, metrics: metrics);

  final natural = measure();
  if (maxHeightPt == null ||
      overflow == BlockOverflow.grow ||
      overflow == BlockOverflow.split) {
    final over = maxHeightPt != null &&
        linesHeight(natural, lineHeightMul) > maxHeightPt;
    return FitResult(lines: natural, scale: 1.0, overflowed: over);
  }

  if (linesHeight(natural, lineHeightMul) <= maxHeightPt) {
    return FitResult(lines: natural, scale: 1.0, overflowed: false);
  }

  switch (overflow) {
    case BlockOverflow.shrinkToFit:
      final baseSize = base.fontSize ?? 12;
      final floorScale = baseSize <= 0 ? 1.0 : minSize / baseSize;
      var scale = 1.0;
      var lines = natural;
      // Step down until it fits or hits the minimum size.
      while (scale > floorScale) {
        scale = (scale - 0.05).clamp(floorScale, 1.0);
        lines = measure(scale);
        if (linesHeight(lines, lineHeightMul) <= maxHeightPt) {
          return FitResult(lines: lines, scale: scale, overflowed: false);
        }
      }
      return FitResult(lines: lines, scale: scale, overflowed: true);

    case BlockOverflow.clip:
      final kept = <TextLine>[];
      var h = 0.0;
      for (final l in natural) {
        final lh = l.maxSize * lineHeightMul;
        if (h + lh > maxHeightPt) break;
        h += lh;
        kept.add(l);
      }
      return FitResult(
        lines: kept,
        scale: 1.0,
        overflowed: true,
        droppedLines: natural.length - kept.length,
      );

    case BlockOverflow.summarize:
      // Estimate how many characters fit and report the budget; keep all lines
      // so a caller that ignores the hint still sees the full (overflowing)
      // content rather than silent truncation.
      var fitLines = 0;
      var h = 0.0;
      for (final l in natural) {
        final lh = l.maxSize * lineHeightMul;
        if (h + lh > maxHeightPt) break;
        h += lh;
        fitLines++;
      }
      final totalChars = rich.plainText.length;
      final ratio = natural.isEmpty ? 1.0 : fitLines / natural.length;
      final target = (totalChars * ratio).floor().clamp(0, totalChars);
      return FitResult(
        lines: natural,
        scale: 1.0,
        overflowed: true,
        targetChars: target,
      );

    case BlockOverflow.grow:
    case BlockOverflow.split:
      return FitResult(lines: natural, scale: 1.0, overflowed: true);
  }
}
