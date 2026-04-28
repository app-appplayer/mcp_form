import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';

import '../../../core/template/layout_extensions.dart';
import '../render_context.dart';
import '../renderer_registry.dart';

/// HTML5 output renderer.
///
/// Produces self-contained HTML with embedded CSS derived from
/// the document's [FormLayoutPolicy].
class HtmlRenderer implements DocumentRenderer {
  const HtmlRenderer();

  @override
  List<String> get supportedFormats => const ['html'];

  @override
  String? get supportedTemplateRange => '>= 1.0.0 < 2.0.0';

  @override
  Future<FormRenderOutput> render(RenderContext context) async {
    final doc = context.document;
    final layout = context.layoutPolicy;
    final buf = StringBuffer();

    buf.writeln('<!DOCTYPE html>');
    buf.writeln('<html lang="en">');
    buf.writeln('<head>');
    buf.writeln('<meta charset="UTF-8">');
    buf.writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
    );

    if (context.options.includeMetadata) {
      buf.writeln('<meta name="author" content="${doc.metadata.author}">');
      buf.writeln(
        '<meta name="templateId" content="${doc.templateId}">',
      );
    }

    buf.writeln('<title>${context.template.name}</title>');
    buf.writeln('<style>');
    _writeStyles(buf, layout);
    buf.writeln('</style>');
    buf.writeln('</head>');
    buf.writeln('<body>');
    buf.writeln('<div class="document">');

    for (final section in doc.sections) {
      buf.writeln('<section>');
      if (section.title != null) {
        buf.writeln('<h2>${_escape(section.title!)}</h2>');
      }
      for (final block in section.blocks) {
        _renderBlock(buf, block, doc.data);
      }
      buf.writeln('</section>');
    }

    buf.writeln('</div>');

    if (context.effectiveWatermark != null) {
      buf.writeln(
        '<div class="watermark">${_escape(context.effectiveWatermark!)}</div>',
      );
    }

    buf.writeln('</body>');
    buf.writeln('</html>');

    final content = buf.toString();
    final bytes = utf8.encode(content);

    return FormRenderOutput(
      format: 'html',
      content: bytes,
      pageCount: 1,
      fileSize: bytes.length,
      generatedAt: doc.metadata.modifiedAt ?? doc.metadata.createdAt,
    );
  }

  void _writeStyles(StringBuffer buf, FormLayoutPolicy layout) {
    final contentWidth = layout.contentWidth;
    final fontPolicy = layout.fontPolicy;

    buf.writeln('body {');
    buf.writeln('  font-family: ${layout.fontFamily}, sans-serif;');
    buf.writeln('  font-size: ${fontPolicy.bodySize}pt;');
    buf.writeln('  max-width: ${contentWidth}mm;');
    buf.writeln('  margin: 0 auto;');
    buf.writeln('  padding: ${layout.margins.top}mm ${layout.margins.right}mm '
        '${layout.margins.bottom}mm ${layout.margins.left}mm;');
    buf.writeln('}');

    buf.writeln('h1, h2, h3, h4, h5, h6 {');
    buf.writeln('  font-size: ${fontPolicy.headingSize}pt;');
    buf.writeln('}');

    buf.writeln('table { border-collapse: collapse; width: 100%; }');
    buf.writeln(
      'th, td { border: 1px solid #ccc; padding: 8px; text-align: left; }',
    );
    buf.writeln('th { background-color: #f5f5f5; }');

    buf.writeln('.form-field { margin: 8px 0; }');
    buf.writeln(
      '.form-field.unfilled { color: #999; font-style: italic; }',
    );

    if (layout.autoWrap) {
      buf.writeln('p { word-wrap: break-word; }');
    }

    buf.writeln('.watermark {');
    buf.writeln('  position: fixed; top: 50%; left: 50%;');
    buf.writeln('  transform: translate(-50%, -50%) rotate(-45deg);');
    buf.writeln('  font-size: 60pt; color: rgba(0,0,0,0.1);');
    buf.writeln('  pointer-events: none; z-index: 1000;');
    buf.writeln('}');
  }

  void _renderBlock(
    StringBuffer buf,
    FormBlock block,
    Map<String, dynamic> data,
  ) {
    switch (block) {
      case FormTextBlock():
        buf.writeln('<p>${_escape(block.content)}</p>');

      case FormHeadingBlock():
        final level = block.level.clamp(1, 6);
        buf.writeln('<h$level>${_escape(block.content)}</h$level>');

      case FormTableBlock():
        buf.writeln('<table>');
        buf.writeln('<thead><tr>');
        for (final col in block.columns) {
          buf.writeln('<th>${_escape(col.title)}</th>');
        }
        buf.writeln('</tr></thead>');
        buf.writeln('<tbody>');
        for (final row in block.rows) {
          buf.writeln('<tr>');
          for (final col in block.columns) {
            final cell = row.cells[col.id];
            buf.writeln('<td>${_escape(cell?.toString() ?? '')}</td>');
          }
          buf.writeln('</tr>');
        }
        buf.writeln('</tbody>');
        buf.writeln('</table>');

      case FormImageBlock():
        buf.writeln('<figure>');
        buf.write('<img src="${_escape(block.src)}"');
        if (block.alt != null) buf.write(' alt="${_escape(block.alt!)}"');
        if (block.maxWidth != null) {
          buf.write(' style="max-width: ${block.maxWidth}px"');
        }
        buf.writeln('>');
        buf.writeln('</figure>');

      case FormChartBlock():
        buf.writeln(
          '<div class="chart" data-type="${block.chartType}">',
        );
        buf.writeln(
          '<p><strong>Chart</strong> (${block.chartType})</p>',
        );
        buf.writeln('</div>');

      case FormCanvasBlock():
        // Scene-live embed. Prefer inline SVG when the resolver pre-
        // injected one under `data[block.blockId]` as a
        // CanvasRenderResult-shaped Map; otherwise emit a placeholder
        // with the target URI for downstream resolution.
        buf.writeln(
          '<figure class="canvas" data-target="${_escape(block.target)}" data-mode="${_escape(block.mode)}">',
        );
        final resolved = data[block.blockId];
        if (resolved is Map && resolved['format'] == 'svg' && resolved['svg'] is String) {
          buf.writeln(resolved['svg'] as String);
        } else if (resolved is Map && resolved['format'] == 'png' && resolved['bytes'] is List) {
          // byte-encoded preview omitted in minimal stub — fall through to
          // the <img> placeholder with the resolver URI.
          buf.writeln('<img src="${_escape(block.target)}" alt="${_escape(block.alt ?? block.target)}">');
        } else {
          buf.writeln(
            '<div class="canvas-placeholder"><code>${_escape(block.target)}</code></div>',
          );
        }
        if (block.caption != null) {
          buf.writeln('<figcaption>${_escape(block.caption!)}</figcaption>');
        }
        buf.writeln('</figure>');

      case FormFieldBlock():
        final value = data[block.fieldName];
        final filled = value != null;
        final cssClass = filled ? 'form-field' : 'form-field unfilled';
        buf.writeln('<div class="$cssClass">');
        buf.writeln(
          '<strong>${_escape(block.fieldName)}</strong>: ',
        );
        buf.writeln(filled ? _escape(value.toString()) : '<em>unfilled</em>');
        buf.writeln('</div>');

      case FormRepeatableBlock():
        buf.writeln('<div class="repeatable">');
        for (final tplBlock in block.itemTemplate) {
          _renderBlock(buf, tplBlock, data);
        }
        buf.writeln('</div>');

      case FormConditionalBlock():
        // Render thenBlock by default (condition evaluation is external)
        _renderBlock(buf, block.thenBlock, data);

      default:
        break;
    }
  }

  String _escape(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}
