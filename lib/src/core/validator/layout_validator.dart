import 'package:mcp_bundle/mcp_bundle.dart';

import '../template/layout_extensions.dart';

/// Validates layout constraints for a [FormDocument] against its
/// [FormLayoutPolicy].
///
/// Detects potential rendering issues such as content overflow and
/// excessive table rows. Layout violations are reported as warnings.
class LayoutValidator {
  const LayoutValidator();

  /// Validate layout constraints for the given [document].
  ///
  /// Returns a list of [FormValidationIssue] containing layout warnings.
  List<FormValidationIssue> validate({
    required FormDocument document,
    required FormLayoutPolicy layoutPolicy,
  }) {
    final issues = <FormValidationIssue>[];
    final contentH = layoutPolicy.contentHeight;
    final contentW = layoutPolicy.contentWidth;

    for (var si = 0; si < document.sections.length; si++) {
      final section = document.sections[si];
      for (var bi = 0; bi < section.blocks.length; bi++) {
        final block = section.blocks[bi];
        final path = '/sections/$si/blocks/$bi';

        issues.addAll(_validateBlock(
          block: block,
          path: path,
          contentHeight: contentH,
          contentWidth: contentW,
          layoutPolicy: layoutPolicy,
        ));
      }
    }

    return issues;
  }

  List<FormValidationIssue> _validateBlock({
    required FormBlock block,
    required String path,
    required double contentHeight,
    required double contentWidth,
    required FormLayoutPolicy layoutPolicy,
  }) {
    final issues = <FormValidationIssue>[];

    if (block is FormTableBlock) {
      // Table row limit check
      if (layoutPolicy.maxTableRows != null &&
          block.rows.length > layoutPolicy.maxTableRows!) {
        issues.add(FormValidationIssue(
          code: 'layout.table_overflow',
          message:
              'Table at $path has ${block.rows.length} rows '
              '(maxTableRows: ${layoutPolicy.maxTableRows})',
          path: path,
          severity: 'warning',
        ));
      }

      if (block.maxRows != null && block.rows.length > block.maxRows!) {
        issues.add(FormValidationIssue(
          code: 'layout.table_overflow',
          message:
              'Table at $path has ${block.rows.length} rows '
              '(maxRows: ${block.maxRows})',
          path: path,
          severity: 'warning',
        ));
      }
    }

    if (block is FormImageBlock) {
      // Image aspect ratio check
      if (block.aspectRatio != null) {
        if (block.aspectRatio! < 0.25 || block.aspectRatio! > 4.0) {
          issues.add(FormValidationIssue(
            code: 'layout.image_ratio',
            message:
                'Image at $path has aspect ratio ${block.aspectRatio} '
                '(acceptable range: 0.25 - 4.0)',
            path: path,
            severity: 'warning',
          ));
        }
      }
    }

    if (block is FormTextBlock) {
      // Estimate text height based on content length
      final estimatedLines = _estimateLineCount(
        block.content,
        contentWidth,
        layoutPolicy.fontPolicy.bodySize,
      );
      final lineHeight = layoutPolicy.fontPolicy.bodySize * 0.3528 * 1.4;
      final estimatedHeight = estimatedLines * lineHeight;

      if (estimatedHeight > contentHeight) {
        issues.add(FormValidationIssue(
          code: 'layout.overflow',
          message:
              'TextBlock at $path may overflow page '
              '(estimated ${estimatedHeight.toStringAsFixed(1)}mm, '
              'page height ${contentHeight.toStringAsFixed(1)}mm)',
          path: path,
          severity: 'warning',
        ));
      }
    }

    if (block is FormRepeatableBlock) {
      if (block.maxItems == null && block.minItems != null) {
        issues.add(FormValidationIssue(
          code: 'layout.constraint_violation',
          message:
              'RepeatableBlock at $path has no maxItems bound',
          path: path,
          severity: 'warning',
        ));
      }
    }

    return issues;
  }

  int _estimateLineCount(
    String content,
    double contentWidthMm,
    double fontSizePt,
  ) {
    // Rough estimation: average char width ~= fontSize * 0.6 * 0.3528 mm
    final avgCharWidthMm = fontSizePt * 0.6 * 0.3528;
    if (avgCharWidthMm <= 0) return 1;
    final charsPerLine = (contentWidthMm / avgCharWidthMm).floor();
    if (charsPerLine <= 0) return 1;
    return (content.length / charsPerLine).ceil().clamp(1, 10000);
  }
}
