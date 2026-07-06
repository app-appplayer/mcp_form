import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/pdf_renderer.dart';
import 'package:test/test.dart';

FormLayoutPolicy _layout() => const FormLayoutPolicy(
      pageSize: FormPageSize(size: 'A4', width: 210, height: 297),
      margins: FormMargins(top: 20, right: 20, bottom: 20, left: 20),
      fontPolicy: FormFontPolicy(
          defaultFont: 'x',
          defaultSize: 12,
          headingSize: 18,
          bodySize: 12,
          minSize: 8),
    );

RenderContext _ctx(int columns, {int lines = 120}) {
  final layout = _layout();
  return RenderContext(
    document: FormDocument(
      documentId: 'd',
      templateId: 't',
      templateVersion: '1.0.0',
      metadata: FormDocumentMetadata(author: 'a', createdAt: DateTime(2026)),
      sections: [
        FormSection(sectionId: 's', index: 0, blocks: [
          for (var i = 0; i < lines; i++)
            FormTextBlock(blockId: 't$i', index: i, content: 'Line $i of flowing body content'),
        ]),
      ],
    ),
    layoutPolicy: layout,
    template: FormTemplate(
        templateId: 't',
        version: '1.0.0',
        name: 'T',
        schema: const FormSchema(),
        layoutPolicy: layout),
    options: RenderOptions(columnCount: columns, compress: false),
  );
}

String _str(FormRenderOutput o) =>
    latin1.decode(o.content as List<int>, allowInvalid: true);

Set<double> _tdXs(String pdf) => RegExp(r'(\d+\.\d+) \d+\.\d+ Td')
    .allMatches(pdf)
    .map((m) => double.parse(m.group(1)!))
    .toSet();

void main() {
  group('multi-column flow', () {
    test('single column is the default and uses one text origin', () async {
      final out = await const PdfRenderer().render(_ctx(1, lines: 10));
      final xs = _tdXs(_str(out));
      // All lines share the left margin x (~56.7pt for a 20mm margin).
      expect(xs.length, 1);
      expect(xs.first, closeTo(20 * 2.8346, 1));
    });

    test('two columns place text at two distinct x origins', () async {
      final out = await const PdfRenderer().render(_ctx(2));
      final xs = _tdXs(_str(out)).toList()..sort();
      // Column 0 at the left margin; column 1 further right.
      expect(xs.length, greaterThanOrEqualTo(2));
      const left = 20 * 2.8346;
      const full = (210 - 40) * 2.8346;
      const colW = (full - 18) / 2;
      const col1 = left + colW + 18;
      expect(xs.first, closeTo(left, 1));
      expect(xs.any((x) => (x - col1).abs() < 1), isTrue);
    });

    test('two columns fit the same content in fewer pages', () async {
      final one = await const PdfRenderer().render(_ctx(1));
      final two = await const PdfRenderer().render(_ctx(2));
      expect(two.pageCount, lessThan(one.pageCount));
    });

    test('columnCount is ignored in continuous flow', () async {
      final out = await const PdfRenderer().render(RenderContext(
        document: _ctx(3, lines: 5).document,
        layoutPolicy: _layout(),
        template: _ctx(3, lines: 5).template,
        options:
            const RenderOptions(columnCount: 3, pageFlow: PageFlow.continuous, compress: false),
      ));
      // One growing page, single column origin.
      expect(out.pageCount, 1);
      expect(_tdXs(_str(out)).length, 1);
    });
  });
}
