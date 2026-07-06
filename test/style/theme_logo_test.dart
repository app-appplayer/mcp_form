import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/mcp_form.dart';
import 'package:test/test.dart';

// A small solid 4x4 PNG (data URI) the image package decodes, for the PDF path.
const _pngDataUri =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAA'
    'FElEQVR4AWPhqjjBAAMsDEgANwcAQfIBWwI/PhMAAAAASUVORK5CYII=';

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
        FormTextBlock(blockId: 'p', index: 0, content: 'Body text.'),
      ]),
    ],
    metadata: FormDocumentMetadata(author: 'x', createdAt: DateTime(2026)),
  );

  RenderContext ctx(FormStyleSheet sheet, {bool compress = true}) =>
      RenderContext(
        document: doc,
        layoutPolicy: layout,
        template: tpl,
        styleSheet: sheet,
        options: RenderOptions(compress: compress),
      );

  group('FormTheme logo + baseFontSize round-trip', () {
    test('fromMap/toMap preserves logo and baseFontSize', () {
      const theme = FormTheme(
        baseFontSize: 14,
        logo: 'logo.png',
        logoWidth: 80,
      );
      final back = FormTheme.fromMap(theme.toMap());
      expect(back.baseFontSize, 14);
      expect(back.logo, 'logo.png');
      expect(back.logoWidth, 80);
    });
  });

  group('theme applied by renderers', () {
    test('html applies baseFontSize and emits a logo img', () async {
      final out = await const HtmlRenderer().render(ctx(
        const FormStyleSheet(
          theme: FormTheme(baseFontSize: 15, logo: 'brand.png', logoWidth: 90),
        ),
      ));
      final html = utf8.decode(out.content as List<int>);
      expect(html, contains('body { font-size: 15.0pt; }'));
      expect(html, contains('<img class="logo" src="brand.png"'));
      expect(html, contains('.logo { display: block; width: 90.0px;'));
    });

    test('markdown emits a logo image at the top', () async {
      final out = await const MarkdownRenderer().render(ctx(
        const FormStyleSheet(theme: FormTheme(logo: 'brand.png')),
      ));
      final md = utf8.decode(out.content as List<int>);
      expect(md, contains('![logo](brand.png)'));
    });

    test('docx applies baseFontSize to the Normal style', () async {
      final out = await const DocxRenderer().render(ctx(
        const FormStyleSheet(theme: FormTheme(baseFontSize: 20)),
      ));
      final docx = utf8.decode(out.content as List<int>);
      // 20pt -> 40 half-points in the Normal style.
      expect(docx, contains('<w:sz w:val="40"/>'));
      // No logo paragraph for this themeless-logo document.
      expect(docx, isNot(contains('[Logo:')));
    });

    test('pdf draws the decoded logo image (XObject present)', () async {
      final out = await const PdfRenderer().render(ctx(
        const FormStyleSheet(theme: FormTheme(logo: _pngDataUri, logoWidth: 60)),
        compress: false,
      ));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      expect(pdf, contains('/Subtype /Image'));
    });

    test('ui dsl exposes the theme in scaffold metadata', () async {
      final out = await const UiDslRenderer().render(ctx(
        const FormStyleSheet(
          theme: FormTheme(logo: 'brand.png', baseFontSize: 13),
        ),
      ));
      final dsl = jsonDecode(utf8.decode(out.content as List<int>))
          as Map<String, dynamic>;
      final meta = dsl['metadata'] as Map<String, dynamic>;
      final theme = meta['theme'] as Map<String, dynamic>;
      expect(theme['logo'], 'brand.png');
      expect(theme['baseFontSize'], 13);
    });
  });
}
