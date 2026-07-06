import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/mcp_form.dart';
import 'package:test/test.dart';

void main() {
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
    name: 'Paper',
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
        FormHeadingBlock(
            blockId: 'h', index: 0, content: 'Introduction', level: 1),
        FormTextBlock(blockId: 'p', index: 1, content: 'Body text here.'),
        FormImageBlock(blockId: 'q', index: 2, src: 'qr:https://x.io'),
      ]),
    ],
    metadata: FormDocumentMetadata(author: 'A', createdAt: DateTime(2026)),
  );

  Future<String> render({required bool tagged}) async {
    final out = await const PdfRenderer().render(RenderContext(
      document: doc,
      layoutPolicy: layout,
      template: tpl,
      options: RenderOptions(compress: false, taggedPdf: tagged),
    ));
    return latin1.decode(out.content as List<int>, allowInvalid: true);
  }

  group('tagged PDF (PDF/UA structure)', () {
    test('emits a structure tree with typed elements', () async {
      final pdf = await render(tagged: true);
      expect(pdf, contains('/StructTreeRoot'));
      expect(pdf, contains('/S /Document'));
      expect(pdf, contains('/S /H1')); // heading
      expect(pdf, contains('/S /P')); // paragraph
      expect(pdf, contains('/S /Figure')); // QR image
    });

    test('marks content with MCIDs and page furniture as artifacts', () async {
      final pdf = await render(tagged: true);
      expect(pdf, contains('BDC'));
      expect(pdf, contains('EMC'));
      expect(pdf, contains('/MCID 0'));
      expect(pdf, contains('/Artifact BDC')); // running text / margins
      expect(pdf, contains('/Type /MCR')); // marked-content references
    });

    test('adds ParentTree, StructParents, MarkInfo and Lang', () async {
      final pdf = await render(tagged: true);
      expect(pdf, contains('/ParentTree'));
      expect(pdf, contains('/StructParents 0'));
      expect(pdf, contains('/Marked true'));
      expect(pdf, contains('/Lang (en-US)'));
    });

    test('default (untagged) output has no structure tree', () async {
      final pdf = await render(tagged: false);
      expect(pdf, isNot(contains('/StructTreeRoot')));
      expect(pdf, isNot(contains('BDC')));
    });
  });

  group('tagged PDF nesting (Phase 2/3)', () {
    final nestedDoc = FormDocument(
      documentId: 'd',
      templateId: 't',
      templateVersion: '1.0.0',
      data: const {},
      sections: [
        FormSection(sectionId: 's', index: 0, blocks: [
          FormTextBlock(
              blockId: 'l',
              index: 0,
              content: 'First\nSecond\nThird',
              style: const {'listStyle': 'ordered'}),
          FormTableBlock(
              blockId: 'tb',
              index: 1,
              columns: const [
                FormTableColumn(id: 'a', title: 'Name', type: 'string'),
                FormTableColumn(id: 'b', title: 'Qty', type: 'number'),
              ],
              rows: [
                FormTableRow(cells: const {'a': 'Apple', 'b': '3'})
              ]),
          FormImageBlock(
              blockId: 'img', index: 2, src: 'qr:x', alt: 'Payment QR code'),
        ]),
      ],
      metadata: FormDocumentMetadata(author: 'A', createdAt: DateTime(2026)),
    );

    Future<String> renderNested() async {
      final out = await const PdfRenderer().render(RenderContext(
        document: nestedDoc,
        layoutPolicy: layout,
        template: tpl,
        options: const RenderOptions(compress: false, taggedPdf: true),
      ));
      return latin1.decode(out.content as List<int>, allowInvalid: true);
    }

    test('lists nest L > LI', () async {
      final pdf = await renderNested();
      expect(pdf, contains('/S /L '));
      expect(pdf, contains('/S /LI'));
    });

    test('tables nest Table > TR > TH / TD', () async {
      final pdf = await renderNested();
      expect(pdf, contains('/S /Table'));
      expect(pdf, contains('/S /TR'));
      expect(pdf, contains('/S /TH')); // header cells
      expect(pdf, contains('/S /TD')); // body cells
    });

    test('figures carry an /Alt description', () async {
      final pdf = await renderNested();
      expect(pdf, contains('/Alt (Payment QR code)'));
    });

    test('declares PDF/UA conformance in XMP metadata', () async {
      final pdf = await renderNested();
      expect(pdf, contains('/Metadata'));
      expect(pdf, contains('pdfuaid'));
      expect(pdf, contains('<pdfuaid:part>1</pdfuaid:part>'));
    });
  });
}
