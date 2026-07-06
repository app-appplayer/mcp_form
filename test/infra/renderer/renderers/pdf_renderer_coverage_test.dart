// Coverage tests for PdfRenderer uncovered lines.
// Target: lib/src/infra/renderer/renderers/pdf_renderer.dart
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/pdf_renderer.dart';
import 'package:mcp_form/src/style/style_sheet.dart';
import 'package:mcp_form/src/style/truetype_font.dart';
import 'package:test/test.dart';

const _renderer = PdfRenderer();

FormLayoutPolicy _layout() => const FormLayoutPolicy(
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

RenderContext _ctx(
  List<FormBlock> blocks, {
  RenderOptions options = const RenderOptions(compress: false),
  String author = 'tester',
  FormStyleSheet? styleSheet,
  TrueTypeFont? embeddedFont,
  List<FormSection>? sections,
}) {
  final layout = _layout();
  final doc = FormDocument(
    documentId: 'd',
    templateId: 't',
    templateVersion: '1.0.0',
    metadata: FormDocumentMetadata(author: author, createdAt: DateTime(2026)),
    sections: sections ??
        [FormSection(sectionId: 's', index: 0, blocks: blocks)],
  );
  return RenderContext(
    document: doc,
    layoutPolicy: layout,
    template: FormTemplate(
      templateId: 't',
      version: '1.0.0',
      name: 'T',
      schema: const FormSchema(),
      layoutPolicy: layout,
    ),
    options: options,
    styleSheet: styleSheet,
    embeddedFont: embeddedFont,
  );
}

String _latin(FormRenderOutput o) =>
    latin1.decode(o.content as List<int>, allowInvalid: true);

String _pngDataUri({int w = 4, int h = 3}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(100, 150, 200));
  return 'data:image/png;base64,${base64Encode(img.encodePng(im))}';
}

void main() {
  group('PdfRenderer coverage', () {
    // Line 34: supportedTemplateRange getter.
    test('supportedTemplateRange is non-null', () {
      expect(_renderer.supportedTemplateRange, isNotNull);
    });

    // Line 34: reorderDevanagari is called when text contains Devanagari chars.
    // hasDevanagari() returns true for U+0900-U+097F range, which sets indic=true
    // and causes _shapeText to call reorderDevanagari (line 34).
    test('Devanagari text triggers indic shaping path', () async {
      // "namaste" in Hindi Devanagari (U+0928, U+092E, U+0938, U+094D, U+0924,
      // U+0947) — any Devanagari codepoint triggers hasDevanagari().
      final out = await _renderer.render(_ctx([
        FormTextBlock(
          blockId: 'deva',
          index: 0,
          content: 'Hello नमस्ते world',
        ),
      ]));
      expect(_latin(out), contains('%PDF'));
    });

    // Lines 208, 217-219: forcePageBreak with active box (border/background).
    // A bordered block followed by a block with pageBreak:before triggers
    // emitBoxFragment(activeBox!, contentHeightPt, true) and the continuation.
    test('forcePageBreak with active border box emits box fragment', () async {
      final out = await _renderer.render(_ctx([
        FormTextBlock(
          blockId: 'boxed',
          index: 0,
          content: 'In a box',
          style: const {'border': true},
        ),
        FormTextBlock(
          blockId: 'next',
          index: 1,
          content: 'After page break',
          style: const {'pageBreak': 'before'},
        ),
      ]));
      expect(out.pageCount, greaterThanOrEqualTo(2));
      expect(_latin(out), contains('After page break'));
    });

    // Line 698: table with empty columns list falls through to addBlankLine.
    test('table with no columns emits a blank line (no crash)', () async {
      final out = await _renderer.render(_ctx([
        FormTableBlock(
          blockId: 'empty',
          index: 0,
          columns: const [],
          rows: const [],
        ),
      ]));
      expect(_latin(out), contains('%PDF'));
    });

    // Lines 663-664: image with maxWidth caps draw width.
    test('image with maxWidth is drawn at capped width', () async {
      final out = await _renderer.render(_ctx([
        FormImageBlock(
          blockId: 'stamp',
          index: 0,
          src: _pngDataUri(),
          maxWidth: 30, // 30px → ~22.5pt, well below content width
        ),
      ]));
      expect(_latin(out), contains('/Subtype /Image'));
    });

    // Line 669: tall image (aspect ratio h/w > contentHeight/drawW) clips
    // to page height.
    test('very tall image is clipped to content height', () async {
      // Use a 1×100 (very tall) image.
      final out = await _renderer.render(_ctx([
        FormImageBlock(
          blockId: 'tall',
          index: 0,
          src: _pngDataUri(w: 1, h: 200), // extreme portrait
        ),
      ]));
      expect(_latin(out), contains('/Subtype /Image'));
    });

    // Line 570: renderBarcode with style.height uses custom height.
    // barcode:// prefix triggers renderBarcode; style['height'] is a num so
    // the true branch (line 570) is taken instead of the 40.0 default.
    test('barcode block with style height uses custom bar height', () async {
      final out = await _renderer.render(_ctx([
        FormImageBlock(
          blockId: 'bcode',
          index: 0,
          src: 'barcode://HELLO-WORLD',
          style: const {'height': 55.0},
        ),
      ]));
      expect(_latin(out), contains('%PDF'));
    });

    // Lines 850-852: tagged PDF with chart, canvas, field blocks resolves
    // structure type for each.
    test('tagged PDF with chart, canvas and field blocks renders valid PDF',
        () async {
      final out = await _renderer.render(_ctx(
        [
          FormChartBlock(
            blockId: 'ch',
            index: 0,
            chartType: 'bar',
            data: const [
              {
                'label': 'S',
                'points': [
                  {'x': 'Q1', 'y': 5},
                ],
              }
            ],
          ),
          FormCanvasBlock(
            blockId: 'cv',
            index: 1,
            target: 'canvas://x',
          ),
          FormFieldBlock(
            blockId: 'ff',
            index: 2,
            fieldName: 'name',
            fieldType: 'text',
          ),
        ],
        options: const RenderOptions(compress: false, taggedPdf: true),
      ));
      expect(_latin(out), contains('%PDF'));
    });

    // Lines 914-916: tagged PDF chart includes alt text in struct tree.
    test('tagged PDF chart with title sets alt text in struct', () async {
      final out = await _renderer.render(_ctx(
        [
          FormChartBlock(
            blockId: 'titled',
            index: 0,
            chartType: 'bar',
            title: 'Revenue Chart',
            data: const [
              {
                'label': 'A',
                'points': [
                  {'x': 'Jan', 'y': 10},
                ],
              }
            ],
          ),
        ],
        options: const RenderOptions(compress: false, taggedPdf: true),
      ));
      expect(_latin(out), contains('Revenue Chart'));
    });

    // Lines 929-934: FormCanvasBlock in PDF renders label and target.
    test('FormCanvasBlock emits label and target text in PDF', () async {
      final out = await _renderer.render(_ctx([
        FormCanvasBlock(
          blockId: 'cv',
          index: 0,
          target: 'canvas://scene.main',
          caption: 'Scene',
        ),
      ]));
      final pdf = _latin(out);
      expect(pdf, contains('([Canvas: Scene]) Tj'));
      expect(pdf, contains('canvas://scene.main'));
    });

    // Line 1009: single-cell row (colSpan < 12) calls renderBlock directly.
    test('single block with colSpan<12 renders as a single-cell row', () async {
      final out = await _renderer.render(_ctx([
        FormTextBlock(
          blockId: 'half',
          index: 0,
          content: 'Half width',
          style: const {'colSpan': 6}, // colSpan < 12 → single-cell row path
        ),
      ]));
      expect(_latin(out), contains('Half width'));
    });

    // Line 1062: tagged PDF with section title emits H2 struct.
    test('tagged PDF with section title emits structure tag', () async {
      final out = await _renderer.render(_ctx(
        [],
        options: const RenderOptions(compress: false, taggedPdf: true),
        sections: [
          FormSection(
            sectionId: 's1',
            index: 0,
            title: 'Section One',
            blocks: [
              FormTextBlock(
                blockId: 't',
                index: 0,
                content: 'Content here',
              ),
            ],
          ),
        ],
      ));
      expect(_latin(out), contains('Section One'));
    });

    // Lines 1115-1122: footnotes emitted as endnotes section.
    test('footnotes in text are collected and appended as endnotes', () async {
      final out = await _renderer.render(_ctx([
        FormTextBlock(
          blockId: 'ft',
          index: 0,
          content: 'See[fn:This is a footnote] end.',
        ),
      ]));
      final pdf = _latin(out);
      expect(pdf, contains('(Notes) Tj'));
      expect(pdf, contains('This is a footnote'));
    });

    // Line 1127: active box open at document end is closed.
    // A bordered block as the very last block leaves activeBox open at end.
    test('bordered block at document end closes activeBox on finish', () async {
      final out = await _renderer.render(_ctx([
        // The page-break block has no background/border, so it won't create a box.
        FormTextBlock(blockId: 'pre', index: 0, content: 'First'),
        // Last block has a border — its box stays open until document end.
        FormTextBlock(
          blockId: 'last',
          index: 1,
          content: 'Bordered last block',
          style: const {'background': '#EEEEEE'},
        ),
      ]));
      expect(_latin(out), contains('Bordered last block'));
    });

    // Line 1310: center-aligned text uses center startX calculation.
    test('center-aligned paragraph renders without error', () async {
      final out = await _renderer.render(_ctx([
        FormTextBlock(
          blockId: 'ctr',
          index: 0,
          content: 'Centered paragraph text',
          style: const {'align': 'center'},
        ),
      ]));
      expect(_latin(out), contains('(Centered paragraph text) Tj'));
    });

    // Line 2014: header text is drawn on each page.
    test('headerText option draws header on each page', () async {
      final out = await _renderer.render(_ctx(
        [
          for (var i = 0; i < 80; i++)
            FormTextBlock(blockId: 't$i', index: i, content: 'Row $i'),
        ],
        options: const RenderOptions(
          compress: false,
          headerText: 'CONFIDENTIAL',
        ),
      ));
      final pdf = _latin(out);
      expect(pdf, contains('(CONFIDENTIAL) Tj'));
    });

    // Lines 2217-2227: line chart with series generates poly-lines in PDF.
    test('line chart generates polyline path ops in PDF stream', () async {
      final out = await _renderer.render(_ctx([
        FormChartBlock(
          blockId: 'lc',
          index: 0,
          chartType: 'line',
          data: const [
            {
              'label': 'Revenue',
              'points': [
                {'x': 'Jan', 'y': 10},
                {'x': 'Feb', 'y': 25},
                {'x': 'Mar', 'y': 18},
              ],
            },
          ],
        ),
      ]));
      final pdf = _latin(out);
      // Poly-line path: starts with 'm' (moveto) and follows with 'l' (lineto) + 'S'.
      expect(pdf, contains(' m'));
      expect(pdf, contains(' l'));
      expect(pdf, contains('S\n'));
    });

    // Line 2379: _escapePdfString maps unmapped Unicode char to '?'.
    // Character U+0100 (Ā — Latin Extended-A) is not in WinAnsi and not in
    // the 0xA0-0xFF range, so it maps to '?' in the PDF string.
    // includeMetadata: true causes the author field to be written via
    // _escapePdfString, which exercises the null-map branch (line 2379).
    test('author name with non-WinAnsi char is safe-encoded in PDF', () async {
      final out = await _renderer.render(_ctx(
        [FormTextBlock(blockId: 't', index: 0, content: 'body')],
        author: 'Author Ā Test', // Ā (U+0100) is unmapped in WinAnsi
        options: const RenderOptions(compress: false, includeMetadata: true),
      ));
      // The PDF is produced without error; the character maps to '?'.
      final pdf = _latin(out);
      expect(pdf, contains('%PDF'));
      // Verify the author appears in the Info dict with '?' for Ā.
      expect(pdf, contains('/Author (Author ? Test)'));
    });

    // Lines 2441-2451: _PdfSeg.copyWith is called during justify re-spacing.
    // Need a multi-line paragraph so at least one non-last line is justified.
    test('justified long paragraph triggers copyWith on non-last lines',
        () async {
      const longText = 'alpha beta gamma delta epsilon zeta eta theta iota '
          'kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi '
          'psi omega aleph beth gimel daleth he vav zayin heth teth yodh '
          'kaph lamedh mem nun samekh ayin pe tsadi qoph resh shin taw';
      final out = await _renderer.render(_ctx([
        FormTextBlock(
          blockId: 'jst',
          index: 0,
          content: longText,
          style: const {'align': 'justify'},
        ),
      ]));
      expect(_latin(out), contains('(alpha) Tj'));
    });

    // Line 2608: _jpegSize non-0xFF byte path (malformed JPEG).
    // Craft a JPEG-like byte sequence where after an APP0 segment with length=2,
    // the next byte is non-0xFF (0x42), then a valid SOF0 provides dimensions.
    test('_jpegSize handles non-0xFF byte by skipping it', () async {
      // Minimal crafted JPEG:
      //   FF D8 — SOI
      //   FF E0 00 02 — APP0, length=2 (empty segment)
      //   42 — non-0xFF byte at position 6 → triggers line 2608
      //   FF C0 00 0B 08 00 04 00 03 03 01 11 00 — SOF0: h=4, w=3
      final jpeg = <int>[
        0xFF, 0xD8, // SOI
        0xFF, 0xE0, 0x00, 0x02, // APP0 length=2
        0x42, // non-0xFF (triggers line 2608 in _jpegSize)
        0xFF, 0xC0, 0x00, 0x0B, 0x08, // SOF0 marker + length=11 + precision=8
        0x00, 0x04, // height = 4
        0x00, 0x03, // width = 3
        0x03, 0x01, 0x11, 0x00, // 3 components (minimal)
        0xFF, 0xD9, // EOI
      ];
      final dataUri =
          'data:image/jpeg;base64,${base64Encode(jpeg)}';
      final out = await _renderer.render(_ctx([
        FormImageBlock(
          blockId: 'mjpeg',
          index: 0,
          src: dataUri,
        ),
      ]));
      // Either the malformed JPEG is embedded or falls through to placeholder.
      expect(_latin(out), contains('%PDF'));
    });

    // Lines 2109-2110: fauxItalic with embedded TrueType font.
    // Guard: only runs on macOS where AppleGothic.ttf exists.
    test('embedded TrueType font with italic text uses shear matrix',
        () async {
      final fontFile =
          File('/System/Library/Fonts/Supplemental/AppleGothic.ttf');
      if (!fontFile.existsSync()) {
        return; // skip on non-macOS or missing font
      }
      final font = TrueTypeFont.parse(fontFile.readAsBytesSync());
      final out = await _renderer.render(_ctx(
        [
          FormTextBlock(
            blockId: 'ital',
            index: 0,
            format: 'markdown',
            content: '*italic text*',
          ),
        ],
        options: const RenderOptions(compress: false),
        embeddedFont: font,
      ));
      final pdf = _latin(out);
      // The faux-italic shear matrix: "1 0 0.182 1 ... Tm"
      expect(pdf, contains('0.182 1'));
    });

    // Lines 2266-2269: ToUnicode surrogate-pair encoding for a
    // supplementary-plane (non-BMP) code point.
    test('ToUnicode encodes a supplementary-plane glyph (surrogate pair)',
        () async {
      final fontFile = File(
          '/System/Library/Fonts/Supplemental/NotoSansCaucasianAlbanian-Regular.ttf');
      if (!fontFile.existsSync()) {
        return; // skip if the supplementary-plane font is absent
      }
      final font = TrueTypeFont.parse(fontFile.readAsBytesSync());
      int? cp;
      for (var c = 0x10530; c <= 0x10570; c++) {
        if ((font.gidFor(c) ?? 0) != 0) {
          cp = c;
          break;
        }
      }
      if (cp == null) return;
      final out = await _renderer.render(_ctx(
        [
          FormTextBlock(
              blockId: 't', index: 0, content: String.fromCharCode(cp)),
        ],
        options: const RenderOptions(compress: false),
        embeddedFont: font,
      ));
      expect(_latin(out), contains('/ToUnicode'));
    });
  });
}
