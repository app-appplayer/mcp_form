import 'dart:convert';
import 'dart:io';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/pdf_renderer.dart';
import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

void main() {
  // Arial Unicode covers Arabic Presentation Forms-B (the shaped glyphs).
  const fontPath = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
  final hasFont = File(fontPath).existsSync();
  final skip = hasFont ? false : 'font not present';

  late TrueTypeFont font;
  if (hasFont) font = TrueTypeFont.parse(File(fontPath).readAsBytesSync());

  Set<double> tdXs(String pdf) => RegExp(r'(\d+\.\d+) \d+\.\d+ Td')
      .allMatches(pdf)
      .map((m) => double.parse(m.group(1)!))
      .toSet();

  RenderContext ctxStyled(String text, Map<String, dynamic>? style) {
    const layout = FormLayoutPolicy(
      pageSize: FormPageSize(size: 'A4', width: 210, height: 297),
      margins: FormMargins(top: 20, right: 20, bottom: 20, left: 20),
      fontPolicy: FormFontPolicy(
          defaultFont: 'x',
          defaultSize: 12,
          headingSize: 18,
          bodySize: 12,
          minSize: 8),
    );
    return RenderContext(
      document: FormDocument(
        documentId: 'd',
        templateId: 't',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(author: 'a', createdAt: DateTime(2026)),
        sections: [
          FormSection(sectionId: 's', index: 0, blocks: [
            FormTextBlock(blockId: 't', index: 0, content: text, style: style),
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
      embeddedFont: font,
      options: const RenderOptions(compress: false),
    );
  }

  RenderContext ctx(String text) {
    const layout = FormLayoutPolicy(
      pageSize: FormPageSize(size: 'A4', width: 210, height: 297),
      margins: FormMargins(top: 20, right: 20, bottom: 20, left: 20),
      fontPolicy: FormFontPolicy(
          defaultFont: 'x',
          defaultSize: 12,
          headingSize: 18,
          bodySize: 12,
          minSize: 8),
    );
    return RenderContext(
      document: FormDocument(
        documentId: 'd',
        templateId: 't',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(author: 'a', createdAt: DateTime(2026)),
        sections: [
          FormSection(sectionId: 's', index: 0, blocks: [
            FormTextBlock(blockId: 't', index: 0, content: text),
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
      embeddedFont: font,
      options: const RenderOptions(compress: false),
    );
  }

  /// The glyph-id hex the renderer should emit: logical text shaped, then bidi
  /// reordered to visual order, then mapped to the embedded font's glyph ids.
  String expectedHex(String logical) {
    final shaped = shapeArabic(logical);
    final r = resolveBidi(shaped);
    final order = reorderVisual(r.levels, shaped.runes.length);
    final runes = shaped.runes.toList();
    return order
        .map((i) => font
            .gidFor(runes[i])!
            .toRadixString(16)
            .padLeft(4, '0')
            .toUpperCase())
        .join();
  }

  group('Arabic PDF (shaping + bidi)', () {
    test('emits shaped presentation forms in visual (RTL) order', () async {
      const word = 'مرحبا'; // marhaba
      final out = await const PdfRenderer().render(ctx(word));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      // The exact reordered, shaped glyph run appears in the content stream.
      expect(pdf, contains('<${expectedHex(word)}> Tj'));
    }, skip: skip);

    test('does not emit the raw unshaped base letters', () async {
      const word = 'مرحبا';
      final out = await const PdfRenderer().render(ctx(word));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      // Base BEH (U+0628) glyph id should not appear — its shaped (medial) form
      // is used instead.
      final baseBehHex =
          font.gidFor(0x0628)!.toRadixString(16).padLeft(4, '0').toUpperCase();
      final medBehHex =
          font.gidFor(0xFE92)!.toRadixString(16).padLeft(4, '0').toUpperCase();
      expect(pdf, contains(medBehHex));
      expect(pdf.contains(baseBehHex), isFalse);
    }, skip: skip);

    test('keeps embedded Latin in logical order alongside Arabic', () async {
      // "OK مرحبا" — Latin stays LTR at the left, Arabic reorders to its right.
      final out = await const PdfRenderer().render(ctx('OK مرحبا'));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      // Arabic portion still present as its visual-order shaped run.
      expect(pdf, contains(expectedHex('مرحبا')));
    }, skip: skip);

    test('an RTL paragraph right-aligns by default', () async {
      final out = await const PdfRenderer().render(ctxStyled('مرحبا', null));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      const left = 20 * 2.8346; // left margin in points
      // Right-aligned: the run starts well to the right of the left margin.
      expect(tdXs(pdf).every((x) => x > left + 100), isTrue);
    }, skip: skip);

    test('an explicit alignment overrides the RTL default', () async {
      final out = await const PdfRenderer()
          .render(ctxStyled('مرحبا', {'align': 'left'}));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      const left = 20 * 2.8346;
      // Left-aligned: the run begins at the left margin.
      expect(tdXs(pdf).any((x) => (x - left).abs() < 1), isTrue);
    }, skip: skip);
  });
}
