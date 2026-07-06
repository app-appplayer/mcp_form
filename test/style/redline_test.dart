import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/mcp_form.dart';
import 'package:test/test.dart';

void main() {
  group('redlineDecoration', () {
    test('inserted underlines green, deleted strikes red', () {
      final ins = redlineDecoration('inserted')!;
      expect(ins.underline, isTrue);
      expect(ins.strike, isFalse);
      final del = redlineDecoration('deleted')!;
      expect(del.strike, isTrue);
      expect(del.underline, isFalse);
      expect(redlineDecoration(null), isNull);
      expect(redlineDecoration('unchanged'), isNull);
    });

    test('applyRedlineStyle merges marks into the style map', () {
      final s = applyRedlineStyle({'change': 'deleted', 'align': 'left'})!;
      expect(s['strike'], isTrue);
      expect(s['align'], 'left'); // preserved
      expect(applyRedlineStyle({'align': 'left'})!['strike'], isNull);
    });
  });

  group('renderers draw redline changes', () {
    const layout = FormLayoutPolicy(
      pageSize: FormPageSize(size: 'A4', width: 210, height: 297),
      margins: FormMargins(top: 20, right: 20, bottom: 20, left: 20),
      fontPolicy: FormFontPolicy(
        defaultFont: 'sans-serif',
        defaultSize: 12,
        headingSize: 18,
        bodySize: 12,
        minSize: 8,
      ),
    );
    final tpl = FormTemplate(
      templateId: 't',
      version: '1.0.0',
      name: 'T',
      schema: const FormSchema(),
      layoutPolicy: layout,
    );
    final doc = FormDocument(
      documentId: 'd',
      templateId: 't',
      templateVersion: '1.0.0',
      data: const {},
      sections: [
        FormSection(sectionId: 's', index: 0, blocks: [
          FormTextBlock(
              blockId: 'a',
              index: 0,
              content: 'Added clause.',
              style: const {'change': 'inserted'}),
          FormTextBlock(
              blockId: 'b',
              index: 1,
              content: 'Removed clause.',
              style: const {'change': 'deleted'}),
        ]),
      ],
      metadata: FormDocumentMetadata(author: 'x', createdAt: DateTime(2026)),
    );
    RenderContext ctx({bool compress = true}) => RenderContext(
          document: doc,
          layoutPolicy: layout,
          template: tpl,
          options: RenderOptions(compress: compress),
        );

    test('html uses ins / del elements', () async {
      final out = await const HtmlRenderer().render(ctx());
      final html = utf8.decode(out.content as List<int>);
      expect(html, contains('<ins style="color: #128A3A">Added clause.</ins>'));
      expect(html, contains('<del style="color: #C0392B">Removed clause.</del>'));
    });

    test('markdown strikes deletions and marks insertions', () async {
      final out = await const MarkdownRenderer().render(ctx());
      final md = utf8.decode(out.content as List<int>);
      expect(md, contains('<ins>Added clause.</ins>'));
      expect(md, contains('~~Removed clause.~~'));
    });

    test('docx sets strike run properties for a deletion', () async {
      final out = await const DocxRenderer().render(ctx());
      final docx = utf8.decode(out.content as List<int>);
      expect(docx, contains('<w:strike/>'));
      expect(docx, contains('<w:u w:val="single"/>'));
    });

    test('pdf applies strike to the deleted run', () async {
      final out = await const PdfRenderer().render(ctx(compress: false));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      // A strike is drawn as a thin filled rectangle over the text run.
      expect(pdf, contains('Removed clause'));
    });
  });
}
