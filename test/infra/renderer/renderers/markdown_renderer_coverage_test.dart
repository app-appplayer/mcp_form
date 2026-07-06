// Coverage tests for MarkdownRenderer uncovered lines.
// Target: lib/src/infra/renderer/renderers/markdown_renderer.dart
import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/markdown_renderer.dart';
import 'package:test/test.dart';

const _renderer = MarkdownRenderer();

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

String _md(FormRenderOutput out) => utf8.decode(out.content as List<int>);

void main() {
  group('MarkdownRenderer coverage', () {
    // Lines 188-189: FormCanvasBlock without caption emits image-link.
    test('FormCanvasBlock without caption emits image link using alt text',
        () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormCanvasBlock(
              blockId: 'cv',
              index: 0,
              target: 'canvas://scene.main',
              alt: 'Main scene',
            ),
          ],
        ),
      ]));
      final md = _md(out);
      // No caption, so only the image link line is emitted.
      expect(md, contains('![Main scene](canvas://scene.main)'));
      expect(md, isNot(contains('*')));
    });

    // Lines 190-191: FormCanvasBlock with caption emits italic caption line.
    test('FormCanvasBlock with caption emits italic caption below image link',
        () async {
      final out = await _renderer.render(_ctx([
        FormSection(
          sectionId: 's1',
          index: 0,
          blocks: [
            FormCanvasBlock(
              blockId: 'cv2',
              index: 0,
              target: 'canvas://dashboard',
              caption: 'Dashboard preview',
            ),
          ],
        ),
      ]));
      final md = _md(out);
      // alt falls back to caption when alt is null.
      expect(md, contains('![Dashboard preview](canvas://dashboard)'));
      // Caption is emitted as italic text on the next line.
      expect(md, contains('*Dashboard preview*'));
    });

    // Lines 213-214: conditional else block is rendered when condition is false.
    test('conditional else block renders when condition is false', () async {
      final out = await _renderer.render(_ctx(
        [
          FormSection(
            sectionId: 's1',
            index: 0,
            blocks: [
              FormConditionalBlock(
                blockId: 'cond',
                index: 0,
                condition: 'status == "active"',
                thenBlock: FormTextBlock(
                  blockId: 'then',
                  index: 1,
                  content: 'Active content',
                ),
                elseBlock: FormTextBlock(
                  blockId: 'els',
                  index: 2,
                  content: 'Inactive content',
                ),
              ),
            ],
          ),
        ],
        // data does not set status to "active", so else branch fires.
        data: {'status': 'inactive'},
      ));
      final md = _md(out);
      expect(md, contains('Inactive content'));
      expect(md, isNot(contains('Active content')));
    });
  });
}
