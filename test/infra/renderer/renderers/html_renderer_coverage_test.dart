// Coverage tests for HtmlRenderer uncovered lines.
// Target: lib/src/infra/renderer/renderers/html_renderer.dart
import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/html_renderer.dart';
import 'package:mcp_form/src/style/block_style.dart';
import 'package:mcp_form/src/style/style_sheet.dart';
import 'package:test/test.dart';

const _renderer = HtmlRenderer();

FormTemplate _makeTemplate() => FormTemplate(
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

RenderContext _ctx(
  List<FormSection> sections, {
  Map<String, dynamic> data = const {},
  FormStyleSheet? styleSheet,
}) =>
    RenderContext(
      document: FormDocument(
        documentId: 'd1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
        sections: sections,
        data: data,
      ),
      layoutPolicy: _makeTemplate().layoutPolicy,
      template: _makeTemplate(),
      options: const RenderOptions(),
      styleSheet: styleSheet,
    );

String _html(FormRenderOutput out) => utf8.decode(out.content as List<int>);

void main() {
  group('HtmlRenderer coverage', () {
    // Line 217: 'upper-roman' in _listCss switch.
    test('ordered list with upper-roman numberFormat uses upper-roman CSS',
        () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormTextBlock(
              blockId: 'lst',
              index: 0,
              content: 'Item one\nItem two',
              style: const {
                'listStyle': 'ordered',
                'numberFormat': 'upper-roman',
              },
            ),
          ],
        ),
      ]));
      expect(_html(out), contains('list-style-type: upper-roman'));
    });

    // Line 438: chart with caption emits figcaption.
    test('chart with caption emits figcaption', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormChartBlock(
              blockId: 'ch',
              index: 0,
              chartType: 'bar',
              style: const {'caption': 'Quarterly Sales'},
              data: const [
                {
                  'label': 'Q1',
                  'points': [
                    {'x': 'Jan', 'y': 10},
                  ],
                }
              ],
            ),
          ],
        ),
      ]));
      final html = _html(out);
      expect(html, contains('<figcaption>'));
      expect(html, contains('Figure 1'));
    });

    // Lines 449-451: FormCanvasBlock with SVG data renders inline SVG.
    test('FormCanvasBlock with svg data renders inline SVG', () async {
      const svgContent = '<svg width="100" height="100"><circle cx="50" cy="50" r="40"/></svg>';
      final out = await _renderer.render(_ctx(
        [
          FormSection(
            sectionId: 's1',
            index: 0,
            blocks: [
              FormCanvasBlock(
                blockId: 'cvSvg',
                index: 0,
                target: 'canvas://scene.main',
              ),
            ],
          ),
        ],
        data: {
          'cvSvg': {'format': 'svg', 'svg': svgContent},
        },
      ));
      expect(_html(out), contains(svgContent));
    });

    // Lines 452-455: FormCanvasBlock with PNG data renders img placeholder.
    test('FormCanvasBlock with png data renders img with src', () async {
      final out = await _renderer.render(_ctx(
        [
          FormSection(
            sectionId: 's1',
            index: 0,
            blocks: [
              FormCanvasBlock(
                blockId: 'cvPng',
                index: 0,
                target: 'canvas://scene.main',
                alt: 'Preview',
              ),
            ],
          ),
        ],
        data: {
          'cvPng': {
            'format': 'png',
            'bytes': [0x89, 0x50, 0x4E, 0x47],
          },
        },
      ));
      final html = _html(out);
      expect(html, contains('<img src="canvas://scene.main"'));
      expect(html, contains('alt="Preview"'));
    });

    // Lines 457-458: FormCanvasBlock without resolved data emits placeholder.
    test('FormCanvasBlock without data emits canvas-placeholder div', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormCanvasBlock(
              blockId: 'cvNone',
              index: 0,
              target: 'canvas://unknown.scene',
            ),
          ],
        ),
      ]));
      expect(_html(out), contains('canvas-placeholder'));
      expect(_html(out), contains('canvas://unknown.scene'));
    });

    // Lines 461-462: FormCanvasBlock with caption emits figcaption.
    test('FormCanvasBlock with caption emits figcaption', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormCanvasBlock(
              blockId: 'cvCap',
              index: 0,
              target: 'canvas://scene.main',
              caption: 'Live Preview',
            ),
          ],
        ),
      ]));
      expect(_html(out), contains('<figcaption>Live Preview</figcaption>'));
    });

    // Lines 489-490: conditional else block renders when condition false.
    test('conditional else block is rendered in HTML', () async {
      final out = await _renderer.render(_ctx(
        [
          FormSection(
            sectionId: 's1',
            index: 0,
            blocks: [
              FormConditionalBlock(
                blockId: 'cond',
                index: 0,
                condition: 'flag == "yes"',
                thenBlock: FormTextBlock(
                  blockId: 'then',
                  index: 1,
                  content: 'Yes branch',
                ),
                elseBlock: FormTextBlock(
                  blockId: 'els',
                  index: 2,
                  content: 'No branch',
                ),
              ),
            ],
          ),
        ],
        data: {'flag': 'no'},
      ));
      final html = _html(out);
      expect(html, contains('No branch'));
      expect(html, isNot(contains('Yes branch')));
    });

    // Lines 505, 512-513, 516-517: _writeThemeStyles with bodyFont, headingFont,
    // and named styles when styleSheet is provided.
    test('styleSheet theme fonts and named styles emit CSS rules', () async {
      final out = await _renderer.render(_ctx(
        [
          FormSection(
            sectionId: 's1',
            index: 0,
            blocks: [
              FormTextBlock(blockId: 't', index: 0, content: 'styled'),
            ],
          ),
        ],
        styleSheet: const FormStyleSheet(
          theme: FormTheme(
            bodyFont: 'Arial',
            headingFont: 'Georgia',
          ),
          styles: {
            'highlight': BlockStyle(
              align: FormTextAlign.center,
            ),
          },
        ),
      ));
      final html = _html(out);
      expect(html, contains('font-family: Arial'));
      expect(html, contains('font-family: Georgia'));
      expect(html, contains('.style-highlight'));
    });

    // Lines 530-531: _blockStyleAttr with and without styleRef.
    test('block with styleRef emits class attribute', () async {
      final out = await _renderer.render(_ctx(
        [
          FormSection(
            sectionId: 's1',
            index: 0,
            blocks: [
              // Block with styleRef: true branch (line 530).
              FormTextBlock(
                blockId: 'sr',
                index: 0,
                content: 'Named style',
                style: const {'styleRef': 'myStyle'},
              ),
              // Block without styleRef: false branch (line 531).
              FormTextBlock(
                blockId: 'nr',
                index: 1,
                content: 'No style',
              ),
            ],
          ),
        ],
        styleSheet: const FormStyleSheet(
          styles: {'myStyle': BlockStyle(align: FormTextAlign.left)},
        ),
      ));
      final html = _html(out);
      expect(html, contains('class="style-myStyle"'));
    });

    // Line 547: block with background color emits background-color CSS.
    test('block with background color emits background-color CSS', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormTextBlock(
              blockId: 'bg',
              index: 0,
              content: 'Highlighted block',
              style: const {'background': '#FFFFCC'},
            ),
          ],
        ),
      ]));
      expect(_html(out), contains('background-color: #FFFFCC'));
    });

    // Line 557: border with non-zero radius emits border-radius CSS.
    test('block border with radius emits border-radius CSS', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormTextBlock(
              blockId: 'boxed',
              index: 0,
              content: 'Rounded box',
              style: const {
                'border': {'color': '#333333', 'width': 1.5, 'radius': 6.0},
              },
            ),
          ],
        ),
      ]));
      expect(_html(out), contains('border-radius: 6.0pt'));
    });

    // Lines 581-582: link run emits <a> with style attribute.
    test('inline markdown link emits anchor with href and style', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormTextBlock(
              blockId: 'lnk',
              index: 0,
              format: 'markdown',
              content: 'Visit [our site](https://makemind.dev) now.',
            ),
          ],
        ),
      ]));
      final html = _html(out);
      expect(html, contains('<a href="https://makemind.dev"'));
      expect(html, contains('our site'));
    });

    // Line 586: superscript-only run (no CSS from _runCss) emits bare <sup>.
    test('HTML superscript-only run emits bare sup without span wrapper',
        () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormTextBlock(
              blockId: 'sup',
              index: 0,
              format: 'html',
              content: 'E=mc<sup>2</sup>',
            ),
          ],
        ),
      ]));
      final html = _html(out);
      // The <sup> run has no extra CSS marks, so it emits as bare <sup>2</sup>
      // without a wrapping <span>.
      expect(html, contains('<sup>2</sup>'));
      expect(html, isNot(contains('<span style')));
    });

    // Line 604: highlight in _runCss emits background-color.
    test('highlighted markdown text emits background-color style', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormTextBlock(
              blockId: 'hl',
              index: 0,
              format: 'markdown',
              content: '==key phrase==',
            ),
          ],
        ),
      ]));
      expect(_html(out), contains('background-color'));
    });

    // Line 698: barcode with style.height uses custom height in SVG.
    test('barcode image with style.height uses custom height', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormImageBlock(
              blockId: 'bc',
              index: 0,
              src: 'barcode:ABC123',
              style: const {'height': 80},
            ),
          ],
        ),
      ]));
      final html = _html(out);
      expect(html, contains('height="80.0"'));
    });

    // Lines 746-754: pie chart emits SVG path elements (wedges).
    test('pie chart emits path elements for wedges', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormChartBlock(
              blockId: 'pie',
              index: 0,
              chartType: 'pie',
              data: const [
                {'label': 'A', 'value': 60},
                {'label': 'B', 'value': 40},
              ],
            ),
          ],
        ),
      ]));
      final html = _html(out);
      // Pie chart produces SVG <path> elements for each wedge.
      expect(html, contains('<path d="M'));
    });

    // Lines 757-759: line chart emits SVG polyline elements.
    test('line chart emits polyline elements', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormChartBlock(
              blockId: 'lc',
              index: 0,
              chartType: 'line',
              data: const [
                {
                  'label': 'Revenue',
                  'points': [
                    {'x': 'Jan', 'y': 10},
                    {'x': 'Feb', 'y': 20},
                    {'x': 'Mar', 'y': 15},
                  ],
                },
              ],
            ),
          ],
        ),
      ]));
      expect(_html(out), contains('<polyline points='));
    });
  });
}
