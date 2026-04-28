import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/docx_renderer.dart';
import 'package:test/test.dart';

const _renderer = DocxRenderer();

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
  group('DocxRenderer', () {
    test('supportedFormats includes docx', () {
      expect(_renderer.supportedFormats, contains('docx'));
    });

    test('output format is docx', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      expect(output.format, 'docx');
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

    test('uses createdAt when modifiedAt is null', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      expect(output.generatedAt, DateTime(2026));
    });

    // OOXML structure

    test('contains XML declaration', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final xml = _renderToString(output);
      expect(xml, contains('<?xml version="1.0"'));
    });

    test('contains OOXML namespace', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final xml = _renderToString(output);
      expect(
        xml,
        contains(
          'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"',
        ),
      );
    });

    test('contains mso-application processing instruction', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final xml = _renderToString(output);
      expect(xml, contains('<?mso-application progid="Word.Document"?>'));
    });

    test('contains body element', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final xml = _renderToString(output);
      expect(xml, contains('<w:body>'));
      expect(xml, contains('</w:body>'));
    });

    // Page size from layout policy

    test('page size from layout policy is present in section properties',
        () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final xml = _renderToString(output);
      expect(xml, contains('<w:pgSz'));
      expect(xml, contains('<w:pgMar'));
    });

    // Font table

    test('font table references layout font family', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final xml = _renderToString(output);
      expect(xml, contains('<w:fonts>'));
      expect(xml, contains('w:ascii="sans-serif"'));
    });

    // Heading styles

    test('heading styles exist for levels 1-6', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final xml = _renderToString(output);
      for (var level = 1; level <= 6; level++) {
        expect(xml, contains('w:styleId="Heading$level"'));
      }
    });

    test('heading styles include bold and outline level', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final xml = _renderToString(output);
      expect(xml, contains('<w:b/>'));
      expect(xml, contains('<w:outlineLvl'));
    });

    // Normal style

    test('Normal style with body font size', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final xml = _renderToString(output);
      expect(xml, contains('w:styleId="Normal"'));
      // bodySize=12, half-points=24
      expect(xml, contains('<w:sz w:val="24"/>'));
    });

    // Table style

    test('TableGrid style with borders', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final xml = _renderToString(output);
      expect(xml, contains('w:styleId="TableGrid"'));
      expect(xml, contains('<w:tblBorders>'));
    });

    // Block type rendering

    test('renders text block as paragraph', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(blockId: 'txt', index: 0, content: 'Paragraph text'),
          ]),
        ]),
      ));
      final xml = _renderToString(output);
      expect(xml, contains('Paragraph text'));
      expect(xml, contains('<w:p>'));
    });

    test('renders heading block with heading style', () async {
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
      final xml = _renderToString(output);
      expect(xml, contains('<w:pStyle w:val="Heading3"/>'));
      expect(xml, contains('Title'));
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
      final xml = _renderToString(output);
      expect(xml, contains('<w:pStyle w:val="Heading1"/>'));
    });

    test('renders table with borders and header row', () async {
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
      final xml = _renderToString(output);
      expect(xml, contains('<w:tbl>'));
      expect(xml, contains('<w:tblHeader/>'));
      expect(xml, contains('<w:tc>'));
      expect(xml, contains('Name'));
      expect(xml, contains('Value'));
      expect(xml, contains('Alice'));
      expect(xml, contains('100'));
      // Table borders
      expect(xml, contains('w:val="single"'));
      // Column grid
      expect(xml, contains('<w:gridCol'));
      // Header row shading
      expect(xml, contains('w:fill="F5F5F5"'));
    });

    test('renders image block as placeholder paragraph', () async {
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
      final xml = _renderToString(output);
      expect(xml, contains('[Image: A photo]'));
      expect(xml, contains('Source: photo.png'));
    });

    test('renders image with maxWidth note', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormImageBlock(
              blockId: 'img',
              index: 0,
              src: 'photo.png',
              alt: 'A photo',
              maxWidth: 300,
            ),
          ]),
        ]),
      ));
      final xml = _renderToString(output);
      expect(xml, contains('max-width: 300'));
    });

    test('renders image with default alt when alt is null', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormImageBlock(
              blockId: 'img',
              index: 0,
              src: 'photo.png',
            ),
          ]),
        ]),
      ));
      final xml = _renderToString(output);
      expect(xml, contains('[Image: Image]'));
    });

    test('renders chart block as placeholder', () async {
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
      final xml = _renderToString(output);
      expect(xml, contains('[Chart: bar]'));
    });

    test('renders filled form field with bold label', () async {
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
      final xml = _renderToString(output);
      expect(xml, contains('Inspector: '));
      expect(xml, contains('John'));
      expect(xml, contains('<w:b/>'));
    });

    test('renders unfilled form field with italic unfilled text', () async {
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
      final xml = _renderToString(output);
      expect(xml, contains('Inspector: '));
      expect(xml, contains('unfilled'));
      expect(xml, contains('<w:i/>'));
      expect(xml, contains('w:val="999999"'));
    });

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
      final xml = _renderToString(output);
      expect(xml, contains('Item A'));
      expect(xml, contains('Item B'));
    });

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
      final xml = _renderToString(output);
      expect(xml, contains('Condition met'));
    });

    // Section title

    test('renders section title as Heading2', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          const FormSection(
            sectionId: 's1',
            index: 0,
            title: 'Overview',
          ),
        ]),
      ));
      final xml = _renderToString(output);
      expect(xml, contains('<w:pStyle w:val="Heading2"/>'));
      expect(xml, contains('Overview'));
    });

    // Metadata

    test('includes document properties when includeMetadata=true', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(),
        includeMetadata: true,
      ));
      final xml = _renderToString(output);
      expect(xml, contains('<o:DocumentProperties>'));
      expect(xml, contains('<o:Author>tester</o:Author>'));
      expect(xml, contains('<o:Created>'));
      expect(xml, contains('<o:LastSaved>'));
    });

    test('includes custom properties with templateId when includeMetadata=true',
        () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(),
        includeMetadata: true,
      ));
      final xml = _renderToString(output);
      expect(xml, contains('<o:CustomDocumentProperties>'));
      expect(xml, contains('<o:templateId>tpl-1</o:templateId>'));
      expect(xml, contains('<o:templateName>Test</o:templateName>'));
    });

    test('excludes document properties when includeMetadata=false', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final xml = _renderToString(output);
      expect(xml, isNot(contains('<o:DocumentProperties>')));
      expect(xml, isNot(contains('<o:CustomDocumentProperties>')));
    });

    // Watermark

    test('renders watermark paragraph when applied', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(),
        applyWatermark: true,
        watermarkText: 'CONFIDENTIAL',
      ));
      final xml = _renderToString(output);
      expect(xml, contains('CONFIDENTIAL'));
      // Watermark uses color C0C0C0 and italic
      expect(xml, contains('w:val="C0C0C0"'));
    });

    test('does not render watermark when not applied', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final xml = _renderToString(output);
      expect(xml, isNot(contains('w:val="C0C0C0"')));
    });

    // XML escaping

    test('escapes XML entities in content', () async {
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
      final xml = _renderToString(output);
      expect(xml, contains('&lt;script&gt;'));
      expect(xml, isNot(contains('<script>')));
    });

    // Section properties with grid columns

    test('section properties include grid columns', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final xml = _renderToString(output);
      expect(xml, contains('<w:cols'));
    });

    // Metadata with engineVersion

    test('includes engineVersion in custom properties when set', () async {
      final doc = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
          engineVersion: '2.0.0',
        ),
        sections: const [],
        data: const {},
      );
      final output = await _renderer.render(_ctx(
        doc,
        includeMetadata: true,
      ));
      final xml = _renderToString(output);
      expect(
        xml,
        contains('<o:engineVersion>2.0.0</o:engineVersion>'),
      );
    });
  });
}
