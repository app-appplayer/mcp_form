import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/markdown_renderer.dart';
import 'package:test/test.dart';

const _renderer = MarkdownRenderer();

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

RenderContext _ctx(FormDocument doc, {bool includeMetadata = false}) {
  return RenderContext(
    document: doc,
    layoutPolicy: _makeTemplate().layoutPolicy,
    template: _makeTemplate(),
    options: RenderOptions(includeMetadata: includeMetadata),
  );
}

String _renderToString(FormRenderOutput output) {
  return utf8.decode(output.content as List<int>);
}

void main() {
  group('MarkdownRenderer', () {
    test('supportedFormats includes markdown', () {
      expect(_renderer.supportedFormats, contains('markdown'));
    });

    // TC-394: Minimal document
    test('renders minimal document as valid UTF-8', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(blockId: 'txt', index: 0, content: 'Hello'),
          ]),
        ]),
      ));
      final md = _renderToString(output);
      expect(md, contains('Hello'));
    });

    // TC-395: Section title as ##
    test('renders section title as ##', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          const FormSection(
            sectionId: 's1',
            index: 0,
            title: 'Overview',
          ),
        ]),
      ));
      final md = _renderToString(output);
      expect(md, contains('## Overview'));
    });

    // TC-396: TextBlock as paragraph
    test('renders text block as paragraph', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(blockId: 'txt', index: 0, content: 'Paragraph text'),
          ]),
        ]),
      ));
      final md = _renderToString(output);
      expect(md, contains('Paragraph text'));
    });

    // TC-397-398: HeadingBlock with correct # count
    test('renders heading with correct # count', () async {
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
      final md = _renderToString(output);
      expect(md, contains('### Title'));
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
      final md = _renderToString(output);
      expect(md, contains('# Low'));
    });

    // TC-399: TableBlock as GFM pipe table
    test('renders table as GFM pipe table', () async {
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
      final md = _renderToString(output);
      expect(md, contains('| Name | Value |'));
      expect(md, contains('| --- | --- |'));
      expect(md, contains('| Alice | 100 |'));
    });

    // TC-400: ImageBlock
    test('renders image with markdown syntax', () async {
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
      final md = _renderToString(output);
      expect(md, contains('![A photo](photo.png)'));
    });

    // TC-401: ChartBlock as blockquote
    test('renders chart as blockquote', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormChartBlock(
              blockId: 'chart',
              index: 0,
              chartType: 'bar',
              unit: 'kg',
            ),
          ]),
        ]),
      ));
      final md = _renderToString(output);
      expect(md, contains('> **Chart** (bar) - Units: kg'));
    });

    // TC-402-403: FormFieldBlock
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
      final md = _renderToString(output);
      expect(md, contains('**Inspector**: John'));
    });

    test('renders unfilled form field', () async {
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
      final md = _renderToString(output);
      expect(md, contains('**Inspector**: _unfilled_'));
    });

    // TC-406-407: YAML metadata
    test('includes YAML front matter when includeMetadata=true', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(),
        includeMetadata: true,
      ));
      final md = _renderToString(output);
      expect(md, startsWith('---\n'));
      expect(md, contains('templateId: tpl-1'));
      expect(md, contains('author: tester'));
    });

    test('excludes YAML front matter when includeMetadata=false', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final md = _renderToString(output);
      expect(md, isNot(startsWith('---\n')));
    });

    // TC: RepeatableBlock renders each item template block
    test('renders repeatable block item templates', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormRepeatableBlock(
              blockId: 'rep',
              index: 0,
              itemTemplate: [
                FormTextBlock(blockId: 'rt1', index: 0, content: 'Item A'),
                FormTextBlock(blockId: 'rt2', index: 1, content: 'Item B'),
              ],
            ),
          ]),
        ]),
      ));
      final md = _renderToString(output);
      expect(md, contains('Item A'));
      expect(md, contains('Item B'));
    });

    // TC: ConditionalBlock renders thenBlock by default
    test('renders conditional block thenBlock', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormConditionalBlock(
              blockId: 'cond',
              index: 0,
              condition: 'status == "active"',
              thenBlock: FormTextBlock(
                blockId: 'then-txt',
                index: 0,
                content: 'Condition met',
              ),
            ),
          ]),
        ]),
      ));
      final md = _renderToString(output);
      expect(md, contains('Condition met'));
    });

    // TC-408: Deterministic timestamp
    test('uses document modifiedAt for generatedAt', () async {
      final fixedTime = DateTime.utc(2026, 1, 15, 10);
      final output = await _renderer.render(_ctx(
        _makeDoc(modifiedAt: fixedTime),
        includeMetadata: true,
      ));
      final md = _renderToString(output);
      expect(md, contains('generatedAt: ${fixedTime.toIso8601String()}'));
      expect(output.generatedAt, fixedTime);
    });
  });
}
