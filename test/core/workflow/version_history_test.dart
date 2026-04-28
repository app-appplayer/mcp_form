import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/core/workflow/version_history.dart';
import 'package:test/test.dart';

FormDocument _makeDoc({int version = 1}) {
  return FormDocument(
    documentId: 'doc-1',
    templateId: 'tpl-1',
    templateVersion: '1.0.0',
    metadata: FormDocumentMetadata(
      author: 'tester',
      createdAt: DateTime(2026),
    ),
    version: version,
  );
}

void main() {
  group('VersionHistory', () {
    // TC-269: Record version
    test('recordVersion stores entry', () {
      final history = VersionHistory();
      history.recordVersion(
        documentId: 'doc-1',
        version: 1,
        document: _makeDoc(),
      );

      final entries = history.listVersions('doc-1');
      expect(entries.length, 1);
      expect(entries[0].version, 1);
    });

    // TC-270: Get specific version
    test('getVersion retrieves specific version', () {
      final history = VersionHistory();
      history.recordVersion(
        documentId: 'doc-1',
        version: 1,
        document: _makeDoc(version: 1),
      );
      history.recordVersion(
        documentId: 'doc-1',
        version: 2,
        document: _makeDoc(version: 2),
      );

      final entry = history.getVersion('doc-1', 1);
      expect(entry, isNotNull);
      expect(entry!.version, 1);
    });

    // TC-271: List versions descending
    test('listVersions returns descending order', () {
      final history = VersionHistory();
      history.recordVersion(
        documentId: 'doc-1',
        version: 1,
        document: _makeDoc(version: 1),
      );
      history.recordVersion(
        documentId: 'doc-1',
        version: 3,
        document: _makeDoc(version: 3),
      );
      history.recordVersion(
        documentId: 'doc-1',
        version: 2,
        document: _makeDoc(version: 2),
      );

      final entries = history.listVersions('doc-1');
      expect(entries.map((e) => e.version).toList(), [3, 2, 1]);
    });

    // TC-272: Get latest version
    test('getLatestVersion returns highest version', () {
      final history = VersionHistory();
      history.recordVersion(
        documentId: 'doc-1',
        version: 1,
        document: _makeDoc(version: 1),
      );
      history.recordVersion(
        documentId: 'doc-1',
        version: 3,
        document: _makeDoc(version: 3),
      );

      final latest = history.getLatestVersion('doc-1');
      expect(latest!.version, 3);
    });

    test('getVersion returns null for non-existent version', () {
      final history = VersionHistory();
      expect(history.getVersion('doc-1', 99), isNull);
    });

    test('getLatestVersion returns null for unknown document', () {
      final history = VersionHistory();
      expect(history.getLatestVersion('unknown'), isNull);
    });
  });

  group('VersionHistory - compare', () {
    // TC-274: Status change detected
    test('detects status change', () {
      final history = VersionHistory();
      final from = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        status: FormDocumentStatus.draft,
        version: 1,
      );
      final to = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        status: FormDocumentStatus.review,
        version: 2,
      );

      final diff = history.compare(from, to);
      expect(diff.changes.any((c) => c.path == '/status'), isTrue);
    });

    // TC-275: Section added
    test('detects added section', () {
      final history = VersionHistory();
      final from = _makeDoc();
      final to = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
        sections: [const FormSection(sectionId: 'sec-1', index: 0)],
      );

      final diff = history.compare(from, to);
      expect(
        diff.changes.any(
          (c) => c.path == '/sections/0' &&
              c.changeType == DiffChangeType.added,
        ),
        isTrue,
      );
    });

    // TC-279: Identical documents return empty
    test('identical documents produce no changes', () {
      final history = VersionHistory();
      final doc = _makeDoc();
      final diff = history.compare(doc, doc);
      expect(diff.changes, isEmpty);
    });

    // TC-276: Data field changes
    test('detects data field changes', () {
      final history = VersionHistory();
      final from = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        data: {'name': 'Alice'},
      );
      final to = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        data: {'name': 'Bob', 'age': 30},
      );

      final diff = history.compare(from, to);
      expect(
        diff.changes.any(
          (c) => c.path == '/data/name' &&
              c.changeType == DiffChangeType.modified,
        ),
        isTrue,
      );
      expect(
        diff.changes.any(
          (c) => c.path == '/data/age' &&
              c.changeType == DiffChangeType.added,
        ),
        isTrue,
      );
    });

    test('detects metadata author change', () {
      final history = VersionHistory();
      final from = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'alice',
          createdAt: DateTime(2026),
        ),
        version: 1,
      );
      final to = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'bob',
          createdAt: DateTime(2026),
        ),
        version: 2,
      );

      final diff = history.compare(from, to);
      expect(
        diff.changes.any(
          (c) =>
              c.path == '/metadata/author' &&
              c.changeType == DiffChangeType.modified &&
              c.oldValue == 'alice' &&
              c.newValue == 'bob',
        ),
        isTrue,
      );
    });

    test('detects data field removed', () {
      final history = VersionHistory();
      final from = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        data: {'name': 'Alice', 'age': 30},
      );
      final to = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        data: {'name': 'Alice'},
      );

      final diff = history.compare(from, to);
      expect(
        diff.changes.any(
          (c) =>
              c.path == '/data/age' &&
              c.changeType == DiffChangeType.removed &&
              c.oldValue == 30,
        ),
        isTrue,
      );
    });

    test('detects section removed', () {
      final history = VersionHistory();
      final from = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        sections: [
          const FormSection(sectionId: 'sec-1', index: 0),
          const FormSection(sectionId: 'sec-2', index: 1),
        ],
      );
      final to = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        sections: [
          const FormSection(sectionId: 'sec-1', index: 0),
        ],
      );

      final diff = history.compare(from, to);
      expect(
        diff.changes.any(
          (c) =>
              c.path == '/sections/1' &&
              c.changeType == DiffChangeType.removed,
        ),
        isTrue,
      );
    });

    test('detects blocks added within matching sections', () {
      final history = VersionHistory();
      final from = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        sections: [
          const FormSection(sectionId: 'sec-1', index: 0, blocks: []),
        ],
      );
      final to = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        sections: [
          FormSection(
            sectionId: 'sec-1',
            index: 0,
            blocks: [
              FormTextBlock(blockId: 'blk-1', index: 0, content: 'Hello'),
            ],
          ),
        ],
      );

      final diff = history.compare(from, to);
      expect(
        diff.changes.any(
          (c) =>
              c.path == '/sections/0/blocks/0' &&
              c.changeType == DiffChangeType.added,
        ),
        isTrue,
      );
    });

    test('detects blocks removed within matching sections', () {
      final history = VersionHistory();
      final from = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        sections: [
          FormSection(
            sectionId: 'sec-1',
            index: 0,
            blocks: [
              FormTextBlock(blockId: 'blk-1', index: 0, content: 'Hello'),
              FormTextBlock(blockId: 'blk-2', index: 1, content: 'World'),
            ],
          ),
        ],
      );
      final to = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        sections: [
          FormSection(
            sectionId: 'sec-1',
            index: 0,
            blocks: [
              FormTextBlock(blockId: 'blk-1', index: 0, content: 'Hello'),
            ],
          ),
        ],
      );

      final diff = history.compare(from, to);
      expect(
        diff.changes.any(
          (c) =>
              c.path == '/sections/0/blocks/1' &&
              c.changeType == DiffChangeType.removed,
        ),
        isTrue,
      );
    });

    test('detects block content modified within matching sections', () {
      final history = VersionHistory();
      final from = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        sections: [
          FormSection(
            sectionId: 'sec-1',
            index: 0,
            blocks: [
              FormTextBlock(blockId: 'blk-1', index: 0, content: 'Old'),
            ],
          ),
        ],
      );
      final to = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        sections: [
          FormSection(
            sectionId: 'sec-1',
            index: 0,
            blocks: [
              FormTextBlock(blockId: 'blk-1', index: 0, content: 'New'),
            ],
          ),
        ],
      );

      final diff = history.compare(from, to);
      expect(
        diff.changes.any(
          (c) =>
              c.path == '/sections/0/blocks/0' &&
              c.changeType == DiffChangeType.modified,
        ),
        isTrue,
      );
    });

    test('detects data field modified with nested maps', () {
      final history = VersionHistory();
      final from = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        data: {
          'config': {'key': 'old'},
        },
      );
      final to = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        data: {
          'config': {'key': 'new'},
        },
      );

      final diff = history.compare(from, to);
      expect(
        diff.changes.any(
          (c) =>
              c.path == '/data/config' &&
              c.changeType == DiffChangeType.modified,
        ),
        isTrue,
      );
    });

    test('detects data field modified with nested lists', () {
      final history = VersionHistory();
      final from = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        data: {
          'tags': ['a', 'b'],
        },
      );
      final to = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        data: {
          'tags': ['a', 'c'],
        },
      );

      final diff = history.compare(from, to);
      expect(
        diff.changes.any(
          (c) =>
              c.path == '/data/tags' &&
              c.changeType == DiffChangeType.modified,
        ),
        isTrue,
      );
    });

    test('data fields with different length maps are not equal', () {
      final history = VersionHistory();
      final from = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        data: {
          'obj': {'a': 1},
        },
      );
      final to = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        data: {
          'obj': {'a': 1, 'b': 2},
        },
      );

      final diff = history.compare(from, to);
      expect(
        diff.changes.any(
          (c) =>
              c.path == '/data/obj' &&
              c.changeType == DiffChangeType.modified,
        ),
        isTrue,
      );
    });

    test('data fields with different length lists are not equal', () {
      final history = VersionHistory();
      final from = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        data: {
          'items': [1, 2],
        },
      );
      final to = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'a',
          createdAt: DateTime(2026),
        ),
        data: {
          'items': [1, 2, 3],
        },
      );

      final diff = history.compare(from, to);
      expect(
        diff.changes.any(
          (c) =>
              c.path == '/data/items' &&
              c.changeType == DiffChangeType.modified,
        ),
        isTrue,
      );
    });
  });
}
