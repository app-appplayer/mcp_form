import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/html_renderer.dart';
import 'package:test/test.dart';

const _renderer = HtmlRenderer();

FormDocument _makeDoc({
  List<FormSection> sections = const [],
  Map<String, dynamic> data = const {},
  DateTime? modifiedAt,
}) {
  return FormDocument(
    documentId: 'doc-1',
    templateId: 'tpl-1',
    templateVersion: '1.0.0',
    metadata: FormDocumentMetadata(
      author: 'tester',
      createdAt: DateTime(2026),
      modifiedAt: modifiedAt,
    ),
    sections: sections,
    data: data,
  );
}

FormTemplate _makeTemplate() {
  return FormTemplate(
    templateId: 'tpl-1',
    version: '1.0.0',
    name: 'Test',
    schema: const FormSchema(),
    layoutPolicy: const FormLayoutPolicy(
      pageSize: FormPageSize(size: 'A4', width: 210, height: 297),
      margins: FormMargins(top: 20, right: 20, bottom: 20, left: 20),
      fontPolicy: FormFontPolicy(
        defaultFont: 'sans-serif',
        defaultSize: 12,
        headingSize: 18,
        bodySize: 12,
        minSize: 8,
      ),
    ),
  );
}

RenderContext _ctx(
  FormDocument doc, {
  bool includeMetadata = false,
  bool applyWatermark = false,
  String? watermarkText,
}) {
  return RenderContext(
    document: doc,
    layoutPolicy: _makeTemplate().layoutPolicy,
    template: _makeTemplate(),
    options: RenderOptions(
      includeMetadata: includeMetadata,
      applyWatermark: applyWatermark,
      watermarkText: watermarkText,
    ),
  );
}

String _renderToString(FormRenderOutput output) {
  return utf8.decode(output.content as List<int>);
}

void main() {
  group('HtmlRenderer', () {
    test('supportedFormats includes html', () {
      expect(_renderer.supportedFormats, contains('html'));
    });

    test('renders valid HTML5 document', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(blockId: 'txt', index: 0, content: 'Hello'),
          ]),
        ]),
      ));
      final html = _renderToString(output);
      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('<meta charset="UTF-8">'));
      expect(html, contains('</html>'));
    });

    test('renders section title as h2', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          const FormSection(
            sectionId: 's1',
            index: 0,
            title: 'Overview',
          ),
        ]),
      ));
      final html = _renderToString(output);
      expect(html, contains('<h2>Overview</h2>'));
    });

    // TextBlock
    test('renders text block as paragraph', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(
              blockId: 'txt',
              index: 0,
              content: 'Paragraph text',
            ),
          ]),
        ]),
      ));
      final html = _renderToString(output);
      expect(html, contains('<p>Paragraph text</p>'));
    });

    // HeadingBlock
    test('renders heading with correct level', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormHeadingBlock(
              blockId: 'h',
              index: 0,
              content: 'Title',
              level: 3,
            ),
          ]),
        ]),
      ));
      final html = _renderToString(output);
      expect(html, contains('<h3>Title</h3>'));
    });

    test('clamps heading level to 1-6', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormHeadingBlock(
              blockId: 'h',
              index: 0,
              content: 'Low',
              level: 0,
            ),
          ]),
        ]),
      ));
      final html = _renderToString(output);
      expect(html, contains('<h1>Low</h1>'));
    });

    // TableBlock
    test('renders table with headers and rows', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTableBlock(
              blockId: 'tbl',
              index: 0,
              columns: [
                const FormTableColumn(
                  id: 'name',
                  title: 'Name',
                  type: 'string',
                ),
                const FormTableColumn(
                  id: 'val',
                  title: 'Value',
                  type: 'string',
                ),
              ],
              rows: [FormTableRow(cells: {'name': 'Alice', 'val': '100'})],
            ),
          ]),
        ]),
      ));
      final html = _renderToString(output);
      expect(html, contains('<th>Name</th>'));
      expect(html, contains('<th>Value</th>'));
      expect(html, contains('<td>Alice</td>'));
      expect(html, contains('<td>100</td>'));
    });

    // ImageBlock
    test('renders image with figure and img tags', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormImageBlock(
              blockId: 'img',
              index: 0,
              src: 'photo.png',
              alt: 'A photo',
            ),
          ]),
        ]),
      ));
      final html = _renderToString(output);
      expect(html, contains('<figure>'));
      expect(html, contains('src="photo.png"'));
      expect(html, contains('alt="A photo"'));
    });

    test('renders image with maxWidth style', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormImageBlock(
              blockId: 'img',
              index: 0,
              src: 'photo.png',
              maxWidth: 300,
            ),
          ]),
        ]),
      ));
      final html = _renderToString(output);
      expect(html, contains('max-width: 300'));
    });

    // ChartBlock
    test('renders chart as div with data-type', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormChartBlock(
              blockId: 'chart',
              index: 0,
              chartType: 'bar',
            ),
          ]),
        ]),
      ));
      final html = _renderToString(output);
      expect(html, contains('class="chart"'));
      expect(html, contains('data-type="bar"'));
      expect(html, contains('<strong>Chart</strong> (bar)'));
    });

    // FormFieldBlock
    test('renders filled form field', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(
          sections: [
            FormSection(sectionId: 's1', index: 0, blocks: [
              FormFieldBlock(
                blockId: 'f',
                index: 0,
                fieldName: 'Inspector',
                fieldType: 'text',
              ),
            ]),
          ],
          data: {'Inspector': 'John'},
        ),
      ));
      final html = _renderToString(output);
      expect(html, contains('class="form-field"'));
      expect(html, contains('<strong>Inspector</strong>'));
      expect(html, contains('John'));
    });

    test('renders unfilled form field with italic', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormFieldBlock(
              blockId: 'f',
              index: 0,
              fieldName: 'Inspector',
              fieldType: 'text',
            ),
          ]),
        ]),
      ));
      final html = _renderToString(output);
      expect(html, contains('form-field unfilled'));
      expect(html, contains('<em>unfilled</em>'));
    });

    // RepeatableBlock
    test('renders repeatable block content', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormRepeatableBlock(
              blockId: 'rep',
              index: 0,
              itemTemplate: [
                FormTextBlock(blockId: 'item', index: 0, content: 'Repeated'),
              ],
            ),
          ]),
        ]),
      ));
      final html = _renderToString(output);
      expect(html, contains('class="repeatable"'));
      expect(html, contains('<p>Repeated</p>'));
    });

    // ConditionalBlock
    test('renders thenBlock by default', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormConditionalBlock(
              blockId: 'cond',
              index: 0,
              condition: 'data.score >= 80',
              thenBlock: FormTextBlock(
                blockId: 'then',
                index: 0,
                content: 'Pass',
              ),
              elseBlock: FormTextBlock(
                blockId: 'else',
                index: 0,
                content: 'Fail',
              ),
            ),
          ]),
        ]),
      ));
      final html = _renderToString(output);
      expect(html, contains('<p>Pass</p>'));
    });

    // Metadata
    test('includes metadata when includeMetadata=true', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(),
        includeMetadata: true,
      ));
      final html = _renderToString(output);
      expect(html, contains('name="author" content="tester"'));
      expect(html, contains('name="templateId" content="tpl-1"'));
    });

    test('excludes metadata when includeMetadata=false', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final html = _renderToString(output);
      expect(html, isNot(contains('name="author"')));
    });

    // Watermark
    test('renders watermark when applied', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(),
        applyWatermark: true,
        watermarkText: 'CONFIDENTIAL',
      ));
      final html = _renderToString(output);
      expect(html, contains('class="watermark"'));
      expect(html, contains('CONFIDENTIAL'));
    });

    // HTML escaping
    test('escapes HTML entities in content', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(
              blockId: 'txt',
              index: 0,
              content: '<script>alert("xss")</script>',
            ),
          ]),
        ]),
      ));
      final html = _renderToString(output);
      expect(html, contains('&lt;script&gt;'));
      expect(html, isNot(contains('<script>')));
    });

    // Output metadata
    test('output format is html', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      expect(output.format, 'html');
    });

    test('output has file size', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      expect(output.fileSize, greaterThan(0));
    });

    test('uses document modifiedAt for generatedAt', () async {
      final fixedTime = DateTime.utc(2026, 1, 15, 10);
      final output = await _renderer.render(_ctx(
        _makeDoc(modifiedAt: fixedTime),
      ));
      expect(output.generatedAt, fixedTime);
    });

    // Embedded CSS
    test('includes embedded CSS styles', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final html = _renderToString(output);
      expect(html, contains('<style>'));
      expect(html, contains('font-family'));
      expect(html, contains('border-collapse'));
    });
  });
}
