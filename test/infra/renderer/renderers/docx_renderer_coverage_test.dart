// Coverage tests for DocxRenderer uncovered lines.
// Target: lib/src/infra/renderer/renderers/docx_renderer.dart
import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/docx_renderer.dart';
import 'package:mcp_form/src/style/style_sheet.dart';
import 'package:test/test.dart';

const _renderer = DocxRenderer();

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

String _xml(FormRenderOutput o) => utf8.decode(o.content as List<int>);

void main() {
  group('DocxRenderer coverage', () {
    // Line 34: supportedTemplateRange getter.
    test('supportedTemplateRange is non-null', () {
      expect(_renderer.supportedTemplateRange, isNotNull);
      expect(_renderer.supportedTemplateRange, contains('1.0.0'));
    });

    // Lines 72-73: logo from styleSheet theme.
    test('logo from styleSheet emits placeholder paragraph', () async {
      final out = await _renderer.render(_ctx(
        [
          FormSection(
            sectionId: 's1',
            index: 0,
            blocks: [FormTextBlock(blockId: 't', index: 0, content: 'body')],
          ),
        ],
        styleSheet: const FormStyleSheet(
          theme: FormTheme(logo: 'company-logo.png'),
        ),
      ));
      expect(_xml(out), contains('[Logo: company-logo.png]'));
    });

    // Lines 87-90: footnotes emitted as endnotes section.
    test('footnotes in text are collected and emitted as endnotes', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormTextBlock(
              blockId: 't',
              index: 0,
              content: 'See note[fn:important detail] here.',
            ),
          ],
        ),
      ]));
      final xml = _xml(out);
      expect(xml, contains('Notes'));
      expect(xml, contains('1. important detail'));
    });

    // Line 274: math text block emits italic placeholder.
    test('math text block emits content as italic paragraph', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormTextBlock(
              blockId: 'm',
              index: 0,
              content: 'E = mc^2',
              style: const {'math': true},
            ),
          ],
        ),
      ]));
      expect(_xml(out), contains('E = mc^2'));
    });

    // Lines 278-285: toc text block emits heading entries.
    test('toc text block emits headings from numbering', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormHeadingBlock(
              blockId: 'h1',
              index: 0,
              content: 'Introduction',
              level: 1,
              numbering: true,
            ),
            FormTextBlock(
              blockId: 'toc',
              index: 1,
              content: 'Contents',
              style: const {'toc': true},
            ),
          ],
        ),
      ]));
      final xml = _xml(out);
      // TOC title and first heading entry.
      expect(xml, contains('Contents'));
      expect(xml, contains('Introduction'));
    });

    // Lines 303, 352-355: table with caption triggers _writeCaption.
    test('table with caption emits caption paragraph after table', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormTableBlock(
              blockId: 'tbl',
              index: 0,
              style: const {'caption': 'Annual Revenue'},
              columns: const [
                FormTableColumn(id: 'c1', title: 'Year', type: 'string'),
              ],
              rows: [
                FormTableRow(cells: {'c1': '2025'}),
              ],
            ),
          ],
        ),
      ]));
      final xml = _xml(out);
      // Caption label ("Table 1") and the caption text.
      expect(xml, contains('Table 1'));
      expect(xml, contains('Annual Revenue'));
    });

    // Lines 319, 516-537: FormCanvasBlock renders target reference.
    test('FormCanvasBlock emits label and target reference', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormCanvasBlock(
              blockId: 'cv',
              index: 0,
              target: 'canvas://scene.main',
              caption: 'Scene preview',
              alt: 'Main scene',
            ),
          ],
        ),
      ]));
      final xml = _xml(out);
      expect(xml, contains('[Canvas: Scene preview]'));
      expect(xml, contains('Target: canvas://scene.main'));
    });

    // Lines 334-335: conditional block with else branch.
    test('conditional else block is rendered when condition is false', () async {
      final out = await _renderer.render(_ctx(
        [
          FormSection(
            sectionId: 's1',
            index: 0,
            blocks: [
              FormConditionalBlock(
                blockId: 'cond',
                index: 0,
                condition: 'choice == "yes"',
                thenBlock: FormTextBlock(
                  blockId: 'then',
                  index: 1,
                  content: 'Condition true',
                ),
                elseBlock: FormTextBlock(
                  blockId: 'els',
                  index: 2,
                  content: 'Condition false',
                ),
              ),
            ],
          ),
        ],
        // data does NOT set choice to "yes", so else branch fires.
        data: {'choice': 'no'},
      ));
      expect(_xml(out), contains('Condition false'));
    });

    // Lines 310-312: image with caption emits caption paragraph.
    test('image with caption emits Figure label', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormImageBlock(
              blockId: 'img',
              index: 0,
              src: 'chart.png',
              alt: 'A chart',
              style: const {'caption': 'Q1 Results'},
            ),
          ],
        ),
      ]));
      final xml = _xml(out);
      expect(xml, contains('Figure 1'));
      expect(xml, contains('Q1 Results'));
    });
  });
}
