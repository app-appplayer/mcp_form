import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/mcp_form.dart';
import 'package:test/test.dart';

FormDocument _makeDoc({
  String id = 'doc-1',
  String templateId = 'tpl-1',
  String author = 'tester',
  FormDocumentStatus status = FormDocumentStatus.draft,
  int version = 1,
  List<FormSection> sections = const [],
  DateTime? createdAt,
  DateTime? modifiedAt,
}) {
  return FormDocument(
    documentId: id,
    templateId: templateId,
    templateVersion: '1.0.0',
    metadata: FormDocumentMetadata(
      author: author,
      createdAt: createdAt ?? DateTime(2026),
      modifiedAt: modifiedAt,
    ),
    status: status,
    version: version,
    sections: sections,
  );
}

void main() {
  group('DocumentSummary', () {
    test('constructs with required fields', () {
      final summary = DocumentSummary(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        author: 'tester',
        status: FormDocumentStatus.draft,
        version: 1,
        sectionCount: 2,
        blockCount: 5,
        createdAt: DateTime(2026),
      );

      expect(summary.documentId, 'doc-1');
      expect(summary.title, isNull);
      expect(summary.modifiedAt, isNull);
      expect(summary.sectionCount, 2);
      expect(summary.blockCount, 5);
    });

    // TC-074: fromDocument extracts correct fields
    test('fromDocument extracts correct fields', () {
      final doc = _makeDoc(
        id: 'doc-99',
        author: 'admin',
        status: FormDocumentStatus.review,
        version: 3,
        sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormHeadingBlock(
              blockId: 'h1',
              index: 0,
              content: 'Main Title',
              level: 1,
            ),
            FormTextBlock(blockId: 't1', index: 1, content: 'Body text'),
          ]),
          FormSection(sectionId: 's2', index: 1, blocks: [
            FormTextBlock(blockId: 't2', index: 0, content: 'More text'),
          ]),
        ],
        modifiedAt: DateTime(2026, 3, 1),
      );

      final summary = DocumentSummary.fromDocument(doc);

      expect(summary.documentId, 'doc-99');
      expect(summary.templateId, 'tpl-1');
      expect(summary.templateVersion, '1.0.0');
      expect(summary.title, 'Main Title');
      expect(summary.author, 'admin');
      expect(summary.status, FormDocumentStatus.review);
      expect(summary.version, 3);
      expect(summary.sectionCount, 2);
      expect(summary.blockCount, 3);
      expect(summary.modifiedAt, DateTime(2026, 3, 1));
    });

    // TC-075: fromDocument with no HeadingBlock
    test('fromDocument with no heading returns null title', () {
      final doc = _makeDoc(
        sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(blockId: 't1', index: 0, content: 'No heading'),
          ]),
        ],
      );

      final summary = DocumentSummary.fromDocument(doc);
      expect(summary.title, isNull);
    });

    test('fromDocument with level-2 heading returns null title', () {
      final doc = _makeDoc(
        sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormHeadingBlock(
              blockId: 'h',
              index: 0,
              content: 'Sub Heading',
              level: 2,
            ),
          ]),
        ],
      );

      final summary = DocumentSummary.fromDocument(doc);
      expect(summary.title, isNull);
    });

    test('fromDocument with empty document', () {
      final doc = _makeDoc();
      final summary = DocumentSummary.fromDocument(doc);

      expect(summary.sectionCount, 0);
      expect(summary.blockCount, 0);
      expect(summary.title, isNull);
    });

    test('blockCount sums across all sections', () {
      final doc = _makeDoc(
        sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(blockId: 't1', index: 0, content: 'a'),
            FormTextBlock(blockId: 't2', index: 1, content: 'b'),
          ]),
          FormSection(sectionId: 's2', index: 1, blocks: [
            FormTextBlock(blockId: 't3', index: 0, content: 'c'),
          ]),
          FormSection(sectionId: 's3', index: 2, blocks: [
            FormTextBlock(blockId: 't4', index: 0, content: 'd'),
            FormTextBlock(blockId: 't5', index: 1, content: 'e'),
            FormTextBlock(blockId: 't6', index: 2, content: 'f'),
          ]),
        ],
      );

      final summary = DocumentSummary.fromDocument(doc);
      expect(summary.blockCount, 6);
    });
  });
}
