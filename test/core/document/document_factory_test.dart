import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/core/document/document_factory.dart';
import 'package:test/test.dart';

FormTemplate _makeTemplate({
  List<FormSection> defaultSections = const [],
  FormSchema? schema,
}) {
  return FormTemplate(
    templateId: 'tpl-001',
    version: '1.0.0',
    name: 'Test Template',
    schema: schema ?? const FormSchema(),
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
    defaultSections: defaultSections,
  );
}

void main() {
  const factory = DocumentFactory();

  group('DocumentFactory', () {
    // TC-063: Create document from template with data
    test('creates document from template with data', () {
      final template = _makeTemplate(
        defaultSections: [
          const FormSection(sectionId: 'sec-1', index: 0, title: 'Section 1'),
        ],
      );
      final doc = factory.createFromTemplate(
        template: template,
        data: {'name': 'Alice', 'age': 30},
        author: 'tester',
      );

      expect(doc.templateId, 'tpl-001');
      expect(doc.templateVersion, '1.0.0');
      expect(doc.data['name'], 'Alice');
      expect(doc.data['age'], 30);
      expect(doc.metadata.author, 'tester');
      expect(doc.sections.length, 1);
      expect(doc.sections[0].sectionId, 'sec-1');
    });

    // TC-064: Create with custom documentId
    test('uses custom documentId when provided', () {
      final template = _makeTemplate();
      final doc = factory.createFromTemplate(
        template: template,
        documentId: 'custom-id-123',
      );

      expect(doc.documentId, 'custom-id-123');
    });

    // TC-065: Create with empty initialData
    test('creates document with empty initial data', () {
      final template = _makeTemplate();
      final doc = factory.createFromTemplate(template: template);

      expect(doc.data, isEmpty);
    });

    // TC-066: New document status is draft
    test('new document starts as draft with version 1', () {
      final template = _makeTemplate();
      final doc = factory.createFromTemplate(template: template);

      expect(doc.status, FormDocumentStatus.draft);
      expect(doc.version, 1);
    });

    test('auto-generates documentId when not provided', () {
      final template = _makeTemplate();
      final doc = factory.createFromTemplate(template: template);

      expect(doc.documentId, startsWith('doc-'));
    });

    test('sets default author to system when not provided', () {
      final template = _makeTemplate();
      final doc = factory.createFromTemplate(template: template);

      expect(doc.metadata.author, 'system');
    });

    test('creates default main section when template has no sections', () {
      final template = _makeTemplate(defaultSections: []);
      final doc = factory.createFromTemplate(template: template);

      expect(doc.sections.length, 1);
      expect(doc.sections[0].sectionId, 'main');
      expect(doc.sections[0].index, 0);
    });

    test('copies template sections when available', () {
      final template = _makeTemplate(
        defaultSections: [
          const FormSection(sectionId: 'a', index: 0),
          const FormSection(sectionId: 'b', index: 1),
        ],
      );
      final doc = factory.createFromTemplate(template: template);

      expect(doc.sections.length, 2);
      expect(doc.sections[0].sectionId, 'a');
      expect(doc.sections[1].sectionId, 'b');
    });

    test('metadata has createdAt set', () {
      final before = DateTime.now();
      final template = _makeTemplate();
      final doc = factory.createFromTemplate(template: template);

      expect(doc.metadata.createdAt.isAfter(before.subtract(
        const Duration(seconds: 1),
      )), isTrue);
    });

    // Coverage: _buildBlocksForSection with FormFieldBlock matching data key
    test('applies initial data to matching FormFieldBlock fields', () {
      final template = _makeTemplate(
        defaultSections: [
          FormSection(sectionId: 'sec-1', index: 0, blocks: [
            FormFieldBlock(
              blockId: 'blk-1',
              index: 0,
              fieldName: 'name',
              fieldType: 'text',
              placeholder: 'Enter name',
            ),
            FormFieldBlock(
              blockId: 'blk-2',
              index: 1,
              fieldName: 'email',
              fieldType: 'text',
            ),
          ]),
        ],
      );

      final doc = factory.createFromTemplate(
        template: template,
        data: {'name': 'Alice'},
      );

      // The section should have both blocks
      expect(doc.sections.length, 1);
      expect(doc.sections[0].blocks.length, 2);

      // The matching block should be reconstructed as FormFieldBlock
      final block0 = doc.sections[0].blocks[0];
      expect(block0, isA<FormFieldBlock>());
      final fieldBlock = block0 as FormFieldBlock;
      expect(fieldBlock.fieldName, 'name');
      expect(fieldBlock.blockId, 'blk-1');
      expect(fieldBlock.placeholder, 'Enter name');

      // The non-matching block should pass through unchanged
      final block1 = doc.sections[0].blocks[1];
      expect(block1, isA<FormFieldBlock>());
      expect((block1 as FormFieldBlock).fieldName, 'email');
    });
  });
}
