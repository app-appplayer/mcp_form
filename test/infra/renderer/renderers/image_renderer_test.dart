import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/image_renderer.dart';
import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

const _renderer = ImageRenderer(dpi: 150);

FormLayoutPolicy _cardLayout() => const FormLayoutPolicy(
      // A business-card-sized page (90×50mm).
      pageSize: FormPageSize(size: 'Card', width: 90, height: 50),
      margins: FormMargins(top: 6, right: 6, bottom: 6, left: 6),
      fontPolicy: FormFontPolicy(
        defaultFont: 'x',
        defaultSize: 11,
        headingSize: 16,
        bodySize: 10,
        minSize: 7,
      ),
    );

RenderContext _ctx(List<FormBlock> blocks, {TrueTypeFont? font}) {
  final layout = _cardLayout();
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
  );
}

int _nonWhitePixels(img.Image im) {
  var n = 0;
  for (final p in im) {
    if (p.r < 250 || p.g < 250 || p.b < 250) n++;
  }
  return n;
}

/// A small solid-colour PNG as a data URI, for image-block tests.
String _pngDataUri({int r = 10, int g = 20, int b = 30}) {
  final im = img.Image(width: 4, height: 3);
  img.fill(im, color: img.ColorRgb8(r, g, b));
  return 'data:image/png;base64,${base64Encode(img.encodePng(im))}';
}

void main() {
  const fontPath = '/System/Library/Fonts/Supplemental/AppleGothic.ttf';
  final hasFont = File(fontPath).existsSync();
  // Verdana Bold has off-curve-start glyphs in both tail variants AND uses the
  // short `loca` format — exercising both the flattener's off-curve rotation
  // and the short-loca offset read in TrueTypeFont.glyphContours.
  const offCurvePath = '/System/Library/Fonts/Supplemental/Verdana Bold.ttf';
  final hasOffCurve = File(offCurvePath).existsSync();
  // A font with a cmap format-12 subtable and supplementary-plane glyphs
  // (Caucasian Albanian, U+10530+), to exercise the format-12 lookup path.
  const cmap12Path =
      '/System/Library/Fonts/Supplemental/NotoSansCaucasianAlbanian-Regular.ttf';
  final hasCmap12 = File(cmap12Path).existsSync();

  group('ImageRenderer', () {
    test('supportedFormats = image / png', () {
      expect(_renderer.supportedFormats, containsAll(['image', 'png']));
    });

    test('renders a business card to a valid PNG', () async {
      final out = await _renderer.render(_ctx([
        FormHeadingBlock(blockId: 'h', index: 0, content: 'Makemind', level: 1),
        FormTextBlock(blockId: 't', index: 1, content: 'hello@makemind.dev'),
      ]));
      expect(out.format, 'image');
      final decoded = img.decodePng(Uint8List.fromList(out.content as List<int>));
      expect(decoded, isNotNull);
      expect(decoded!.width, greaterThan(0));
      expect(decoded.height, greaterThan(0));
    });

    test('renders table + field blocks (structured card / invoice)', () async {
      final layout = _cardLayout();
      final ctx = RenderContext(
        document: FormDocument(
          documentId: 'd',
          templateId: 't',
          templateVersion: '1.0.0',
          metadata:
              FormDocumentMetadata(author: 'a', createdAt: DateTime(2026)),
          sections: [
            FormSection(sectionId: 's', index: 0, blocks: [
              FormFieldBlock(
                  blockId: 'f', index: 0, fieldName: 'name', fieldType: 'text'),
              FormTableBlock(
                blockId: 'tbl',
                index: 1,
                columns: const [
                  // Weighted widths: Item column 3× the Qty column.
                  FormTableColumn(
                      id: 'item', title: 'Item', type: 'text', width: 3),
                  FormTableColumn(
                      id: 'qty', title: 'Qty', type: 'number', width: 1),
                ],
                rows: [
                  FormTableRow(cells: const {'item': 'Widget', 'qty': 3}),
                ],
              ),
            ]),
          ],
          data: const {'name': 'Alice'},
        ),
        layoutPolicy: layout,
        template: FormTemplate(
          templateId: 't',
          version: '1.0.0',
          name: 'T',
          schema: const FormSchema(),
          layoutPolicy: layout,
        ),
      );
      final out = await _renderer.render(ctx);
      final decoded = img.decodePng(Uint8List.fromList(out.content as List<int>));
      expect(decoded, isNotNull);
      // Table grid lines + text → not blank.
      expect(_nonWhitePixels(decoded!), greaterThan(50));
    });

    test('paged output is the full page box (A4 aspect), not content-cropped',
        () async {
      const a4 = FormLayoutPolicy(
        pageSize: FormPageSize(size: 'A4', width: 210, height: 297),
        margins: FormMargins(top: 20, right: 20, bottom: 20, left: 20),
        fontPolicy: FormFontPolicy(
          defaultFont: 'x',
          defaultSize: 11,
          headingSize: 16,
          bodySize: 10,
          minSize: 7,
        ),
      );
      final ctx = RenderContext(
        document: FormDocument(
          documentId: 'd',
          templateId: 't',
          templateVersion: '1.0.0',
          metadata:
              FormDocumentMetadata(author: 'a', createdAt: DateTime(2026)),
          sections: [
            FormSection(sectionId: 's', index: 0, blocks: [
              FormTextBlock(blockId: 't', index: 0, content: 'short'),
            ]),
          ],
        ),
        layoutPolicy: a4,
        template: FormTemplate(
          templateId: 't',
          version: '1.0.0',
          name: 'T',
          schema: const FormSchema(),
          layoutPolicy: a4,
        ),
      );
      final out = await _renderer.render(ctx);
      final decoded =
          img.decodePng(Uint8List.fromList(out.content as List<int>))!;
      // Even with tiny content, the image keeps the A4 portrait aspect.
      expect(decoded.height / decoded.width, closeTo(297 / 210, 0.02));
    });

    test('placement (bottom-center text) is drawn near the page bottom',
        () async {
      const a4 = FormLayoutPolicy(
        pageSize: FormPageSize(size: 'A4', width: 210, height: 297),
        margins: FormMargins(top: 20, right: 20, bottom: 20, left: 20),
        fontPolicy: FormFontPolicy(
          defaultFont: 'x',
          defaultSize: 11,
          headingSize: 16,
          bodySize: 10,
          minSize: 7,
        ),
      );
      final font = hasFont
          ? TrueTypeFont.parse(File(fontPath).readAsBytesSync())
          : null;
      final ctx = RenderContext(
        document: FormDocument(
          documentId: 'd',
          templateId: 't',
          templateVersion: '1.0.0',
          metadata:
              FormDocumentMetadata(author: 'a', createdAt: DateTime(2026)),
          sections: [
            FormSection(sectionId: 's', index: 0, blocks: [
              FormTextBlock(blockId: 'top', index: 0, content: 'header'),
              FormTextBlock(
                blockId: 'co',
                index: 1,
                content: 'Makemind',
                style: const {
                  'placement': {'anchor': 'bottom-center', 'y': 10}
                },
              ),
            ]),
          ],
        ),
        layoutPolicy: a4,
        template: FormTemplate(
          templateId: 't',
          version: '1.0.0',
          name: 'T',
          schema: const FormSchema(),
          layoutPolicy: a4,
        ),
        embeddedFont: font,
      );
      final out = await _renderer.render(ctx);
      final im = img.decodePng(Uint8List.fromList(out.content as List<int>))!;
      // Find the lowest non-white row (placed text near the bottom margin).
      var lowest = 0;
      for (var yy = 0; yy < im.height; yy++) {
        for (var xx = 0; xx < im.width; xx++) {
          final p = im.getPixel(xx, yy);
          if (p.r < 250 || p.g < 250 || p.b < 250) {
            lowest = yy;
            break;
          }
        }
      }
      // The bottom-anchored text sits in the lower third of the page.
      expect(lowest, greaterThan(im.height * 2 ~/ 3),
          skip: hasFont ? false : 'font not present');
    });

    test('supportedTemplateRange is null', () {
      expect(_renderer.supportedTemplateRange, isNull);
    });

    test('wraps a long line across multiple rows', () async {
      // Continuous flow so height reflects content (paged would clamp to the box).
      RenderContext ctxFor(String text) {
        final layout = _cardLayout();
        return RenderContext(
          document: FormDocument(
            documentId: 'd',
            templateId: 't',
            templateVersion: '1.0.0',
            metadata: FormDocumentMetadata(author: 'a', createdAt: DateTime(2026)),
            sections: [
              FormSection(sectionId: 's', index: 0, blocks: [
                FormTextBlock(blockId: 'l', index: 0, content: text),
              ]),
            ],
          ),
          layoutPolicy: layout,
          template: FormTemplate(
            templateId: 't',
            version: '1.0.0',
            name: 'T',
            schema: const FormSchema(),
            layoutPolicy: layout,
          ),
          options: const RenderOptions(pageFlow: PageFlow.continuous),
        );
      }

      final short =
          img.decodePng(Uint8List.fromList((await _renderer.render(ctxFor('one'))).content as List<int>))!;
      final long = img.decodePng(Uint8List.fromList(
          (await _renderer.render(ctxFor(List.filled(80, 'word').join(' ')))).content as List<int>))!;
      // The wrapped paragraph occupies more vertical space.
      expect(long.height, greaterThan(short.height));
    });

    test('placement image: fit contain + a no-size stamp (maxWidth default)',
        () async {
      final out = await _renderer.render(_ctx([
        // fit:contain where height is the binding constraint.
        FormImageBlock(
          blockId: 'c',
          index: 0,
          src: _pngDataUri(r: 40, g: 60, b: 80),
          style: const {
            'placement': {
              'anchor': 'center',
              'width': 30,
              'height': 8,
              'fit': 'contain',
            }
          },
        ),
        // No width/height/fit → sized from maxWidth.
        FormImageBlock(
          blockId: 'n',
          index: 1,
          src: _pngDataUri(r: 90, g: 10, b: 10),
          maxWidth: 20,
          style: const {
            'placement': {'anchor': 'top-left', 'x': 2, 'y': 2}
          },
        ),
      ]));
      final im = img.decodePng(Uint8List.fromList(out.content as List<int>))!;
      expect(_nonWhitePixels(im), greaterThan(20));
    });

    test('renders an in-flow image block (data-URI)', () async {
      final out = await _renderer.render(_ctx([
        FormImageBlock(
            blockId: 'img', index: 0, src: _pngDataUri(), maxWidth: 40),
      ]));
      final im = img.decodePng(Uint8List.fromList(out.content as List<int>))!;
      // The coloured image was composited → not blank.
      expect(_nonWhitePixels(im), greaterThan(20));
    });

    test('image placement: full-bleed background (z:back, cover) + a stamp',
        () async {
      final out = await _renderer.render(_ctx([
        FormTextBlock(blockId: 't', index: 0, content: 'over background'),
        // Full-page background behind the flow.
        FormImageBlock(
          blockId: 'bg',
          index: 1,
          src: _pngDataUri(r: 200, g: 210, b: 220),
          style: const {
            'placement': {
              'anchor': 'top-left',
              'width': 'full',
              'height': 'full',
              'z': 'back',
              'fit': 'cover',
            }
          },
        ),
        // A stamp anchored bottom-right.
        FormImageBlock(
          blockId: 'stamp',
          index: 2,
          src: _pngDataUri(r: 220, g: 30, b: 30),
          style: const {
            'placement': {'anchor': 'bottom-right', 'x': 5, 'y': 5, 'width': 15}
          },
        ),
      ]));
      final im = img.decodePng(Uint8List.fromList(out.content as List<int>))!;
      // Background fills the card → almost every pixel is non-white.
      expect(_nonWhitePixels(im), greaterThan(im.width * im.height ~/ 2));
      // The stamp (red) sits in the bottom-right quadrant.
      var redInBr = 0;
      for (var yy = im.height ~/ 2; yy < im.height; yy++) {
        for (var xx = im.width ~/ 2; xx < im.width; xx++) {
          final p = im.getPixel(xx, yy);
          if (p.r > 150 && p.g < 100 && p.b < 100) redInBr++;
        }
      }
      expect(redInBr, greaterThan(0));
    });

    test('continuous flow grows to content (not the fixed page box)', () async {
      final layout = _cardLayout();
      final ctx = RenderContext(
        document: FormDocument(
          documentId: 'd',
          templateId: 't',
          templateVersion: '1.0.0',
          metadata: FormDocumentMetadata(author: 'a', createdAt: DateTime(2026)),
          sections: [
            FormSection(sectionId: 's', index: 0, title: 'Section Title', blocks: [
              FormTextBlock(blockId: 't', index: 0, content: 'one line'),
            ]),
          ],
        ),
        layoutPolicy: layout,
        template: FormTemplate(
          templateId: 't',
          version: '1.0.0',
          name: 'T',
          schema: const FormSchema(),
          layoutPolicy: layout,
        ),
        options: const RenderOptions(pageFlow: PageFlow.continuous),
      );
      final out = await _renderer.render(ctx);
      final im = img.decodePng(Uint8List.fromList(out.content as List<int>))!;
      // Card page box is 50mm tall; short continuous content crops well under it.
      final pageBoxH = (50 * 150 / 25.4).round();
      expect(im.height, lessThan(pageBoxH));
    });

    test('reads cmap format-12 and looks up supplementary-plane glyphs',
        () async {
      final font = TrueTypeFont.parse(File(cmap12Path).readAsBytesSync());
      // Find a code point the font maps through its format-12 subtable.
      int? mapped;
      for (var cp = 0x10530; cp <= 0x10570; cp++) {
        if ((font.gidFor(cp) ?? 0) != 0) {
          mapped = cp;
          break;
        }
      }
      expect(mapped, isNotNull, reason: 'expected a format-12 mapped glyph');
      // Exercise the binary search: a hit, a below-range and an above-range miss.
      expect(font.gidFor(mapped!), isNotNull);
      font.gidFor(0x20); // below all groups
      font.gidFor(0x10FFFF); // above all groups
      final out = await _renderer.render(_ctx([
        FormTextBlock(
            blockId: 't', index: 0, content: String.fromCharCode(mapped)),
      ], font: font));
      expect(img.decodePng(Uint8List.fromList(out.content as List<int>)),
          isNotNull);
    }, skip: hasCmap12 ? false : 'cmap-12 font not present');

    test('rasterizes real glyphs (non-blank output) with an injected font',
        () async {
      final font = TrueTypeFont.parse(File(fontPath).readAsBytesSync());
      final out = await _renderer.render(_ctx([
        FormHeadingBlock(blockId: 'h', index: 0, content: '메이크마인드', level: 1),
        FormTextBlock(blockId: 't', index: 1, content: '문서 발행 엔진'),
      ], font: font));
      final decoded = img.decodePng(Uint8List.fromList(out.content as List<int>))!;
      // Glyphs were filled: the page is not entirely white.
      expect(_nonWhitePixels(decoded), greaterThan(50));
    }, skip: hasFont ? false : 'font not present');

    test('rasterizes a wide range of glyphs (off-curve contour starts)',
        () async {
      final font = TrueTypeFont.parse(File(fontPath).readAsBytesSync());
      // A broad character mix maximises the chance of hitting every glyph
      // decode path (contours that start off-curve, etc.).
      const sample =
          '가나다라마바사아자차카타파하 ABCDEFGHIJ 0123456789 '
          '国家品質保証書 @#\$%&*()_+ 세종대왕 서울특별시 프린트발행';
      final out = await _renderer.render(_ctx([
        FormHeadingBlock(blockId: 'h', index: 0, content: sample, level: 1),
        FormTextBlock(blockId: 't', index: 1, content: sample),
      ], font: font));
      final decoded = img.decodePng(Uint8List.fromList(out.content as List<int>))!;
      expect(_nonWhitePixels(decoded), greaterThan(200));
    }, skip: hasFont ? false : 'font not present');

    test('flattens glyph contours that start off-curve (both tail cases)',
        () async {
      // A short-loca font with off-curve-start glyphs in both tail variants.
      // (AppleGothic normalises every start to on-curve and uses long loca, so
      // it can't exercise these defensive paths.)
      final font = TrueTypeFont.parse(File(offCurvePath).readAsBytesSync());
      final sb = StringBuffer();
      var lastOn = false, lastOff = false;
      for (var cp = 0x20; cp <= 0x2FA1D && !(lastOn && lastOff); cp++) {
        final gid = font.gidFor(cp);
        if (gid == null || gid == 0) continue;
        for (final c in font.glyphContours(gid)) {
          if (c.isNotEmpty && !c.first.$3) {
            if (c.last.$3 && !lastOn) {
              sb.writeCharCode(cp);
              lastOn = true;
            } else if (!c.last.$3 && !lastOff) {
              sb.writeCharCode(cp);
              lastOff = true;
            }
          }
        }
      }
      expect(lastOn && lastOff, isTrue,
          reason: 'expected the font to expose both off-curve-start variants');
      final out = await _renderer.render(_ctx([
        FormTextBlock(blockId: 't', index: 0, content: sb.toString()),
      ], font: font));
      final im = img.decodePng(Uint8List.fromList(out.content as List<int>))!;
      expect(_nonWhitePixels(im), greaterThan(20));
    }, skip: hasOffCurve ? false : 'Verdana Bold font not present');
  });
}
