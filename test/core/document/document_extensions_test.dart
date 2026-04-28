import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/mcp_form.dart';
import 'package:test/test.dart';

/// Helper to create a minimal FormDocument for testing.
FormDocument _makeDocument({
  String documentId = 'doc-001',
  FormDocumentStatus status = FormDocumentStatus.draft,
  int version = 1,
  List<FormSection> sections = const [],
  Map<String, dynamic> data = const {},
}) {
  final now = DateTime(2025, 1, 1);
  return FormDocument(
    documentId: documentId,
    templateId: 'tpl-001',
    templateVersion: '1.0.0',
    metadata: FormDocumentMetadata(
      author: 'tester',
      createdAt: now,
      modifiedAt: now,
      engineVersion: '1.0.0',
    ),
    status: status,
    version: version,
    sections: sections,
    data: data,
  );
}

void main() {
  // ---- DocumentVersioning ----
  group('DocumentVersioning', () {
    test('incrementVersion increments version by 1', () {
      final doc = _makeDocument(version: 3);
      final updated = doc.incrementVersion();
      expect(updated.version, 4);
    });

    test('incrementVersion updates modifiedAt timestamp', () {
      final doc = _makeDocument();
      final before = DateTime.now();
      final updated = doc.incrementVersion();

      expect(updated.metadata.modifiedAt, isNotNull);
      expect(
        updated.metadata.modifiedAt!.isAfter(
          before.subtract(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });

    test('incrementVersion preserves all other fields', () {
      final doc = _makeDocument(
        documentId: 'doc-preserve',
        status: FormDocumentStatus.draft,
        version: 5,
        sections: [const FormSection(sectionId: 'sec-1', index: 0)],
        data: {'key': 'value'},
      );
      final updated = doc.incrementVersion();

      expect(updated.documentId, doc.documentId);
      expect(updated.templateId, doc.templateId);
      expect(updated.templateVersion, doc.templateVersion);
      expect(updated.status, doc.status);
      expect(updated.metadata.author, doc.metadata.author);
      expect(updated.metadata.createdAt, doc.metadata.createdAt);
      expect(updated.sections.length, 1);
      expect(updated.sections[0].sectionId, 'sec-1');
      expect(updated.data['key'], 'value');
    });
  });

  // ---- DocumentCloning ----
  group('DocumentCloning', () {
    test('cloneAsNewDocument creates document with new ID', () {
      final doc = _makeDocument(documentId: 'doc-original');
      final cloned = doc.cloneAsNewDocument();

      expect(cloned.documentId, isNot(doc.documentId));
      expect(cloned.documentId, startsWith('doc-'));
    });

    test('cloneAsNewDocument uses provided custom ID', () {
      final doc = _makeDocument();
      final cloned = doc.cloneAsNewDocument(newDocumentId: 'custom');

      expect(cloned.documentId, 'custom');
    });

    test('cloneAsNewDocument resets status to draft', () {
      final doc = _makeDocument(status: FormDocumentStatus.approved);
      final cloned = doc.cloneAsNewDocument();

      expect(cloned.status, FormDocumentStatus.draft);
    });

    test('cloneAsNewDocument resets version to 1', () {
      final doc = _makeDocument(version: 10);
      final cloned = doc.cloneAsNewDocument();

      expect(cloned.version, 1);
    });

    test('cloneAsNewDocument preserves sections and data', () {
      final doc = _makeDocument(
        sections: [const FormSection(sectionId: 'sec-a', index: 0)],
        data: {'foo': 'bar'},
      );
      final cloned = doc.cloneAsNewDocument();

      expect(cloned.sections.length, 1);
      expect(cloned.sections[0].sectionId, 'sec-a');
      expect(cloned.data['foo'], 'bar');
    });
  });

  // ---- FormDocumentStatusExtension ----
  group('FormDocumentStatusExtension', () {
    group('isEditable', () {
      test('draft is editable', () {
        expect(FormDocumentStatus.draft.isEditable, isTrue);
      });

      test('review is not editable', () {
        expect(FormDocumentStatus.review.isEditable, isFalse);
      });
    });

    group('isExportable', () {
      test('approved is exportable', () {
        expect(FormDocumentStatus.approved.isExportable, isTrue);
      });

      test('draft is not exportable', () {
        expect(FormDocumentStatus.draft.isExportable, isFalse);
      });
    });

    group('isTerminal', () {
      test('published is terminal', () {
        expect(FormDocumentStatus.published.isTerminal, isTrue);
      });

      test('approved is not terminal', () {
        expect(FormDocumentStatus.approved.isTerminal, isFalse);
      });
    });

    group('displayName', () {
      test('draft displays as Draft', () {
        expect(FormDocumentStatus.draft.displayName, 'Draft');
      });

      test('review displays as Under Review', () {
        expect(FormDocumentStatus.review.displayName, 'Under Review');
      });

      test('approved displays as Approved', () {
        expect(FormDocumentStatus.approved.displayName, 'Approved');
      });

      test('published displays as Published', () {
        expect(FormDocumentStatus.published.displayName, 'Published');
      });
    });
  });

  // ---- Block Path Utilities (FR-DOM-002) ----
  group('Block path utilities', () {
    test('blockPath returns correct path for existing block', () {
      final doc = _makeDocument(
        sections: [
          FormSection(
            sectionId: 'sec-0',
            index: 0,
            blocks: [
              FormTextBlock(blockId: 'blk-a', index: 0, content: 'hello'),
              FormTextBlock(blockId: 'blk-b', index: 1, content: 'world'),
            ],
          ),
          FormSection(
            sectionId: 'sec-1',
            index: 1,
            blocks: [
              FormTextBlock(blockId: 'blk-c', index: 0, content: 'foo'),
            ],
          ),
        ],
      );

      expect(blockPath(doc, 'blk-a'), '/sections/0/blocks/0');
      expect(blockPath(doc, 'blk-b'), '/sections/0/blocks/1');
      expect(blockPath(doc, 'blk-c'), '/sections/1/blocks/0');
    });

    test('blockPath returns null for non-existent blockId', () {
      final doc = _makeDocument(
        sections: [
          FormSection(
            sectionId: 'sec-0',
            index: 0,
            blocks: [
              FormTextBlock(blockId: 'blk-a', index: 0, content: 'hello'),
            ],
          ),
        ],
      );

      expect(blockPath(doc, 'nonexistent'), isNull);
    });

    test('allBlockPaths returns all block paths', () {
      final doc = _makeDocument(
        sections: [
          FormSection(
            sectionId: 'sec-0',
            index: 0,
            blocks: [
              FormTextBlock(blockId: 'blk-a', index: 0, content: 'hello'),
              FormTextBlock(blockId: 'blk-b', index: 1, content: 'world'),
            ],
          ),
          FormSection(
            sectionId: 'sec-1',
            index: 1,
            blocks: [
              FormTextBlock(blockId: 'blk-c', index: 0, content: 'foo'),
            ],
          ),
        ],
      );

      final paths = allBlockPaths(doc);
      expect(paths, {
        'blk-a': '/sections/0/blocks/0',
        'blk-b': '/sections/0/blocks/1',
        'blk-c': '/sections/1/blocks/0',
      });
    });
  });

  // ---- Transition Utilities ----
  group('Transition utilities', () {
    group('isValidTransition', () {
      test('draft to review is valid', () {
        expect(
          isValidTransition(FormDocumentStatus.draft, FormDocumentStatus.review),
          isTrue,
        );
      });

      test('draft to published is invalid', () {
        expect(
          isValidTransition(
            FormDocumentStatus.draft,
            FormDocumentStatus.published,
          ),
          isFalse,
        );
      });

      test('review to approved is valid', () {
        expect(
          isValidTransition(
            FormDocumentStatus.review,
            FormDocumentStatus.approved,
          ),
          isTrue,
        );
      });

      test('review to draft is valid', () {
        expect(
          isValidTransition(FormDocumentStatus.review, FormDocumentStatus.draft),
          isTrue,
        );
      });
    });

    group('validTransitionsFrom', () {
      test('draft can transition to review', () {
        expect(
          validTransitionsFrom(FormDocumentStatus.draft),
          equals({FormDocumentStatus.review}),
        );
      });

      test('published has no valid transitions', () {
        expect(
          validTransitionsFrom(FormDocumentStatus.published),
          isEmpty,
        );
      });

      test('review can transition to approved and draft', () {
        final transitions = validTransitionsFrom(FormDocumentStatus.review);
        expect(transitions.length, 2);
        expect(
          transitions.containsAll([
            FormDocumentStatus.approved,
            FormDocumentStatus.draft,
          ]),
          isTrue,
        );
      });
    });

    group('checkModificationAllowed', () {
      test('returns null for draft document', () {
        final doc = _makeDocument(status: FormDocumentStatus.draft);
        expect(checkModificationAllowed(doc), isNull);
      });

      test('returns FormError for review document', () {
        final doc = _makeDocument(status: FormDocumentStatus.review);
        final error = checkModificationAllowed(doc);

        expect(error, isNotNull);
        expect(error, isA<FormError>());
        expect(error!.code, 'document.invalid_state');
      });
    });
  });
}
