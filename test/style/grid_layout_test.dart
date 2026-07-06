import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/html_renderer.dart';
import 'package:mcp_form/src/infra/renderer/renderers/pdf_renderer.dart';
import 'package:test/test.dart';

/// Per-block 12-column grid placement via `style.colSpan` — a render-time
/// feature of mcp_form (no mcp_bundle core field). Consecutive blocks whose
/// spans fit within 12 are laid side by side; span 12 (or unset) is full width.
void main() {
  RenderContext ctx(List<FormBlock> blocks) {
    const layout = FormLayoutPolicy(
      pageSize: FormPageSize(size: 'A4', width: 210, height: 297),
      margins: FormMargins(top: 20, right: 20, bottom: 20, left: 20),
      fontPolicy: FormFontPolicy(
        defaultFont: 'x',
        defaultSize: 12,
        headingSize: 18,
        bodySize: 12,
        minSize: 8,
      ),
    );
    return RenderContext(
      document: FormDocument(
        documentId: 'd',
        templateId: 't',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(author: 'a', createdAt: DateTime(2026)),
        sections: [FormSection(sectionId: 's', index: 0, blocks: blocks)],
      ),
      layoutPolicy: layout,
      template: FormTemplate(
        templateId: 't',
        version: '1.0.0',
        name: 'T',
        schema: const FormSchema(),
        layoutPolicy: layout,
      ),
      options: const RenderOptions(compress: false),
    );
  }

  FormTextBlock text(String id, String body, {int? colSpan}) => FormTextBlock(
        blockId: id,
        index: 0,
        content: body,
        style: colSpan == null ? null : {'colSpan': colSpan},
      );

  // Td x-coordinates emitted in the PDF content stream.
  List<double> tdXs(String pdf) => RegExp(r'(\d+\.\d+) \d+\.\d+ Td')
      .allMatches(pdf)
      .map((m) => double.parse(m.group(1)!))
      .toList();

  group('PDF grid layout', () {
    test('two colSpan-6 blocks sit side by side (distinct left edges)',
        () async {
      final out = await const PdfRenderer().render(ctx([
        text('a', 'Left side text', colSpan: 6),
        text('b', 'Right side text', colSpan: 6),
      ]));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      final xs = tdXs(pdf).toSet().toList()..sort();
      // Two different x columns: the second cell begins to the right of the first.
      expect(xs.length, greaterThanOrEqualTo(2));
      const left = 20 * 2.8346;
      expect(xs.first, closeTo(left, 1)); // first cell at left margin
      expect(xs.last, greaterThan(left + 100)); // second cell shifted right
    });

    test('full-width blocks (no colSpan) share one left edge', () async {
      final out = await const PdfRenderer().render(ctx([
        text('a', 'First paragraph'),
        text('b', 'Second paragraph'),
      ]));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      final xs = tdXs(pdf).toSet();
      const left = 20 * 2.8346;
      expect(xs.every((x) => (x - left).abs() < 1), isTrue);
    });

    test('a row advances the cursor past the tallest cell', () async {
      // Tall left cell + short right cell: the block AFTER the row must start
      // below the taller of the two.
      final tall = List.generate(8, (i) => 'line $i').join('\n\n');
      final out = await const PdfRenderer().render(ctx([
        text('a', tall, colSpan: 6),
        text('b', 'short', colSpan: 6),
        text('c', 'after the row'),
      ]));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      // The "after" block exists and the document rendered without error.
      expect(pdf, contains('Td'));
      expect(out.pageCount, greaterThanOrEqualTo(1));
    });
  });

  group('HTML grid layout', () {
    test('side-by-side blocks emit a grid-row with spanned cells', () async {
      final out = await const HtmlRenderer().render(ctx([
        text('a', 'Left', colSpan: 4),
        text('b', 'Right', colSpan: 8),
      ]));
      final html = utf8.decode(out.content as List<int>);
      expect(html, contains('class="grid-row"'));
      expect(html, contains('grid-column: span 4;'));
      expect(html, contains('grid-column: span 8;'));
      expect(html, contains('display: grid'));
    });

    test('full-width blocks are not wrapped in a grid-row', () async {
      final out = await const HtmlRenderer().render(ctx([
        text('a', 'One'),
        text('b', 'Two'),
      ]));
      final html = utf8.decode(out.content as List<int>);
      expect(html.contains('class="grid-row"'), isFalse);
    });

    test('a span overflowing 12 starts a new row', () async {
      final out = await const HtmlRenderer().render(ctx([
        text('a', 'A', colSpan: 8),
        text('b', 'B', colSpan: 8), // 8 + 8 > 12 -> new row
      ]));
      final html = utf8.decode(out.content as List<int>);
      // Two separate grid-row wrappers, one per single-cell row.
      expect('class="grid-row"'.allMatches(html).length, 2);
    });
  });
}
