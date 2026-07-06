import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/mcp_form.dart';
import 'package:test/test.dart';

void main() {
  group('QR error correction (Reed–Solomon over GF(256))', () {
    test('matches the canonical HELLO WORLD v1-M vector', () {
      // Documented QR reference: 16 data codewords -> 10 EC codewords.
      final data = [
        32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17, 236, 17
      ];
      expect(qrErrorCorrection(data, 10),
          [196, 35, 39, 119, 235, 215, 231, 226, 93, 23]);
    });
  });

  group('encodeQr structure', () {
    test('version grows with payload; size = 17 + 4*version', () {
      final small = encodeQr('HI'); // fits v1
      expect(small.size, 21); // 17 + 4
      final bigger = encodeQr('https://makemind.dev/forms'); // 26 bytes -> v2
      expect(bigger.size, 25); // 17 + 8
    });

    test('has three finder patterns (7x7 dark border) at the corners', () {
      final qr = encodeQr('TEST');
      bool finder(int ox, int oy) =>
          qr.modules[oy][ox] && // corner dark
          qr.modules[oy][ox + 6] &&
          qr.modules[oy + 6][ox] &&
          !qr.modules[oy + 1][ox + 1]; // inner separator ring is light
      expect(finder(0, 0), isTrue);
      expect(finder(qr.size - 7, 0), isTrue);
      expect(finder(0, qr.size - 7), isTrue);
    });

    test('the dark module is set', () {
      final qr = encodeQr('X');
      expect(qr.modules[qr.size - 8][8], isTrue);
    });

    test('encoding is deterministic', () {
      expect(encodeQr('same').modules, encodeQr('same').modules);
    });

    test('overflowing versions 1-7 throws', () {
      expect(() => encodeQr('x' * 200), throwsArgumentError);
    });

    test('isQrSrc / qrData parse the src scheme', () {
      expect(isQrSrc('qr:https://x.io'), isTrue);
      expect(isQrSrc('barcode:1'), isFalse);
      expect(qrData('qr:https://x.io'), 'https://x.io');
    });
  });

  group('renderers draw a qr image block', () {
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
              blockId: 'q',
              index: 0,
              src: 'qr:https://makemind.dev',
              style: const {'caption': 'Scan to pay'}),
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

    test('html emits an svg grid of modules', () async {
      final out = await const HtmlRenderer().render(ctx());
      final html = utf8.decode(out.content as List<int>);
      expect(html, contains('<svg class="qr"'));
      expect(html, contains('fill="#000"'));
      expect(html, contains('Figure 1: Scan to pay'));
    });

    test('pdf draws filled module rectangles', () async {
      final out = await const PdfRenderer().render(ctx(compress: false));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      expect(pdf, contains('0.000 0.000 0.000 rg'));
      expect(pdf, contains('re f'));
    });
  });
}
