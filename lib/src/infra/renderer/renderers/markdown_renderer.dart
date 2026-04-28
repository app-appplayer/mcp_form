import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';

import '../render_context.dart';
import '../renderer_registry.dart';

/// Markdown output renderer with GFM extensions.
///
/// Produces standard Markdown with optional YAML front matter
/// for metadata. Uses document.updatedAt for deterministic timestamps.
class MarkdownRenderer implements DocumentRenderer {
  const MarkdownRenderer();

  @override
  List<String> get supportedFormats => const ['markdown'];

  @override
  String? get supportedTemplateRange => '>= 1.0.0 < 2.0.0';

  @override
  Future<FormRenderOutput> render(RenderContext context) async {
    final doc = context.document;
    final buf = StringBuffer();

    // YAML front matter
    if (context.options.includeMetadata) {
      final generatedAt =
          doc.metadata.modifiedAt ?? doc.metadata.createdAt;
      buf.writeln('---');
      buf.writeln('templateId: ${doc.templateId}');
      buf.writeln('templateVersion: ${doc.templateVersion}');
      buf.writeln('author: ${doc.metadata.author}');
      buf.writeln('generatedAt: ${generatedAt.toIso8601String()}');
      buf.writeln('status: ${doc.status.name}');
      buf.writeln('---');
      buf.writeln();
    }

    for (final section in doc.sections) {
      if (section.title != null) {
        buf.writeln('## ${section.title}');
        buf.writeln();
      }
      for (final block in section.blocks) {
        _renderBlock(buf, block, doc.data);
        buf.writeln();
      }
    }

    final content = buf.toString();
    final bytes = utf8.encode(content);

    return FormRenderOutput(
      format: 'markdown',
      content: bytes,
      pageCount: 1,
      fileSize: bytes.length,
      generatedAt: doc.metadata.modifiedAt ?? doc.metadata.createdAt,
    );
  }

  void _renderBlock(
    StringBuffer buf,
    FormBlock block,
    Map<String, dynamic> data,
  ) {
    switch (block) {
      case FormTextBlock():
        buf.writeln(block.content);

      case FormHeadingBlock():
        final level = block.level.clamp(1, 6);
        buf.writeln('${'#' * level} ${block.content}');

      case FormTableBlock():
        if (block.columns.isEmpty) break;

        // Header row
        buf.write('|');
        for (final col in block.columns) {
          buf.write(' ${col.title} |');
        }
        buf.writeln();

        // Separator
        buf.write('|');
        for (var i = 0; i < block.columns.length; i++) {
          buf.write(' --- |');
        }
        buf.writeln();

        // Data rows
        for (final row in block.rows) {
          buf.write('|');
          for (final col in block.columns) {
            final cell = row.cells[col.id];
            buf.write(' ${cell?.toString() ?? ''} |');
          }
          buf.writeln();
        }

      case FormImageBlock():
        final alt = block.alt ?? '';
        buf.writeln('![$alt](${block.src})');

      case FormChartBlock():
        buf.write('> **Chart** (${block.chartType})');
        if (block.unit != null) {
          buf.write(' - Units: ${block.unit}');
        }
        buf.writeln();

      case FormCanvasBlock():
        // Markdown has no native canvas block — emit either an image link
        // (when the resolver downgraded to png) or a callout with the
        // target URI. Caption (if any) goes below as italicised text.
        final alt = block.alt ?? block.caption ?? block.target;
        buf.writeln('![$alt](${block.target})');
        if (block.caption != null) {
          buf.writeln('*${block.caption}*');
        }

      case FormFieldBlock():
        final value = data[block.fieldName];
        final label = block.fieldName;
        if (value != null) {
          buf.writeln('**$label**: $value');
        } else {
          buf.writeln('**$label**: _unfilled_');
        }

      case FormRepeatableBlock():
        for (final tplBlock in block.itemTemplate) {
          _renderBlock(buf, tplBlock, data);
        }

      case FormConditionalBlock():
        // Render thenBlock by default (condition evaluation is external)
        _renderBlock(buf, block.thenBlock, data);

      default:
        break;
    }
  }
}
