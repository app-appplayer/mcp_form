import 'package:mcp_bundle/mcp_bundle.dart';

import '../../core/template/layout_extensions.dart';

/// Pre-render layout validation.
///
/// Checks document content against layout policy constraints and
/// returns warnings for potential rendering issues. Does not prevent
/// rendering — issues are informational.
class LayoutEnforcer {
  const LayoutEnforcer();

  /// Validate a document against its layout policy before rendering.
  List<String> preValidate({
    required FormDocument document,
    required FormLayoutPolicy layoutPolicy,
  }) {
    final warnings = <String>[];
    final contentH = layoutPolicy.contentHeight;

    for (var si = 0; si < document.sections.length; si++) {
      final section = document.sections[si];
      for (var bi = 0; bi < section.blocks.length; bi++) {
        final block = section.blocks[bi];
        final path = '/sections/$si/blocks/$bi';

        if (block is FormTableBlock) {
          if (layoutPolicy.maxTableRows != null &&
              block.rows.length > layoutPolicy.maxTableRows!) {
            warnings.add(
              'layout.table_overflow: Table at $path has '
              '${block.rows.length} rows (max: ${layoutPolicy.maxTableRows})',
            );
          }
        }

        if (block is FormTextBlock) {
          final estimatedHeight = _estimateTextHeight(
            block.content,
            layoutPolicy.contentWidth,
            layoutPolicy.fontPolicy.bodySize,
          );
          if (estimatedHeight > contentH) {
            warnings.add(
              'layout.text_overflow: Text at $path may overflow page',
            );
          }
        }
      }
    }

    return warnings;
  }

  double _estimateTextHeight(
    String content,
    double contentWidthMm,
    double fontSizePt,
  ) {
    final avgCharWidthMm = fontSizePt * 0.6 * 0.3528;
    if (avgCharWidthMm <= 0) return 0;
    final charsPerLine = (contentWidthMm / avgCharWidthMm).floor();
    if (charsPerLine <= 0) return 0;
    final lines = (content.length / charsPerLine).ceil().clamp(1, 10000);
    final lineHeight = fontSizePt * 0.3528 * 1.4;
    return lines * lineHeight;
  }
}
