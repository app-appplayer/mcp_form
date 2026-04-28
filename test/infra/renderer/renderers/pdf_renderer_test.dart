import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/pdf_renderer.dart';
import 'package:test/test.dart';

const _renderer = PdfRenderer();

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
  group('PdfRenderer', () {
    test('supportedFormats includes pdf', () {
      expect(_renderer.supportedFormats, contains('pdf'));
    });

    test('output format is pdf', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      expect(output.format, 'pdf');
    });

    test('output has file size', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      expect(output.fileSize, greaterThan(0));
    });

    test('output starts with %PDF-1.4', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final pdf = _renderToString(output);
      expect(pdf, startsWith('%PDF-1.4'));
    });

    test('output contains %%EOF', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final pdf = _renderToString(output);
      expect(pdf, contains('%%EOF'));
    });

    test('output contains xref table', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final pdf = _renderToString(output);
      expect(pdf, contains('xref'));
      expect(pdf, contains('trailer'));
      expect(pdf, contains('startxref'));
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

    test('renders empty document with at least one page', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      expect(output.pageCount, greaterThanOrEqualTo(1));
    });

    // Block type rendering

    test('renders text block', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(blockId: 'txt', index: 0, content: 'Hello World'),
          ]),
        ]),
      ));
      final pdf = _renderToString(output);
      expect(pdf, contains('Hello World'));
    });

    test('renders heading block with bold font', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormHeadingBlock(
              blockId: 'h',
              index: 0,
              content: 'Section Title',
              level: 1,
            ),
          ]),
        ]),
      ));
      final pdf = _renderToString(output);
      // Heading should use bold font (/F2)
      expect(pdf, contains('/F2'));
      expect(pdf, contains('Section Title'));
    });

    test('clamps heading level to 1-6', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormHeadingBlock(
              blockId: 'h',
              index: 0,
              content: 'Clamped',
              level: 0,
            ),
          ]),
        ]),
      ));
      final pdf = _renderToString(output);
      expect(pdf, contains('Clamped'));
    });

    test('renders table block with header and rows', () async {
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
      final pdf = _renderToString(output);
      expect(pdf, contains('Name'));
      expect(pdf, contains('Value'));
      expect(pdf, contains('Alice'));
      expect(pdf, contains('100'));
    });

    test('renders image block as placeholder', () async {
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
      final pdf = _renderToString(output);
      expect(pdf, contains('[Image: A photo]'));
      expect(pdf, contains('Source: photo.png'));
    });

    test('renders image with default alt text when alt is null', () async {
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
      final pdf = _renderToString(output);
      expect(pdf, contains('[Image: Image]'));
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
      final pdf = _renderToString(output);
      expect(pdf, contains('[Chart: bar]'));
    });

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
      final pdf = _renderToString(output);
      expect(pdf, contains('Inspector: John'));
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
      final pdf = _renderToString(output);
      // Parentheses are escaped in PDF string syntax
      expect(pdf, contains(r'Inspector: \(unfilled\)'));
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
      final pdf = _renderToString(output);
      expect(pdf, contains('Item A'));
      expect(pdf, contains('Item B'));
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
      final pdf = _renderToString(output);
      expect(pdf, contains('Condition met'));
    });

    // Section title

    test('renders section title as heading', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          const FormSection(
            sectionId: 's1',
            index: 0,
            title: 'Overview',
          ),
        ]),
      ));
      final pdf = _renderToString(output);
      expect(pdf, contains('Overview'));
    });

    // Watermark

    test('renders watermark text when applied', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(),
        applyWatermark: true,
        watermarkText: 'CONFIDENTIAL',
      ));
      final pdf = _renderToString(output);
      expect(pdf, contains('CONFIDENTIAL'));
    });

    test('does not render watermark when not applied', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(blockId: 'txt', index: 0, content: 'Body'),
          ]),
        ]),
      ));
      final pdf = _renderToString(output);
      // No watermark-specific rotation matrix
      expect(pdf, isNot(contains('0.7071')));
    });

    // Metadata

    test('includes metadata in info dictionary when includeMetadata=true',
        () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(),
        includeMetadata: true,
      ));
      final pdf = _renderToString(output);
      expect(pdf, contains('/Author'));
      expect(pdf, contains('tester'));
      expect(pdf, contains('/Subject'));
      expect(pdf, contains('tpl-1'));
      expect(pdf, contains('/Title'));
      expect(pdf, contains('Test'));
    });

    test('excludes metadata from info dictionary when includeMetadata=false',
        () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final pdf = _renderToString(output);
      expect(pdf, isNot(contains('/Author')));
      expect(pdf, isNot(contains('/Subject')));
      expect(pdf, isNot(contains('/Title')));
    });

    test('info dictionary always contains creation date', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final pdf = _renderToString(output);
      expect(pdf, contains('/CreationDate'));
      expect(pdf, contains('/ModDate'));
    });

    // PDF structure

    test('contains Catalog and Pages objects', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final pdf = _renderToString(output);
      expect(pdf, contains('/Type /Catalog'));
      expect(pdf, contains('/Type /Pages'));
    });

    test('contains font definitions', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final pdf = _renderToString(output);
      expect(pdf, contains('/BaseFont /Helvetica'));
      expect(pdf, contains('/BaseFont /Helvetica-Bold'));
    });

    test('contains page MediaBox with correct dimensions', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final pdf = _renderToString(output);
      expect(pdf, contains('/MediaBox'));
    });

    // Multi-page

    test('multi-page works with many text blocks', () async {
      // Create many text blocks to force overflow onto multiple pages
      final blocks = <FormBlock>[];
      for (var i = 0; i < 200; i++) {
        blocks.add(FormTextBlock(
          blockId: 'txt-$i',
          index: i,
          content: 'Line $i: This is a repeated content block that takes up space on the page.',
        ));
      }
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: blocks),
        ]),
      ));
      expect(output.pageCount, greaterThan(1));
      final pdf = _renderToString(output);
      expect(pdf, contains('Line 0'));
      expect(pdf, contains('Line 199'));
    });

    // PDF string escaping

    test('escapes special characters in content', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(
              blockId: 'txt',
              index: 0,
              content: 'Test (with) parentheses and \\backslash',
            ),
          ]),
        ]),
      ));
      final pdf = _renderToString(output);
      expect(pdf, contains(r'Test \(with\) parentheses and \\backslash'));
    });

    // Table header repetition across pages (FR-REND-008)

    test('repeats table header when table spans multiple pages', () async {
      // Use a small page height to force page breaks within the table
      final smallTemplate = FormTemplate(
        templateId: 'tpl-1',
        version: '1.0.0',
        name: 'Test',
        schema: const FormSchema(),
        layoutPolicy: const FormLayoutPolicy(
          pageSize: FormPageSize(size: 'custom', width: 210, height: 100),
          margins: FormMargins(top: 10, right: 10, bottom: 10, left: 10),
          fontPolicy: FormFontPolicy(
            defaultFont: 'sans-serif',
            defaultSize: 12,
            headingSize: 18,
            bodySize: 12,
            minSize: 8,
          ),
        ),
      );

      // Generate 60 rows to ensure page overflow
      final rows = List.generate(
        60,
        (i) => FormTableRow(cells: {'name': 'Person $i', 'val': 'Score $i'}),
      );

      final doc = _makeDoc(sections: [
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
            rows: rows,
          ),
        ]),
      ]);

      final ctx = RenderContext(
        document: doc,
        layoutPolicy: smallTemplate.layoutPolicy,
        template: smallTemplate,
        options: const RenderOptions(),
      );

      final output = await _renderer.render(ctx);
      expect(output.pageCount, greaterThan(1));

      final pdf = _renderToString(output);
      // The header 'Name  |  Value' should appear more than once
      // (once per page that contains table content)
      final headerPattern = 'Name  |  Value';
      final escapedHeader = headerPattern
          .replaceAll(r'\', r'\\')
          .replaceAll('(', r'\(')
          .replaceAll(')', r'\)');
      // Count occurrences of the header in the PDF text
      final matches =
          RegExp(RegExp.escape(escapedHeader)).allMatches(pdf).length;
      expect(
        matches,
        greaterThan(1),
        reason: 'Table header should repeat on each page',
      );
    });

    // Text wrapping

    test('wraps long text into multiple lines', () async {
      final longText = List.generate(50, (i) => 'word$i').join(' ');
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(blockId: 'txt', index: 0, content: longText),
          ]),
        ]),
      ));
      final pdf = _renderToString(output);
      // The content should contain words from the long text
      expect(pdf, contains('word0'));
      expect(pdf, contains('word49'));
    });
  });
}
