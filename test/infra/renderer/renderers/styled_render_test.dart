import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/html_renderer.dart';
import 'package:mcp_form/src/infra/renderer/renderers/pdf_renderer.dart';
import 'package:mcp_form/src/infra/renderer/renderers/ui_dsl_renderer.dart';
import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

FormLayoutPolicy _layout({double height = 297}) => FormLayoutPolicy(
      pageSize: FormPageSize(size: 'A4', width: 210, height: height),
      margins: const FormMargins(top: 20, right: 20, bottom: 20, left: 20),
      fontPolicy: const FormFontPolicy(
        defaultFont: 'sans-serif',
        defaultSize: 12,
        headingSize: 18,
        bodySize: 12,
        minSize: 6,
      ),
    );

FormDocument _doc(List<FormBlock> blocks) => FormDocument(
      documentId: 'doc-1',
      templateId: 'tpl-1',
      templateVersion: '1.0.0',
      metadata: FormDocumentMetadata(author: 't', createdAt: DateTime(2026)),
      sections: [FormSection(sectionId: 's', index: 0, blocks: blocks)],
    );

RenderContext _ctx(List<FormBlock> blocks,
    {double height = 297, FormStyleSheet? sheet}) {
  final layout = _layout(height: height);
  return RenderContext(
    document: _doc(blocks),
    layoutPolicy: layout,
    template: FormTemplate(
      templateId: 'tpl-1',
      version: '1.0.0',
      name: 'T',
      schema: const FormSchema(),
      layoutPolicy: layout,
    ),
    styleSheet: sheet,
    options: const RenderOptions(compress: false),
  );
}

String _pdf(FormRenderOutput o) =>
    latin1.decode(o.content as List<int>, allowInvalid: true);
String _str(FormRenderOutput o) => utf8.decode(o.content as List<int>);

void main() {
  group('PDF styling', () {
    test('markdown bold uses the bold font', () async {
      final out = await const PdfRenderer().render(_ctx([
        FormTextBlock(
            blockId: 't', index: 0, content: '**bold** text', format: 'markdown'),
      ]));
      expect(_pdf(out), contains('/F2'));
      expect(_pdf(out), contains('bold'));
    });

    test('coloured run emits an rgb fill', () async {
      final out = await const PdfRenderer().render(_ctx([
        FormTextBlock(
          blockId: 't',
          index: 0,
          content: '<span style="color:#FF0000">red</span>',
          format: 'html',
        ),
      ]));
      expect(_pdf(out), contains('1.000 0.000 0.000 rg'));
    });

    test('underline draws a stroke line', () async {
      final out = await const PdfRenderer().render(_ctx([
        FormTextBlock(
            blockId: 't', index: 0, content: '<u>x</u>', format: 'html'),
      ]));
      expect(_pdf(out), contains(' l S'));
    });

    test('bordered block strokes a frame', () async {
      final out = await const PdfRenderer().render(_ctx([
        FormTextBlock(
          blockId: 't',
          index: 0,
          content: 'framed',
          style: {
            'border': {'width': 1, 'color': '#000000'},
            'padding': 6,
          },
        ),
      ]));
      expect(_pdf(out), contains(' l S'));
    });

    test('background block fills a rectangle', () async {
      final out = await const PdfRenderer().render(_ctx([
        FormTextBlock(
          blockId: 't',
          index: 0,
          content: 'filled',
          style: {'background': '#EEEEEE', 'padding': 4},
        ),
      ]));
      expect(_pdf(out), contains(' re f'));
    });

    test('copyfit clip drops content past the box height', () async {
      final long =
          "${List.generate(40, (i) => 'row $i').join('\n')}\nZZZEND";
      final clipped = await const PdfRenderer().render(_ctx([
        FormTextBlock(
          blockId: 't',
          index: 0,
          content: long,
          style: {'height': 40, 'overflow': 'clip'},
        ),
      ]));
      expect(_pdf(clipped), isNot(contains('ZZZEND')));

      final grown = await const PdfRenderer().render(_ctx([
        FormTextBlock(blockId: 't', index: 0, content: long),
      ]));
      expect(_pdf(grown), contains('ZZZEND'));
    });

    test('a bordered box splits across pages', () async {
      final long = List.generate(40, (i) => 'line $i').join('\n');
      final out = await const PdfRenderer().render(_ctx(
        [
          FormTextBlock(
            blockId: 't',
            index: 0,
            content: long,
            style: {
              'border': {'width': 1, 'color': '#000000'}
            },
          ),
        ],
        height: 90,
      ));
      expect(out.pageCount, greaterThan(1));
      expect(_pdf(out), contains(' l S'));
    });

    test('table renders a cell-border grid with a header fill', () async {
      final out = await const PdfRenderer().render(_ctx([
        FormTableBlock(
          blockId: 'tbl',
          index: 0,
          columns: const [
            FormTableColumn(id: 'a', title: 'Name', type: 'string'),
            FormTableColumn(id: 'b', title: 'Value', type: 'string'),
          ],
          rows: [
            FormTableRow(cells: {'a': 'Alice', 'b': '100'}),
            FormTableRow(cells: {'a': 'Bob', 'b': '90'}),
          ],
        ),
      ]));
      final pdf = _pdf(out);
      expect(pdf, contains(' l S'), reason: 'cell borders drawn');
      expect(pdf, contains(' re f'), reason: 'header cell fill drawn');
      expect(pdf, contains('(Alice) Tj'));
      expect(pdf, contains('(Name) Tj'));
    });

    FormTableBlock longCellTable(Map<String, dynamic>? style) => FormTableBlock(
          blockId: 'tbl',
          index: 0,
          style: style,
          columns: const [
            FormTableColumn(id: 'a', title: 'Notes', type: 'string'),
          ],
          rows: [
            FormTableRow(cells: {
              'a': 'This is a deliberately long cell value that wraps to '
                  'several lines so overflow handling is exercised END_TOKEN'
            }),
          ],
        );

    double minTf(String pdf) => RegExp(r'/F\d+ ([\d.]+) Tf')
        .allMatches(pdf)
        .map((m) => double.parse(m.group(1)!))
        .reduce((a, b) => a < b ? a : b);

    test('table cell shrinkToFit shrinks the font to a fixed row height',
        () async {
      final out = await const PdfRenderer().render(_ctx([
        longCellTable({'rowHeight': 18, 'overflow': 'shrink'}),
      ]));
      final pdf = _pdf(out);
      // Font scaled below the 12pt body size, and nothing was dropped.
      expect(minTf(pdf), lessThan(11));
      expect(pdf, contains('END_TOKEN'));
    });

    test('table cell clip drops content past a fixed row height', () async {
      final out = await const PdfRenderer().render(_ctx([
        longCellTable({'rowHeight': 18, 'overflow': 'clip'}),
      ]));
      expect(_pdf(out), isNot(contains('END_TOKEN')));
    });

    test('table rows grow by default (no fixed height, no shrink)', () async {
      final out = await const PdfRenderer().render(_ctx([
        longCellTable(null),
      ]));
      final pdf = _pdf(out);
      expect(pdf, contains('END_TOKEN'));
      expect(minTf(pdf), greaterThanOrEqualTo(12));
    });

    test('rowHeight with grow is a minimum — content still not clipped',
        () async {
      final out = await const PdfRenderer().render(_ctx([
        longCellTable({'rowHeight': 18, 'overflow': 'grow'}),
      ]));
      final pdf = _pdf(out);
      expect(pdf, contains('END_TOKEN'));
      expect(minTf(pdf), greaterThanOrEqualTo(12));
    });

    test('theme colour token resolves in PDF', () async {
      final sheet = FormStyleSheet.fromMap({
        'theme': {
          'colors': {'brand': '#00FF00'}
        },
      });
      final out = await const PdfRenderer().render(_ctx(
        [
          FormTextBlock(
              blockId: 't', index: 0, content: 'x', style: {'color': 'brand'}),
        ],
        sheet: sheet,
      ));
      expect(_pdf(out), contains('0.000 1.000 0.000 rg'));
    });
  });

  group('HTML styling', () {
    test('markdown bold becomes a styled span', () async {
      final out = await const HtmlRenderer().render(_ctx([
        FormTextBlock(
            blockId: 't', index: 0, content: '**b**', format: 'markdown'),
      ]));
      expect(_str(out), contains('font-weight: bold'));
    });

    test('block align emits text-align', () async {
      final out = await const HtmlRenderer().render(_ctx([
        FormHeadingBlock(
            blockId: 'h', index: 0, content: 'Title', style: {'align': 'center'}),
      ]));
      expect(_str(out), contains('text-align: center'));
    });

    test('border emits a CSS border', () async {
      final out = await const HtmlRenderer().render(_ctx([
        FormTextBlock(
          blockId: 't',
          index: 0,
          content: 'x',
          style: {
            'border': {'width': 1, 'color': '#000000'}
          },
        ),
      ]));
      expect(_str(out), contains('border:'));
    });

    test('unstyled text stays a clean paragraph', () async {
      final out = await const HtmlRenderer().render(_ctx([
        FormTextBlock(blockId: 't', index: 0, content: 'plain'),
      ]));
      expect(_str(out), contains('<p>plain</p>'));
    });
  });

  group('UI DSL styling', () {
    test('text block carries rich runs', () async {
      final out = await const UiDslRenderer().render(_ctx([
        FormTextBlock(
            blockId: 't', index: 0, content: '**b** x', format: 'markdown'),
      ]));
      final json = _str(out);
      expect(json, contains('"runs"'));
      expect(json, contains('"bold":true'));
    });
  });
}
