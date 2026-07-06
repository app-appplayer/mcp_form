import 'dart:convert';
import 'dart:io';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/html_renderer.dart';
import 'package:mcp_form/src/infra/renderer/renderers/pdf_renderer.dart';
import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

/// Whole-layer end-to-end audit: every styling feature exercised through the
/// real render path, asserting integrated output properties (not unit internals).
void main() {
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

  RenderContext ctx(
    List<FormBlock> blocks, {
    TrueTypeFont? font,
    List<TrueTypeFont> fallback = const [],
    RenderOptions options = const RenderOptions(compress: false),
  }) =>
      RenderContext(
        document: FormDocument(
          documentId: 'd',
          templateId: 't',
          templateVersion: '1.0.0',
          metadata:
              FormDocumentMetadata(author: 'a', createdAt: DateTime(2026)),
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
        embeddedFont: font,
        fallbackFonts: fallback,
        options: options,
      );

  String pdfStr(List<int> bytes) =>
      latin1.decode(bytes, allowInvalid: true);

  FormTextBlock txt(String s, {Map<String, dynamic>? style}) =>
      FormTextBlock(blockId: 't', index: 0, content: s, style: style);

  group('AUDIT — default path stays simple (non-regression guards)', () {
    test('plain LTR single-column emits a valid one-font PDF', () async {
      final out = await const PdfRenderer().render(ctx([txt('Hello world')]));
      final s = pdfStr(out.content as List<int>);
      expect(s.startsWith('%PDF-1.'), isTrue);
      expect(s, contains('%%EOF'));
      expect(s, contains('Tj'));
      // No Type0 / multi-font machinery on the plain Helvetica path.
      expect(s.contains('/CIDFontType2'), isFalse);
      expect(out.pageCount, greaterThanOrEqualTo(1));
    });

    test('HTML default has no grid-row wrappers', () async {
      final out = await const HtmlRenderer().render(ctx([txt('a'), txt('b')]));
      final s = utf8.decode(out.content as List<int>);
      expect(s.contains('class="grid-row"'), isFalse);
      expect(s, contains('<!DOCTYPE html>'));
    });
  });

  group('AUDIT — chart (format-independent geometry)', () {
    final chart = FormChartBlock(
      blockId: 'c',
      index: 0,
      chartType: 'bar',
      title: 'Q',
      data: [
        {
          'label': 'A',
          'color': '#3366cc',
          'points': [
            {'x': 'Jan', 'y': 10},
            {'x': 'Feb', 'y': 20},
          ],
        },
      ],
    );

    test('PDF draws vector chart ops (not a placeholder)', () async {
      final out = await const PdfRenderer().render(ctx([chart]));
      final s = pdfStr(out.content as List<int>);
      expect(s.contains('[Chart'), isFalse); // not the old placeholder
      expect(s, anyOf(contains(' re\n'), contains(' re '))); // rectangles
    });

    test('HTML emits inline SVG figure', () async {
      final out = await const HtmlRenderer().render(ctx([chart]));
      final s = utf8.decode(out.content as List<int>);
      expect(s, contains('<svg'));
      expect(s, contains('class="chart"'));
    });
  });

  group('AUDIT — grid colSpan (PDF band + HTML CSS grid)', () {
    test('PDF places two half-width cells at distinct x', () async {
      final out = await const PdfRenderer().render(ctx([
        txt('left', style: {'colSpan': 6}),
        txt('right', style: {'colSpan': 6}),
      ]));
      final s = pdfStr(out.content as List<int>);
      final xs = RegExp(r'(\d+\.\d+) \d+\.\d+ Td')
          .allMatches(s)
          .map((m) => double.parse(m.group(1)!))
          .toSet();
      expect(xs.length, greaterThanOrEqualTo(2));
    });
  });

  group('AUDIT — Indic / bidi pure logic (font-independent)', () {
    test('Devanagari i-matra reorders before its cluster', () {
      expect(reorderDevanagari('कि'), 'िक');
    });
    test('bidi mirrors and neutralises explicit codes', () {
      expect(mirrorGlyph(0x28), 0x29);
      // LRE/PDF around Latin inside Hebrew: paragraph stays RTL.
      expect(resolveBidi('א\u202Ab\u202C').paraLevel, 1);
    });
  });

  // Font-dependent features (subsetting, fallback, RTL shaping) need real TTFs.
  group('AUDIT — font-dependent (skipped without macOS fonts)', () {
    const cjk = '/System/Library/Fonts/Supplemental/AppleGothic.ttf';
    const latin = '/System/Library/Fonts/Supplemental/Georgia.ttf';
    const broad = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
    final hasCjk = File(cjk).existsSync();
    final hasLatin = File(latin).existsSync();
    final hasBroad = File(broad).existsSync();

    test('subsetting: embedded font is far smaller than the source', () async {
      final font = TrueTypeFont.parse(File(cjk).readAsBytesSync());
      final out = await const PdfRenderer().render(ctx([txt('한글 문서')],
          font: font,
          options: const RenderOptions(compress: false)));
      // The embedded FontFile2 must be a tiny subset, not the 14MB original.
      expect((out.content as List).length, lessThan(2 * 1024 * 1024));
      final s = pdfStr(out.content as List<int>);
      expect(s, contains('/CIDFontType2'));
    }, skip: hasCjk ? false : 'AppleGothic absent');

    test('fallback: Latin + CJK route to two embedded fonts', () async {
      final g = TrueTypeFont.parse(File(latin).readAsBytesSync());
      final k = TrueTypeFont.parse(File(cjk).readAsBytesSync());
      final out = await const PdfRenderer()
          .render(ctx([txt('Hi 한글')], font: g, fallback: [k]));
      final s = pdfStr(out.content as List<int>);
      // Two Type0 composite fonts present (one per script).
      expect('/Type0'.allMatches(s).length, greaterThanOrEqualTo(2));
    }, skip: (hasLatin && hasCjk) ? false : 'Georgia/AppleGothic absent');

    test('Arabic: shaped presentation forms in visual RTL order', () async {
      final font = TrueTypeFont.parse(File(broad).readAsBytesSync());
      final out =
          await const PdfRenderer().render(ctx([txt('مرحبا')], font: font));
      final s = pdfStr(out.content as List<int>);
      final shaped = shapeArabic('مرحبا');
      final r = resolveBidi(shaped);
      final order = reorderVisual(r.levels, shaped.runes.length);
      final runes = shaped.runes.toList();
      final hex = order
          .map((i) => font
              .gidFor(runes[i])!
              .toRadixString(16)
              .padLeft(4, '0')
              .toUpperCase())
          .join();
      expect(s, contains('<$hex> Tj'));
    }, skip: hasBroad ? false : 'Arial Unicode absent');
  });
}
