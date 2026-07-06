import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/mcp_form.dart';
import 'package:test/test.dart';

void main() {
  group('encodeCode128B', () {
    test('symbol sequence and checksum for "A"', () {
      // Start B (104), 'A' (65-32=33), checksum, Stop (106).
      // checksum = (104*1 + 33*1) % 103 = 137 % 103 = 34.
      final code = encodeCode128B('A');
      expect(code.symbolValues, [104, 33, 34, 106]);
    });

    test('weighted checksum for "AB"', () {
      // 104*1 + 33*1 + 34*2 = 205; 205 % 103 = 102.
      final code = encodeCode128B('AB');
      expect(code.symbolValues, [104, 33, 34, 102, 106]);
    });

    test('module bitmap starts with the Start-B bar pattern 211214', () {
      final code = encodeCode128B('A');
      // 2 bars, 1 space, 1 bar, 2 spaces, 1 bar, 4 spaces.
      expect(
        code.modules.take(11).toList(),
        [true, true, false, true, false, false, true, false, false, false, false],
      );
    });

    test('every data/start symbol is 11 modules, stop is 13', () {
      final code = encodeCode128B('Hello');
      // start + 5 data + checksum = 7 symbols * 11 + stop 13.
      expect(code.width, 7 * 11 + 13);
    });

    test('non-printable input is sanitised to a space, not dropped', () {
      final tab = encodeCode128B('\t');
      final space = encodeCode128B(' ');
      expect(tab.symbolValues, space.symbolValues);
    });

    test('isBarcodeSrc / barcodeData parse the src scheme', () {
      expect(isBarcodeSrc('barcode:INV-42'), isTrue);
      expect(isBarcodeSrc('data:image/png;base64,xx'), isFalse);
      expect(barcodeData('barcode:INV-42'), 'INV-42');
    });
  });

  group('renderers draw a barcode image block', () {
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
          FormImageBlock(
              blockId: 'bc',
              index: 0,
              src: 'barcode:INV-2026-0042',
              style: const {'caption': 'Invoice code'}),
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

    test('html emits an inline barcode svg with bar rects', () async {
      final out = await const HtmlRenderer().render(ctx());
      final html = utf8.decode(out.content as List<int>);
      expect(html, contains('<svg class="barcode"'));
      expect(html, contains('fill="#000"'));
      // The caption still renders below the figure.
      expect(html, contains('Figure 1: Invoice code'));
    });

    test('pdf draws filled bar rectangles', () async {
      final out = await const PdfRenderer().render(ctx(compress: false));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      // Bars are black filled rectangles (`re f` after a black `rg` fill).
      expect(pdf, contains('0.000 0.000 0.000 rg'));
      expect(pdf, contains('re f'));
      expect(pdf, contains('Figure 1: Invoice code'));
    });
  });
}
