import 'dart:convert';

import 'package:image/image.dart' as img;
import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/pdf_renderer.dart';
import 'package:test/test.dart';

String _pngDataUri({int r = 10, int g = 20, int b = 30}) {
  final im = img.Image(width: 4, height: 3);
  img.fill(im, color: img.ColorRgb8(r, g, b));
  return 'data:image/png;base64,${base64Encode(img.encodePng(im))}';
}

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

RenderContext _ctx(List<FormBlock> blocks,
    {RenderOptions options = const RenderOptions(compress: false),
    double height = 297}) {
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
    options: options,
  );
}

String _latin(FormRenderOutput o) =>
    latin1.decode(o.content as List<int>, allowInvalid: true);

void main() {
  group('placement, backgrounds & page breaks', () {
    test('style.pageBreak before/after forces new pages (full-width and row)',
        () async {
      final out = await const PdfRenderer().render(_ctx([
        FormTextBlock(blockId: 'a', index: 0, content: 'cover'),
        FormTextBlock(
            blockId: 'b',
            index: 1,
            content: 'body',
            style: const {'pageBreak': 'before'}), // before
        FormTextBlock(
            blockId: 'c',
            index: 2,
            content: 'section',
            style: const {'pageBreak': 'after'}), // full-width after
        // A row (colSpan < 12) whose last block breaks after.
        FormTextBlock(
            blockId: 'd1', index: 3, content: 'L', style: const {'colSpan': 6}),
        FormTextBlock(
            blockId: 'd2',
            index: 4,
            content: 'R',
            style: const {'colSpan': 6, 'pageBreak': 'after'}), // row after
        FormTextBlock(blockId: 'e', index: 5, content: 'tail'),
      ]));
      expect(out.pageCount, greaterThanOrEqualTo(3));
    });

    test('image placement across anchors, fit variants and z-back background',
        () async {
      final out = await const PdfRenderer().render(_ctx([
        FormTextBlock(blockId: 't', index: 0, content: 'over background'),
        // Full-bleed background behind the flow (cover, else-branch of fit).
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
        // contain (if-branch of fit) at bottom-right.
        FormImageBlock(
          blockId: 's1',
          index: 2,
          src: _pngDataUri(r: 220, g: 30, b: 30),
          style: const {
            'placement': {
              'anchor': 'bottom-right',
              'x': 5,
              'y': 5,
              'width': 20,
              'height': 20,
              'fit': 'contain',
            }
          },
        ),
        // No fit → sized from maxWidth, at top-right.
        FormImageBlock(
          blockId: 's2',
          index: 3,
          src: _pngDataUri(),
          maxWidth: 30,
          style: const {
            'placement': {'anchor': 'top-right', 'x': 5, 'y': 5}
          },
        ),
        // Remaining anchors with explicit sizes for placeBox coverage.
        for (final a in const [
          'top-left',
          'top-center',
          'bottom-left',
          'bottom-center',
          'center',
        ])
          FormImageBlock(
            blockId: 'a-$a',
            index: 10 + const [
              'top-left',
              'top-center',
              'bottom-left',
              'bottom-center',
              'center',
            ].indexOf(a),
            src: _pngDataUri(),
            style: {
              'placement': {'anchor': a, 'x': 3, 'y': 3, 'width': 15, 'height': 10}
            },
          ),
      ]));
      final pdf = _latin(out);
      expect(pdf, contains('/Subtype /Image'));
    });

    test('text placement + page border with radius', () async {
      final out = await const PdfRenderer().render(
        _ctx(
          [
            FormTextBlock(
              blockId: 'seal',
              index: 0,
              content: 'CERTIFIED',
              style: const {
                'placement': {'anchor': 'center'}
              },
            ),
          ],
          options: const RenderOptions(
            compress: false,
            pageBorder: true,
            pageBorderWidth: 2,
            pageBorderRadius: 6,
          ),
        ),
      );
      expect(_latin(out), isNotEmpty);
      expect(out.pageCount, greaterThanOrEqualTo(1));
    });
  });

  group('clickable links', () {
    test('markdown link becomes a Link annotation', () async {
      final out = await const PdfRenderer().render(_ctx([
        FormTextBlock(
            blockId: 't',
            index: 0,
            format: 'markdown',
            content: 'see [docs](https://makemind.dev)'),
      ]));
      final pdf = _latin(out);
      expect(pdf, contains('/Subtype /Link'));
      expect(pdf, contains('/URI (https://makemind.dev)'));
    });
  });

  group('header / footer / page numbers', () {
    test('page number and footer text are drawn', () async {
      final out = await const PdfRenderer().render(_ctx(
        [
          for (var i = 0; i < 90; i++)
            FormTextBlock(blockId: 't$i', index: i, content: 'Row $i'),
        ],
        options: const RenderOptions(
          compress: false,
          showPageNumbers: true,
          footerText: 'CONFIDENTIAL',
          pageNumberTemplate: '{page}/{total}',
        ),
      ));
      expect(out.pageCount, greaterThan(1));
      final pdf = _latin(out);
      expect(pdf, contains('(CONFIDENTIAL) Tj'));
      expect(pdf, contains('(1/${out.pageCount}) Tj'));
    });
  });

  group('compression', () {
    test('compressed output is smaller and uses FlateDecode', () async {
      final blocks = [
        for (var i = 0; i < 60; i++)
          FormTextBlock(
              blockId: 't$i', index: i, content: 'Repeated content line $i ' * 6),
      ];
      final plain = await const PdfRenderer()
          .render(_ctx(blocks, options: const RenderOptions(compress: false)));
      final comp = await const PdfRenderer()
          .render(_ctx(blocks, options: const RenderOptions()));
      expect(_latin(comp), contains('/FlateDecode'));
      expect((comp.content as List).length,
          lessThan((plain.content as List).length));
    });
  });

  group('watermark config', () {
    test('honours colour, opacity and angle', () async {
      final out = await const PdfRenderer().render(_ctx(
        [FormTextBlock(blockId: 't', index: 0, content: 'body')],
        options: const RenderOptions(
          compress: false,
          applyWatermark: true,
          watermarkText: 'DRAFT',
          watermarkColor: '#FF0000',
          watermarkOpacity: 0.3,
          watermarkAngle: 30,
        ),
      ));
      final pdf = _latin(out);
      expect(pdf, contains('/GSwm gs'));
      expect(pdf, contains('/ca 0.300'));
      expect(pdf, contains('1.000 0.000 0.000 rg'));
      expect(pdf, contains('(DRAFT) Tj'));
    });
  });

  group('table cell rich content', () {
    test('cellFormat markdown bolds inside a cell', () async {
      final out = await const PdfRenderer().render(_ctx([
        FormTableBlock(
          blockId: 'tbl',
          index: 0,
          style: const {'cellFormat': 'markdown'},
          columns: const [
            FormTableColumn(id: 'a', title: 'Item', type: 'string'),
          ],
          rows: [
            FormTableRow(cells: {'a': '**bold** cell'}),
          ],
        ),
      ]));
      // Body cell uses the bold font from markdown.
      expect(_latin(out), contains('/F2'));
    });
  });

  group('justify', () {
    test('justified paragraph still renders valid text', () async {
      final out = await const PdfRenderer().render(_ctx([
        FormTextBlock(
          blockId: 't',
          index: 0,
          content: 'one two three four five six seven eight nine ten eleven '
              'twelve thirteen fourteen fifteen sixteen seventeen',
          style: const {'align': 'justify'},
        ),
      ]));
      final pdf = _latin(out);
      expect(pdf, contains('(one) Tj'));
      expect(pdf, contains('%PDF'));
    });
  });
}
