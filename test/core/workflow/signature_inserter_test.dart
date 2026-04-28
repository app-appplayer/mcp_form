import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/mcp_form.dart';
import 'package:test/test.dart';

FormDocument _makeDoc({
  FormDocumentStatus status = FormDocumentStatus.approved,
  List<FormSection> sections = const [],
  Map<String, dynamic> data = const {},
}) {
  return FormDocument(
    documentId: 'doc-1',
    templateId: 'tpl-1',
    templateVersion: '1.0.0',
    metadata: FormDocumentMetadata(
      author: 'tester',
      createdAt: DateTime(2026),
    ),
    status: status,
    sections: sections,
    data: data,
  );
}

void main() {
  final inserter = SignatureInserter();

  group('SignatureInserter - state validation', () {
    test('throws on draft document', () {
      final doc = _makeDoc(status: FormDocumentStatus.draft);

      expect(
        () => inserter.insertArtifact(
          document: doc,
          artifact: const SignatureArtifact(
            type: ArtifactType.signature,
            content: 'sig.png',
            targetPath: '/sections/0/blocks/0',
          ),
        ),
        throwsA(isA<FormError>()),
      );
    });

    test('throws on review document', () {
      final doc = _makeDoc(status: FormDocumentStatus.review);

      expect(
        () => inserter.insertArtifact(
          document: doc,
          artifact: const SignatureArtifact(
            type: ArtifactType.stamp,
            content: 'stamp.png',
            targetPath: '/sections/0/blocks/0',
          ),
        ),
        throwsA(isA<FormError>()),
      );
    });

    test('throws on published document', () {
      final doc = _makeDoc(status: FormDocumentStatus.published);

      expect(
        () => inserter.insertArtifact(
          document: doc,
          artifact: const SignatureArtifact(
            type: ArtifactType.signature,
            content: 'sig.png',
            targetPath: '/sections/0/blocks/0',
          ),
        ),
        throwsA(isA<FormError>()),
      );
    });

    test('error code is workflow.invalid_state', () {
      final doc = _makeDoc(status: FormDocumentStatus.draft);

      try {
        inserter.insertArtifact(
          document: doc,
          artifact: const SignatureArtifact(
            type: ArtifactType.signature,
            content: 'sig.png',
            targetPath: '/sections/0/blocks/0',
          ),
        );
        fail('Expected FormError');
      } on FormError catch (e) {
        expect(e.code, 'workflow.invalid_state');
      }
    });
  });

  group('SignatureInserter - signature/stamp insertion', () {
    test('inserts signature image block at bottom', () {
      final doc = _makeDoc(
        sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(blockId: 'txt', index: 0, content: 'Body'),
          ]),
        ],
      );

      final result = inserter.insertArtifact(
        document: doc,
        artifact: const SignatureArtifact(
          type: ArtifactType.signature,
          content: 'data:image/png;base64,abc123',
          targetPath: '/sections/0',
        ),
      );

      expect(result.sections[0].blocks.length, 2);
      final inserted = result.sections[0].blocks[1] as FormImageBlock;
      expect(inserted.src, 'data:image/png;base64,abc123');
      expect(inserted.alt, 'signature');
    });

    test('inserts stamp image block at top', () {
      final doc = _makeDoc(
        sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(blockId: 'txt', index: 0, content: 'Body'),
          ]),
        ],
      );

      final result = inserter.insertArtifact(
        document: doc,
        artifact: const SignatureArtifact(
          type: ArtifactType.stamp,
          content: 'stamp.png',
          targetPath: '/sections/0',
          position: ArtifactPosition.top,
        ),
      );

      expect(result.sections[0].blocks.length, 2);
      final inserted = result.sections[0].blocks[0] as FormImageBlock;
      expect(inserted.src, 'stamp.png');
      expect(inserted.alt, 'stamp');
    });

    test('preserves document status as approved', () {
      final doc = _makeDoc(
        sections: const [FormSection(sectionId: 's1', index: 0)],
      );

      final result = inserter.insertArtifact(
        document: doc,
        artifact: const SignatureArtifact(
          type: ArtifactType.signature,
          content: 'sig.png',
          targetPath: '/sections/0',
        ),
      );

      expect(result.status, FormDocumentStatus.approved);
    });

    test('does not increment version', () {
      final doc = _makeDoc(
        sections: const [FormSection(sectionId: 's1', index: 0)],
      );

      final result = inserter.insertArtifact(
        document: doc,
        artifact: const SignatureArtifact(
          type: ArtifactType.signature,
          content: 'sig.png',
          targetPath: '/sections/0',
        ),
      );

      expect(result.version, doc.version);
    });

    test('throws for invalid target path', () {
      final doc = _makeDoc(
        sections: const [FormSection(sectionId: 's1', index: 0)],
      );

      expect(
        () => inserter.insertArtifact(
          document: doc,
          artifact: const SignatureArtifact(
            type: ArtifactType.signature,
            content: 'sig.png',
            targetPath: '/invalid/path',
          ),
        ),
        throwsA(isA<FormError>()),
      );
    });

    test('inserts image block at center position', () {
      final doc = _makeDoc(
        sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(blockId: 'txt1', index: 0, content: 'First'),
            FormTextBlock(blockId: 'txt2', index: 1, content: 'Second'),
            FormTextBlock(blockId: 'txt3', index: 2, content: 'Third'),
            FormTextBlock(blockId: 'txt4', index: 3, content: 'Fourth'),
          ]),
        ],
      );

      final result = inserter.insertArtifact(
        document: doc,
        artifact: const SignatureArtifact(
          type: ArtifactType.signature,
          content: 'sig.png',
          targetPath: '/sections/0',
          position: ArtifactPosition.center,
        ),
      );

      // 4 blocks, mid = 4 ~/ 2 = 2, so insert at index 2
      expect(result.sections[0].blocks.length, 5);
      final inserted = result.sections[0].blocks[2] as FormImageBlock;
      expect(inserted.src, 'sig.png');
    });

    test('throws for out-of-range section index', () {
      final doc = _makeDoc(
        sections: const [FormSection(sectionId: 's1', index: 0)],
      );

      expect(
        () => inserter.insertArtifact(
          document: doc,
          artifact: const SignatureArtifact(
            type: ArtifactType.signature,
            content: 'sig.png',
            targetPath: '/sections/5',
          ),
        ),
        throwsA(isA<FormError>()),
      );
    });
  });

  group('SignatureInserter - watermark insertion', () {
    test('inserts watermark into document data', () {
      final doc = _makeDoc();

      final result = inserter.insertArtifact(
        document: doc,
        artifact: const SignatureArtifact(
          type: ArtifactType.watermark,
          content: 'APPROVED',
          targetPath: 'all',
          opacity: 0.15,
          position: ArtifactPosition.center,
        ),
      );

      expect(result.data['watermark'], isNotNull);
      final watermark = result.data['watermark'] as Map<String, dynamic>;
      expect(watermark['text'], 'APPROVED');
      expect(watermark['opacity'], 0.15);
      expect(watermark['position'], 'center');
    });

    test('watermark does not modify sections', () {
      final doc = _makeDoc(
        sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(blockId: 'txt', index: 0, content: 'Body'),
          ]),
        ],
      );

      final result = inserter.insertArtifact(
        document: doc,
        artifact: const SignatureArtifact(
          type: ArtifactType.watermark,
          content: 'DRAFT',
          targetPath: 'all',
        ),
      );

      expect(result.sections[0].blocks.length, 1);
    });
  });
}
