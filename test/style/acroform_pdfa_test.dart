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
    name: 'Application Form',
    schema: const FormSchema(),
    layoutPolicy: layout,
  );
  final doc = FormDocument(
    documentId: 'd1',
    templateId: 't',
    templateVersion: '1.0.0',
    data: const {'name': 'Jane'},
    sections: [
      FormSection(sectionId: 's', index: 0, blocks: [
        FormFieldBlock(
            blockId: 'f1', index: 0, fieldName: 'name', fieldType: 'text'),
        FormFieldBlock(
            blockId: 'f2', index: 1, fieldName: 'email', fieldType: 'text'),
      ]),
    ],
    metadata: FormDocumentMetadata(author: 'MakeMind', createdAt: DateTime(2026)),
  );

  RenderContext ctx(RenderOptions opts) => RenderContext(
      document: doc, layoutPolicy: layout, template: tpl, options: opts);

  Future<String> renderPdf(RenderOptions opts) async {
    final out = await const PdfRenderer().render(ctx(opts));
    return latin1.decode(out.content as List<int>, allowInvalid: true);
  }

  group('AcroForm fillable fields', () {
    test('emits interactive text-field widgets with prefilled values', () async {
      final pdf = await renderPdf(
          const RenderOptions(compress: false, fillableFields: true));
      expect(pdf, contains('/AcroForm'));
      expect(pdf, contains('/Subtype /Widget'));
      expect(pdf, contains('/FT /Tx'));
      expect(pdf, contains('/T (name)'));
      expect(pdf, contains('/T (email)'));
      expect(pdf, contains('/V (Jane)')); // bound value prefilled
      expect(pdf, contains('/NeedAppearances true'));
    });

    test('default (static) rendering has no AcroForm', () async {
      final pdf = await renderPdf(const RenderOptions(compress: false));
      expect(pdf, isNot(contains('/AcroForm')));
      expect(pdf, contains('name: Jane')); // static text instead
    });
  });

  group('PDF/A archival metadata', () {
    test('adds XMP metadata, document ID and MarkInfo', () async {
      final pdf =
          await renderPdf(const RenderOptions(compress: false, pdfA: true));
      expect(pdf, contains('/Metadata'));
      expect(pdf, contains('pdfaid:part'));
      expect(pdf, contains('pdfaid:conformance'));
      expect(pdf, contains('/MarkInfo'));
      expect(pdf, contains('/ID [<'));
      expect(pdf, contains('Application Form')); // dc:title
    });

    test('the document ID is deterministic', () async {
      final a = await renderPdf(const RenderOptions(compress: false, pdfA: true));
      final b = await renderPdf(const RenderOptions(compress: false, pdfA: true));
      final idRe = RegExp(r'/ID \[<([0-9a-f]+)>');
      expect(idRe.firstMatch(a)!.group(1), idRe.firstMatch(b)!.group(1));
    });

    test('default output has no PDF/A metadata', () async {
      final pdf = await renderPdf(const RenderOptions(compress: false));
      expect(pdf, isNot(contains('/Metadata')));
      expect(pdf, isNot(contains('/ID [<')));
    });
  });
}
