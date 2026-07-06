import 'dart:convert';
import 'dart:io';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/pdf_renderer.dart';
import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

void main() {
  // Primary = a Latin face without Hangul; fallback = a Korean face.
  const latinPath = '/System/Library/Fonts/Supplemental/Georgia.ttf';
  const cjkPath = '/System/Library/Fonts/Supplemental/AppleGothic.ttf';
  final hasFonts = File(latinPath).existsSync() && File(cjkPath).existsSync();
  final skip = hasFonts ? false : 'fonts not present';

  late TrueTypeFont latin;
  late TrueTypeFont cjk;
  if (hasFonts) {
    latin = TrueTypeFont.parse(File(latinPath).readAsBytesSync());
    cjk = TrueTypeFont.parse(File(cjkPath).readAsBytesSync());
  }

  group('FallbackMetrics', () {
    test('measures each code point with the first covering font', () {
      final fm = FallbackMetrics([latin, cjk]);
      final a = 'A'.runes.first;
      final han = '한'.runes.first;
      // Latin glyph: primary width. Hangul: fallback width (primary lacks it).
      expect(fm.advanceEm(a), latin.advanceWidth1000(latin.gidFor(a)!) / 1000.0);
      expect(fm.advanceEm(han), cjk.advanceWidth1000(cjk.gidFor(han)!) / 1000.0);
      // Primary does not cover Hangul.
      expect(latin.gidFor(han), anyOf(isNull, 0));
    }, skip: skip);

    test('falls back to a nominal width when no font covers', () {
      final fm = FallbackMetrics([latin, cjk]);
      // A Private Use Area code point neither face covers.
      expect(fm.advanceEm(0x100000), greaterThan(0));
    }, skip: skip);
  });

  group('PDF multi-font routing', () {
    RenderContext ctx() {
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
              FormTextBlock(blockId: 't', index: 0, content: 'Hi 한글 World'),
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
        embeddedFont: latin,
        fallbackFonts: [cjk],
        options: const RenderOptions(compress: false),
      );
    }

    test('embeds one Type0 font per used face and references both', () async {
      final out = await const PdfRenderer().render(ctx());
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      // Two embedded Type0 programs (primary + fallback).
      expect('/Subtype /Type0'.allMatches(pdf).length, 2);
      expect('/FontFile2'.allMatches(pdf).length, 2);
      // Both referenced in the page font resources, and both used in content.
      expect(pdf, contains('/F1'));
      expect(pdf, contains('/F2'));
      expect(pdf, contains('> Tj')); // hex GID strings, not Helvetica literals
      expect(pdf, isNot(contains('/Helvetica')));
    }, skip: skip);

    test('Latin stays on the primary when no fallback is given', () async {
      // Same primary alone: Hangul would be .notdef but only one font embeds.
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
      final out = await const PdfRenderer().render(RenderContext(
        document: FormDocument(
          documentId: 'd',
          templateId: 't',
          templateVersion: '1.0.0',
          metadata: FormDocumentMetadata(author: 'a', createdAt: DateTime(2026)),
          sections: [
            FormSection(sectionId: 's', index: 0, blocks: [
              FormTextBlock(blockId: 't', index: 0, content: 'Latin only'),
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
        embeddedFont: latin,
        options: const RenderOptions(compress: false),
      ));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      expect('/Subtype /Type0'.allMatches(pdf).length, 1);
    }, skip: skip);
  });
}
