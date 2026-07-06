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

    test('style.placement image is absolute-positioned, out of flow', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormImageBlock(
              blockId: 'seal',
              index: 0,
              src: 'stamp.png',
              alt: 'seal',
              maxWidth: 80,
              style: const {
                'placement': {
                  'anchor': 'bottom-left',
                  'x': 10,
                  'y': 15,
                }
              },
            ),
          ]),
        ]),
      ));
      final html = _renderToString(output);
      expect(html, contains('position: absolute'));
      expect(html, contains('bottom: 15'));
      expect(html, contains('left: 10'));
      // The positioned page box (relative + min-height) anchors bottom to the
      // paper, not the content height (defect 1).
      expect(html, contains('position: relative'));
      expect(html, contains('min-height:'));
    });

    test('non-image placement (text block) is also pulled out and absolute',
        () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(
              blockId: 'co',
              index: 0,
              content: 'Makemind Inc.',
              style: const {
                'placement': {'anchor': 'bottom-center', 'y': 12}
              },
            ),
          ]),
        ]),
      ));
      final html = _renderToString(output);
      // Company name is absolute-positioned (bottom-center), not in flow.
      expect(html, contains('position: absolute'));
      expect(html, contains('translateX(-50%)'));
      expect(html, contains('Makemind Inc.'));
    });

    test('background image: z-back + full-bleed + object-fit cover', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormImageBlock(
              blockId: 'bg',
              index: 0,
              src: 'hero.jpg',
              style: const {
                'placement': {
                  'anchor': 'top-left',
                  'x': 0,
                  'y': 0,
                  'width': 'full',
                  'height': 'full',
                  'z': 'back',
                  'fit': 'cover',
                }
              },
            ),
          ]),
        ]),
      ));
      final html = _renderToString(output);
      expect(html, contains('z-index: -1'));
      expect(html, contains('object-fit: cover'));
      expect(html, contains('width: 100%'));
    });

    test('pageBorder option draws a page frame (border on the page box)',
        () async {
      final output = await _renderer.render(RenderContext(
        document: _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(blockId: 't', index: 0, content: 'x'),
          ]),
        ]),
        layoutPolicy: _makeTemplate().layoutPolicy,
        template: _makeTemplate(),
        options: const RenderOptions(
          pageBorder: true,
          pageBorderColor: '#333333',
          pageBorderWidth: 2,
        ),
      ));
      final html = _renderToString(output);
      expect(html, contains('border: 2'));
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
      // Headings carry an id anchor (for TOC links) and may be auto-numbered;
      // an unnumbered heading renders its text verbatim.
      expect(html, contains('<h3 id="h">Title</h3>'));
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
      expect(html, contains('<h1 id="h">Low</h1>'));
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
    test('renders chart as inline SVG with data-type', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormChartBlock(
              blockId: 'chart',
              index: 0,
              chartType: 'bar',
              title: 'Sales',
              data: const [
                {
                  'label': 'Q1',
                  'points': [
                    {'x': 'Jan', 'y': 10},
                    {'x': 'Feb', 'y': 20},
                  ],
                },
              ],
            ),
          ]),
        ]),
      ));
      final html = _renderToString(output);
      expect(html, contains('class="chart"'));
      expect(html, contains('data-type="bar"'));
      // Native SVG output, not a text placeholder.
      expect(html, contains('<svg'));
      expect(html, contains('<rect ')); // bars
      expect(html, contains('>Jan</text>')); // category label
      expect(html, isNot(contains('<strong>Chart</strong>')));
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
    test('renders thenBlock when the condition holds', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(data: {'score': 85}, sections: [
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

    test('page break, placement anchors and page border with radius', () async {
      final doc = _makeDoc(sections: [
        FormSection(sectionId: 's', index: 0, blocks: [
          FormTextBlock(blockId: 'a', index: 0, content: 'cover'),
          FormTextBlock(
              blockId: 'b',
              index: 1,
              content: 'body',
              style: const {'pageBreak': 'before'}),
          FormTextBlock(
              blockId: 'tc',
              index: 2,
              content: 'top center',
              style: const {
                'placement': {'anchor': 'top-center', 'y': 5}
              }),
          FormTextBlock(
              blockId: 'bc',
              index: 3,
              content: 'bottom center',
              style: const {
                'placement': {'anchor': 'bottom-center', 'y': 5}
              }),
          FormTextBlock(
              blockId: 'ce',
              index: 4,
              content: 'center',
              style: const {
                'placement': {'anchor': 'center'}
              }),
          FormTextBlock(
              blockId: 'br',
              index: 5,
              content: 'stamp',
              style: const {
                'placement': {'anchor': 'bottom-right', 'x': 5, 'y': 5}
              }),
        ]),
      ]);
      final out = await _renderer.render(RenderContext(
        document: doc,
        layoutPolicy: _makeTemplate().layoutPolicy,
        template: _makeTemplate(),
        options: const RenderOptions(
          pageBorder: true,
          pageBorderWidth: 2,
          pageBorderRadius: 8,
        ),
      ));
      final html = _renderToString(out);
      expect(html, contains('break-before: page'));
      expect(html, contains('border-radius: 8'));
      expect(html, contains('translateX(-50%)')); // top/bottom-center
      expect(html, contains('translate(-50%, -50%)')); // center
    });
  });
}
