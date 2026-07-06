import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';

import '../../../core/binding/repeatable_binding.dart';
import '../../../core/condition/condition_evaluator.dart';
import '../../../core/document/document_numbering.dart';
import '../../../style/style.dart';
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
    final numbering = DocumentNumbering.compute(doc.sections);
    final footnotes = FootnoteCollector();
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

    final logo = context.styleSheet?.theme.logo;
    if (logo != null && logo.isNotEmpty) {
      buf.writeln('![logo]($logo)');
      buf.writeln();
    }

    for (final section in doc.sections) {
      if (section.title != null) {
        buf.writeln('## ${section.title}');
        buf.writeln();
      }
      for (final block in section.blocks) {
        _renderBlock(buf, block, doc.data, numbering, footnotes);
        buf.writeln();
      }
    }

    if (!footnotes.isEmpty) {
      buf.writeln('---');
      buf.writeln();
      buf.writeln('**Notes**');
      buf.writeln();
      final notes = footnotes.notes;
      for (var i = 0; i < notes.length; i++) {
        buf.writeln('${i + 1}. ${notes[i]}');
      }
      buf.writeln();
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
    DocumentNumbering numbering,
    FootnoteCollector footnotes,
  ) {
    switch (block) {
      case FormTextBlock():
        if (block.style?['math'] == true) {
          buf.writeln('\$\$${block.content}\$\$');
          break;
        }
        if (block.style?['toc'] == true) {
          final title = block.content.trim();
          if (title.isNotEmpty) {
            buf.writeln('**$title**');
            buf.writeln();
          }
          for (final e in numbering.tocEntries) {
            final indent = '  ' * (e.level - 1);
            final prefix = e.number.isEmpty ? '' : '${e.number} ';
            buf.writeln('$indent- $prefix${e.text}');
          }
          break;
        }
        final listStyle = block.style?['listStyle'] as String?;
        if (isListStyle(listStyle)) {
          final ordered = listStyle == 'ordered';
          var n = 1;
          for (final raw in block.content.split('\n')) {
            if (raw.trim().isEmpty) continue;
            final line = footnotes.consume(applyCrossRefs(raw.trim(), numbering));
            buf.writeln(ordered ? '${n++}. $line' : '- $line');
          }
          buf.writeln();
        } else {
          final text =
              footnotes.consume(applyCrossRefs(block.content, numbering));
          final change = block.style?['change'] as String?;
          if (change == 'deleted') {
            buf.writeln('~~$text~~');
          } else if (change == 'inserted') {
            buf.writeln('<ins>$text</ins>');
          } else {
            buf.writeln(text);
          }
        }

      case FormHeadingBlock():
        final level = block.level.clamp(1, 6);
        final number = numbering.headingNumber(block.blockId);
        final text = footnotes.consume(applyCrossRefs(block.content, numbering));
        final body = number != null ? '$number $text' : text;
        buf.writeln('${'#' * level} $body');

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
        _writeCaption(buf, block, numbering);

      case FormImageBlock():
        final alt = block.alt ?? '';
        buf.writeln('![$alt](${block.src})');
        _writeCaption(buf, block, numbering);

      case FormChartBlock():
        buf.write('> **Chart** (${block.chartType})');
        if (block.unit != null) {
          buf.write(' - Units: ${block.unit}');
        }
        buf.writeln();
        _writeCaption(buf, block, numbering);

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
        for (final item in resolveRepeatableItems(block, data)) {
          for (final tplBlock in block.itemTemplate) {
            _renderBlock(buf, tplBlock, item, numbering, footnotes);
          }
        }

      case FormConditionalBlock():
        if (evaluateCondition(block.condition, data)) {
          _renderBlock(buf, block.thenBlock, data, numbering, footnotes);
        } else if (block.elseBlock != null) {
          _renderBlock(buf, block.elseBlock!, data, numbering, footnotes);
        }

      default:
        break;
    }
  }

  /// Emit an auto-numbered caption ("*Figure 1: ...*") under a figure / table
  /// when the block carries a caption; no-op otherwise.
  void _writeCaption(
    StringBuffer buf,
    FormBlock block,
    DocumentNumbering numbering,
  ) {
    final label = numbering.captionLabel(block.blockId);
    if (label == null) return;
    final caption = block.style?['caption'] as String?;
    final text =
        caption == null || caption.isEmpty ? label : '$label: $caption';
    buf.writeln('*$text*');
  }
}
