import 'dart:convert';
import 'dart:io';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/pdf_renderer.dart';
import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

FormLayoutPolicy _layout({double height = 297}) => FormLayoutPolicy(
      pageSize: FormPageSize(size: 'A4', width: 210, height: height),
      margins: const FormMargins(top: 20, right: 20, bottom: 20, left: 20),
      fontPolicy: const FormFontPolicy(
        defaultFont: 'x',
        defaultSize: 12,
        headingSize: 18,
        bodySize: 12,
        minSize: 8,
      ),
    );

RenderContext _ctx(
  List<FormBlock> blocks, {
  TrueTypeFont? font,
  PageFlow flow = PageFlow.paged,
  double height = 297,
}) {
  final layout = _layout(height: height);
  return RenderContext(
    document: FormDocument(
      documentId: 'd',
      templateId: 't',
      templateVersion: '1.0.0',
      metadata: FormDocumentMetadata(author: 'a', createdAt: DateTime(2026)),
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
    options: RenderOptions(pageFlow: flow, compress: false),
  );
}

String _latin(FormRenderOutput o) =>
    latin1.decode(o.content as List<int>, allowInvalid: true);

void main() {
  // A system font with broad coverage; the embed test is skipped where absent
  // (non-macOS CI).
  const fontPath = '/System/Library/Fonts/Supplemental/AppleGothic.ttf';
  final hasFont = File(fontPath).existsSync();

  group('TrueTypeFont', () {
    test('parses cmap + metrics and maps Hangul', () {
      final f = TrueTypeFont.parse(File(fontPath).readAsBytesSync());
      expect(f.numGlyphs, greaterThan(0));
      expect(f.unitsPerEm, greaterThan(0));
      final gid = f.gidFor('가'.runes.first);
      expect(gid, isNotNull);
      expect(gid, greaterThan(0));
      expect(f.advanceWidth1000(gid!), greaterThan(0));
    }, skip: hasFont ? false : 'font not present');

    test('returns null for an uncovered code point', () {
      final f = TrueTypeFont.parse(File(fontPath).readAsBytesSync());
      // A Private Use Area code point no normal font covers.
      expect(f.gidFor(0x100000), anyOf(isNull, 0));
    }, skip: hasFont ? false : 'font not present');
  });

  group('PDF multilingual (Type0)', () {
    test('embeds a Type0 font and encodes glyph ids', () async {
      final font = TrueTypeFont.parse(File(fontPath).readAsBytesSync());
      final out = await const PdfRenderer().render(_ctx(
        [
          FormHeadingBlock(
              blockId: 'h', index: 0, content: '한국어 제목', level: 1),
          FormTextBlock(
              blockId: 't', index: 1, content: '본문 텍스트 with English.'),
        ],
        font: font,
      ));
      final pdf = _latin(out);
      expect(pdf, contains('/Subtype /Type0'));
      expect(pdf, contains('/CIDFontType2'));
      expect(pdf, contains('/Encoding /Identity-H'));
      expect(pdf, contains('/FontFile2'));
      expect(pdf, contains('/ToUnicode'));
      // Glyphs are emitted as hex GID strings, not Helvetica literals.
      expect(pdf, contains('> Tj'));
      expect(pdf, isNot(contains('/Helvetica')));
    }, skip: hasFont ? false : 'font not present');

    test('embeds only a glyph subset, not the whole font', () async {
      final fontBytes = File(fontPath).readAsBytesSync();
      final font = TrueTypeFont.parse(fontBytes);
      final out = await const PdfRenderer().render(_ctx(
        [FormTextBlock(blockId: 't', index: 0, content: '한국어 ABC 123')],
        font: font,
      ));
      // The face is many MB; with subsetting the whole PDF stays tiny even
      // uncompressed (compress:false here).
      expect((out.content as List).length, lessThan(fontBytes.length ~/ 10));
      // Still a valid embedded Type0 program.
      expect(_latin(out), contains('/FontFile2'));
    }, skip: hasFont ? false : 'font not present');

    test('falls back to Helvetica without an embedded font', () async {
      final out = await const PdfRenderer().render(_ctx([
        FormTextBlock(blockId: 't', index: 0, content: 'Latin only'),
      ]));
      expect(_latin(out), contains('/Helvetica'));
    });
  });

  group('PDF continuous flow', () {
    List<FormBlock> many() => [
          for (var i = 0; i < 80; i++)
            FormTextBlock(blockId: 't$i', index: i, content: 'Line $i of content'),
        ];

    test('continuous produces a single growing page', () async {
      final out = await const PdfRenderer()
          .render(_ctx(many(), flow: PageFlow.continuous));
      expect(out.pageCount, 1);
      // The single MediaBox is taller than an A4 page.
      final m = RegExp(r'/MediaBox \[0 0 [\d.]+ ([\d.]+)\]')
          .firstMatch(_latin(out));
      expect(m, isNotNull);
      expect(double.parse(m!.group(1)!), greaterThan(297 * 2.8346));
    });

    test('paged splits the same content across pages', () async {
      final out = await const PdfRenderer()
          .render(_ctx(many(), flow: PageFlow.paged));
      expect(out.pageCount, greaterThan(1));
    });
  });
}
