// Coverage tests for UiDslRenderer uncovered lines.
// Target: lib/src/infra/renderer/renderers/ui_dsl_renderer.dart
import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/ui_dsl_renderer.dart';
import 'package:test/test.dart';

const _renderer = UiDslRenderer();

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

RenderContext _ctx(List<FormSection> sections,
    {Map<String, dynamic> data = const {}}) =>
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
    );

Map<String, dynamic> _decode(FormRenderOutput out) =>
    jsonDecode(utf8.decode(out.content as List<int>)) as Map<String, dynamic>;

/// Extract the block children from the first section in the widget tree.
List<Map<String, dynamic>> _firstSectionChildren(Map<String, dynamic> tree) {
  final body = tree['body'] as Map<String, dynamic>;
  final sections =
      (body['children'] as List).cast<Map<String, dynamic>>();
  return (sections.first['children'] as List).cast<Map<String, dynamic>>();
}

void main() {
  group('UiDslRenderer coverage', () {
    // Line 22: supportedTemplateRange getter.
    test('supportedTemplateRange is non-null', () {
      expect(_renderer.supportedTemplateRange, isNotNull);
      expect(_renderer.supportedTemplateRange, contains('1.0.0'));
    });

    // Line 171: table with caption includes caption field.
    test('table with caption includes caption in output', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormTableBlock(
              blockId: 'tbl',
              index: 0,
              style: const {'caption': 'Revenue Table'},
              columns: const [
                FormTableColumn(id: 'c1', title: 'Year', type: 'string'),
              ],
              rows: [FormTableRow(cells: {'c1': '2025'})],
            ),
          ],
        ),
      ]));
      final tree = _decode(out);
      final children = _firstSectionChildren(tree);
      final table = children.first;
      expect(table['type'], 'DataTable');
      // Caption label "Table 1" + caption text combined.
      expect((table['caption'] as String), contains('Table 1'));
      expect((table['caption'] as String), contains('Revenue Table'));
    });

    // Line 185: chart with caption includes caption field.
    test('chart with caption includes caption in output', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormChartBlock(
              blockId: 'ch',
              index: 0,
              chartType: 'bar',
              style: const {'caption': 'Sales Chart'},
              data: const [
                {
                  'label': 'A',
                  'points': [
                    {'x': 'Jan', 'y': 10},
                  ],
                }
              ],
            ),
          ],
        ),
      ]));
      final tree = _decode(out);
      final children = _firstSectionChildren(tree);
      final chart = children.first;
      expect(chart['type'], 'Chart');
      expect((chart['caption'] as String), contains('Figure 1'));
      expect((chart['caption'] as String), contains('Sales Chart'));
    });

    // Lines 200-215: FormCanvasBlock with optional fields.
    test('FormCanvasBlock includes all optional fields in output', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormCanvasBlock(
              blockId: 'cv',
              index: 0,
              target: 'canvas://scene.main',
              mode: 'live',
              format: 'png',
              fallback: 'bitmap',
              viewport: const {'width': 800, 'height': 600},
              caption: 'Scene view',
              alt: 'Interactive scene',
              maxWidth: 640,
              aspectRatio: 1.5,
            ),
          ],
        ),
      ]));
      final tree = _decode(out);
      final children = _firstSectionChildren(tree);
      final canvas = children.first;
      expect(canvas['type'], 'Canvas');
      expect(canvas['target'], 'canvas://scene.main');
      expect(canvas['mode'], 'live');
      expect(canvas['format'], 'png');
      expect(canvas['fallback'], 'bitmap');
      expect(canvas['viewport'], isA<Map<String, dynamic>>());
      expect(canvas['caption'], 'Scene view');
      expect(canvas['alt'], 'Interactive scene');
      expect(canvas['maxWidth'], 640);
      expect(canvas['aspectRatio'], 1.5);
    });

    // Line 200: FormImageBlock with caption emits caption field in output.
    test('FormImageBlock with caption includes caption in output', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormImageBlock(
              blockId: 'img',
              index: 0,
              src: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
              alt: 'Test image',
              style: const {'caption': 'Sample figure'},
            ),
          ],
        ),
      ]));
      final tree = _decode(out);
      final children = _firstSectionChildren(tree);
      final img = children.first;
      expect(img['type'], 'Image');
      // Caption label "Figure 1" + caption text combined.
      expect((img['caption'] as String), contains('Figure 1'));
      expect((img['caption'] as String), contains('Sample figure'));
    });

    // Lines 257-260: _captionText with non-empty caption string.
    // A table with only a kind of 'table' and explicit caption text.
    test('_captionText returns "Table N: caption" for table with caption', () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormTableBlock(
              blockId: 'tb2',
              index: 0,
              // caption is non-empty, so the full "Table 1: caption" path is taken.
              style: const {'caption': 'Key Metrics'},
              columns: const [
                FormTableColumn(id: 'c', title: 'Metric', type: 'string'),
              ],
              rows: [FormTableRow(cells: {'c': 'Revenue'})],
            ),
          ],
        ),
      ]));
      final tree = _decode(out);
      final children = _firstSectionChildren(tree);
      final table = children.first;
      expect(table['caption'], 'Table 1: Key Metrics');
    });
  });
}
