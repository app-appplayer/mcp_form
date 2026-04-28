import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/core/patch/incremental_builder.dart';
import 'package:test/test.dart';

void main() {
  group('IncrementalBuilder', () {
    // TC-249: Progressive building
    test('addSection adds sections progressively', () {
      final builder = IncrementalBuilder(
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        author: 'tester',
      );

      builder.addSection(
        const FormSection(sectionId: 'sec-1', index: 0, title: 'First'),
      );
      expect(builder.currentDocument.sections.length, 1);
      expect(builder.currentDocument.sections[0].sectionId, 'sec-1');
    });

    // TC-250: Add blocks to section
    test('addBlock adds blocks to existing section', () {
      final builder = IncrementalBuilder(
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        author: 'tester',
      );

      builder.addSection(
        const FormSection(sectionId: 'sec-1', index: 0),
      );
      builder.addBlock(
        sectionIndex: 0,
        block: FormTextBlock(
          blockId: 'txt-1',
          index: 0,
          content: 'Hello',
        ),
      );

      final doc = builder.currentDocument;
      expect(doc.sections[0].blocks.length, 1);
      expect((doc.sections[0].blocks[0] as FormTextBlock).content, 'Hello');
    });

    // TC-251: Build finalizes document
    test('build finalizes document and prevents further adds', () {
      final builder = IncrementalBuilder(
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        author: 'tester',
      );

      builder.addSection(
        const FormSection(sectionId: 'sec-1', index: 0),
      );
      final doc = builder.build();
      expect(doc.templateId, 'tpl-1');
      expect(doc.documentId, startsWith('doc-'));

      expect(
        () => builder.addSection(
          const FormSection(sectionId: 'sec-2', index: 1),
        ),
        throwsStateError,
      );
    });

    test('operationHistory records all operations', () {
      final builder = IncrementalBuilder(
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        author: 'tester',
      );

      builder.addSection(
        const FormSection(sectionId: 'sec-1', index: 0),
      );
      builder.addBlock(
        sectionIndex: 0,
        block: FormTextBlock(
          blockId: 'txt-1',
          index: 0,
          content: 'Hi',
        ),
      );

      expect(builder.operationHistory.length, 2);
      expect(builder.operationHistory[0].op, 'add');
      expect(builder.operationHistory[1].op, 'add');
    });

    test('addBlock with invalid section index throws RangeError', () {
      final builder = IncrementalBuilder(
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        author: 'tester',
      );

      expect(
        () => builder.addBlock(
          sectionIndex: 0,
          block: FormTextBlock(
            blockId: 'txt-1',
            index: 0,
            content: 'Hi',
          ),
        ),
        throwsRangeError,
      );
    });
  });
}
