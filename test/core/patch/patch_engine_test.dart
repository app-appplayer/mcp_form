import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/core/patch/patch_engine.dart';
import 'package:test/test.dart';

FormDocument _makeDoc([Map<String, dynamic> data = const {}]) {
  return FormDocument(
    documentId: 'doc-1',
    templateId: 'tpl-1',
    templateVersion: '1.0.0',
    metadata: FormDocumentMetadata(
      author: 'tester',
      createdAt: DateTime(2026),
    ),
    data: data,
  );
}

void main() {
  const engine = PatchEngine();

  group('PatchEngine - add', () {
    // TC-222: Add new field
    test('add operation inserts value', () {
      final result = engine.apply(
        document: _makeDoc(),
        operations: [
          FormPatchOperation(op: 'add', path: '/data/name', value: 'Alice'),
        ],
      );
      expect(result.isSuccess, isTrue);
      expect(result.document!.data['name'], 'Alice');
      expect(result.affectedPaths, contains('/data/name'));
      expect(result.newVersion, 2);
    });

    // TC-223: Add without value fails validation
    test('add without value fails', () {
      final result = engine.apply(
        document: _makeDoc(),
        operations: [
          FormPatchOperation(op: 'add', path: '/data/name'),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.invalid_value');
    });
  });

  group('PatchEngine - remove', () {
    // TC-224: Remove existing field
    test('remove operation removes value', () {
      final result = engine.apply(
        document: _makeDoc({'name': 'Alice'}),
        operations: [
          FormPatchOperation(op: 'remove', path: '/data/name'),
        ],
      );
      expect(result.isSuccess, isTrue);
      expect(result.document!.data.containsKey('name'), isFalse);
    });

    // TC-225: Remove non-existent field fails
    test('remove non-existent path fails', () {
      final result = engine.apply(
        document: _makeDoc(),
        operations: [
          FormPatchOperation(op: 'remove', path: '/data/missing'),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.invalid_path');
    });
  });

  group('PatchEngine - replace', () {
    // TC-226: Replace existing field
    test('replace operation updates value', () {
      final result = engine.apply(
        document: _makeDoc({'name': 'Alice'}),
        operations: [
          FormPatchOperation(
            op: 'replace',
            path: '/data/name',
            value: 'Bob',
          ),
        ],
      );
      expect(result.isSuccess, isTrue);
      expect(result.document!.data['name'], 'Bob');
    });

    // TC-227: Replace non-existent fails
    test('replace non-existent path fails', () {
      final result = engine.apply(
        document: _makeDoc(),
        operations: [
          FormPatchOperation(
            op: 'replace',
            path: '/data/missing',
            value: 'x',
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.invalid_path');
    });

    // TC-228: Replace without value fails
    test('replace without value fails validation', () {
      final result = engine.apply(
        document: _makeDoc({'name': 'Alice'}),
        operations: [
          FormPatchOperation(op: 'replace', path: '/data/name'),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.invalid_value');
    });
  });

  group('PatchEngine - move', () {
    // TC-229: Move field
    test('move operation relocates value', () {
      final result = engine.apply(
        document: _makeDoc({'firstName': 'Alice'}),
        operations: [
          FormPatchOperation(
            op: 'move',
            path: '/data/name',
            from: '/data/firstName',
          ),
        ],
      );
      expect(result.isSuccess, isTrue);
      expect(result.document!.data['name'], 'Alice');
      expect(result.document!.data.containsKey('firstName'), isFalse);
      expect(result.affectedPaths, contains('/data/firstName'));
      expect(result.affectedPaths, contains('/data/name'));
    });

    // TC-230: Move from non-existent fails
    test('move from non-existent path fails', () {
      final result = engine.apply(
        document: _makeDoc(),
        operations: [
          FormPatchOperation(
            op: 'move',
            path: '/data/name',
            from: '/data/missing',
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.invalid_from');
    });
  });

  group('PatchEngine - copy', () {
    // TC-231: Copy field
    test('copy operation duplicates value', () {
      final result = engine.apply(
        document: _makeDoc({'name': 'Alice'}),
        operations: [
          FormPatchOperation(
            op: 'copy',
            path: '/data/nameCopy',
            from: '/data/name',
          ),
        ],
      );
      expect(result.isSuccess, isTrue);
      expect(result.document!.data['nameCopy'], 'Alice');
      expect(result.document!.data['name'], 'Alice');
    });

    // TC-232: Copy from non-existent fails
    test('copy from non-existent path fails', () {
      final result = engine.apply(
        document: _makeDoc(),
        operations: [
          FormPatchOperation(
            op: 'copy',
            path: '/data/x',
            from: '/data/missing',
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.invalid_from');
    });
  });

  group('PatchEngine - test', () {
    // TC-233: Test passes
    test('test operation passes when values match', () {
      final result = engine.apply(
        document: _makeDoc({'name': 'Alice'}),
        operations: [
          FormPatchOperation(
            op: 'test',
            path: '/data/name',
            value: 'Alice',
          ),
        ],
      );
      expect(result.isSuccess, isTrue);
    });

    // TC-234: Test fails
    test('test operation fails when values differ', () {
      final result = engine.apply(
        document: _makeDoc({'name': 'Alice'}),
        operations: [
          FormPatchOperation(
            op: 'test',
            path: '/data/name',
            value: 'Bob',
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.test_failed');
    });
  });

  group('PatchEngine - atomicity', () {
    // TC-235: Multi-op success
    test('multiple operations all succeed', () {
      final result = engine.apply(
        document: _makeDoc({'a': 1}),
        operations: [
          FormPatchOperation(op: 'add', path: '/data/b', value: 2),
          FormPatchOperation(op: 'replace', path: '/data/a', value: 10),
        ],
      );
      expect(result.isSuccess, isTrue);
      expect(result.document!.data['a'], 10);
      expect(result.document!.data['b'], 2);
    });

    // TC-236: Failure mid-sequence rolls back
    test('failure mid-sequence rolls back all changes', () {
      final result = engine.apply(
        document: _makeDoc({'a': 1}),
        operations: [
          FormPatchOperation(op: 'add', path: '/data/b', value: 2),
          FormPatchOperation(
            op: 'replace',
            path: '/data/nonexistent',
            value: 3,
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.document, isNull);
    });
  });

  group('PatchEngine - applySingle', () {
    // TC-238: Single operation
    test('applies single operation', () {
      final result = engine.applySingle(
        document: _makeDoc(),
        operation: FormPatchOperation(
          op: 'add',
          path: '/data/x',
          value: 42,
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(result.document!.data['x'], 42);
    });
  });

  group('PatchEngine - read-only paths', () {
    // TC-243: Patch targeting documentId rejected
    test('rejects patch to documentId', () {
      final result = engine.apply(
        document: _makeDoc(),
        operations: [
          FormPatchOperation(
            op: 'replace',
            path: '/documentId',
            value: 'new-id',
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.invalid_path');
    });

    // TC-244: Patch targeting createdAt rejected
    test('rejects patch to createdAt', () {
      final result = engine.apply(
        document: _makeDoc(),
        operations: [
          FormPatchOperation(
            op: 'replace',
            path: '/metadata/createdAt',
            value: '2025-01-01',
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.invalid_path');
    });
  });

  group('PatchEngine - validateOperations', () {
    // TC-240: Structural validation
    test('detects invalid operations structurally', () {
      final errors = engine.validateOperations(
        document: _makeDoc(),
        operations: [
          FormPatchOperation(op: 'add', path: '/data/x'),
          FormPatchOperation(op: 'move', path: '/data/y'),
        ],
      );
      expect(errors.length, 2);
      expect(errors[0].code, 'patch.invalid_value');
      expect(errors[1].code, 'patch.invalid_from');
    });
  });

  group('PatchEngine - version increment', () {
    test('increments version on successful patch', () {
      final doc = _makeDoc({'x': 1});
      expect(doc.version, 1);

      final result = engine.apply(
        document: doc,
        operations: [
          FormPatchOperation(op: 'replace', path: '/data/x', value: 2),
        ],
      );
      expect(result.newVersion, 2);
      expect(result.document!.version, 2);
    });
  });

  group('PatchEngine - unknown operation', () {
    test('validateOperations rejects unknown op', () {
      final errors = engine.validateOperations(
        document: _makeDoc(),
        operations: [
          FormPatchOperation(op: 'invalid_op', path: '/data/x', value: 1),
        ],
      );
      expect(errors.length, 1);
      expect(errors[0].code, 'patch.unknown_operation');
      expect(errors[0].path, '/data/x');
      expect(errors[0].operationIndex, 0);
    });
  });

  group('PatchEngine - bindings and validationIssues preservation', () {
    test('preserves bindings through patch', () {
      final doc = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
        data: {'x': 1},
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/x',
            dataPath: '/source/x',
            source: FormDataSourceType.userInput,
          ),
        ],
      );

      final result = engine.apply(
        document: doc,
        operations: [
          FormPatchOperation(op: 'replace', path: '/data/x', value: 2),
        ],
      );
      expect(result.isSuccess, isTrue);
      expect(result.document!.bindings, isNotNull);
      expect(result.document!.bindings!.length, 1);
      expect(result.document!.bindings![0].bindingId, 'b1');
    });

    test('preserves validationIssues through patch', () {
      final doc = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
        data: {'x': 1},
        validationIssues: [
          FormValidationIssue(
            code: 'required',
            message: 'Field is required',
            path: '/data/y',
          ),
        ],
      );

      final result = engine.apply(
        document: doc,
        operations: [
          FormPatchOperation(op: 'replace', path: '/data/x', value: 2),
        ],
      );
      expect(result.isSuccess, isTrue);
      expect(result.document!.validationIssues, isNotNull);
      expect(result.document!.validationIssues!.length, 1);
      expect(result.document!.validationIssues![0].code, 'required');
    });
  });

  group('PatchEngine - section and array operations', () {
    test('add to array with append token "-"', () {
      final doc = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
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

      final result = engine.apply(
        document: doc,
        operations: [
          FormPatchOperation(
            op: 'add',
            path: '/sections/0/blocks/-',
            value: {
              'type': 'text',
              'blockId': 'blk-2',
              'index': 1,
              'content': 'World',
            },
          ),
        ],
      );
      expect(result.isSuccess, isTrue);
      expect(result.document!.sections[0].blocks.length, 2);
    });

    test('add to array with numeric index inserts at position', () {
      final doc = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
        sections: [
          FormSection(
            sectionId: 'sec-1',
            index: 0,
            blocks: [
              FormTextBlock(blockId: 'blk-1', index: 0, content: 'First'),
              FormTextBlock(blockId: 'blk-2', index: 1, content: 'Third'),
            ],
          ),
        ],
      );

      final result = engine.apply(
        document: doc,
        operations: [
          FormPatchOperation(
            op: 'add',
            path: '/sections/0/blocks/1',
            value: {
              'type': 'text',
              'blockId': 'blk-mid',
              'index': 1,
              'content': 'Second',
            },
          ),
        ],
      );
      expect(result.isSuccess, isTrue);
      expect(result.document!.sections[0].blocks.length, 3);
    });

    test('add to array with invalid index fails', () {
      final doc = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
        sections: [
          const FormSection(sectionId: 'sec-1', index: 0),
        ],
      );

      final result = engine.apply(
        document: doc,
        operations: [
          FormPatchOperation(
            op: 'add',
            path: '/sections/0/blocks/999',
            value: {'type': 'text', 'blockId': 'x', 'index': 0},
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.invalid_path');
    });

    test('add to array with non-numeric key fails', () {
      final doc = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
        sections: [
          const FormSection(sectionId: 'sec-1', index: 0),
        ],
      );

      final result = engine.apply(
        document: doc,
        operations: [
          FormPatchOperation(
            op: 'add',
            path: '/sections/0/blocks/abc',
            value: {'type': 'text', 'blockId': 'x', 'index': 0},
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.invalid_path');
    });

    test('remove from array by index', () {
      final doc = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
        sections: [
          FormSection(
            sectionId: 'sec-1',
            index: 0,
            blocks: [
              FormTextBlock(blockId: 'blk-1', index: 0, content: 'A'),
              FormTextBlock(blockId: 'blk-2', index: 1, content: 'B'),
            ],
          ),
        ],
      );

      final result = engine.apply(
        document: doc,
        operations: [
          FormPatchOperation(op: 'remove', path: '/sections/0/blocks/0'),
        ],
      );
      expect(result.isSuccess, isTrue);
      expect(result.document!.sections[0].blocks.length, 1);
    });

    test('remove from array with invalid index fails', () {
      final doc = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
        sections: [
          FormSection(
            sectionId: 'sec-1',
            index: 0,
            blocks: [
              FormTextBlock(blockId: 'blk-1', index: 0, content: 'A'),
            ],
          ),
        ],
      );

      final result = engine.apply(
        document: doc,
        operations: [
          FormPatchOperation(op: 'remove', path: '/sections/0/blocks/99'),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.invalid_path');
    });

    test('replace in array by index', () {
      final doc = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
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

      final result = engine.apply(
        document: doc,
        operations: [
          FormPatchOperation(
            op: 'replace',
            path: '/sections/0/blocks/0',
            value: {
              'type': 'text',
              'blockId': 'blk-1',
              'index': 0,
              'content': 'New',
            },
          ),
        ],
      );
      expect(result.isSuccess, isTrue);
    });

    test('replace in array with invalid index fails', () {
      final doc = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
        sections: [
          FormSection(
            sectionId: 'sec-1',
            index: 0,
            blocks: [
              FormTextBlock(blockId: 'blk-1', index: 0, content: 'A'),
            ],
          ),
        ],
      );

      final result = engine.apply(
        document: doc,
        operations: [
          FormPatchOperation(
            op: 'replace',
            path: '/sections/0/blocks/99',
            value: {'type': 'text', 'blockId': 'x', 'index': 0},
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.invalid_path');
    });
  });

  group('PatchEngine - unresolvable paths', () {
    test('add to unresolvable parent path fails', () {
      final result = engine.apply(
        document: _makeDoc(),
        operations: [
          FormPatchOperation(
            op: 'add',
            path: '/nonexistent/deep/path',
            value: 1,
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.invalid_path');
    });

    test('remove from unresolvable parent path fails', () {
      final result = engine.apply(
        document: _makeDoc(),
        operations: [
          FormPatchOperation(op: 'remove', path: '/nonexistent/deep/path'),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.invalid_path');
    });

    test('replace at unresolvable parent path fails', () {
      final result = engine.apply(
        document: _makeDoc(),
        operations: [
          FormPatchOperation(
            op: 'replace',
            path: '/nonexistent/deep/path',
            value: 1,
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.invalid_path');
    });
  });

  group('PatchEngine - test operation edge cases', () {
    test('test on non-existent path fails', () {
      final result = engine.apply(
        document: _makeDoc(),
        operations: [
          FormPatchOperation(
            op: 'test',
            path: '/data/nonexistent',
            value: 'x',
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.invalid_path');
    });

    test('test with matching map values passes', () {
      final result = engine.apply(
        document: _makeDoc({'nested': {'a': 1, 'b': 2}}),
        operations: [
          FormPatchOperation(
            op: 'test',
            path: '/data/nested',
            value: {'a': 1, 'b': 2},
          ),
        ],
      );
      expect(result.isSuccess, isTrue);
    });

    test('test with matching list values passes', () {
      final result = engine.apply(
        document: _makeDoc({'items': [1, 2, 3]}),
        operations: [
          FormPatchOperation(
            op: 'test',
            path: '/data/items',
            value: [1, 2, 3],
          ),
        ],
      );
      expect(result.isSuccess, isTrue);
    });

    test('test with non-matching map values fails', () {
      final result = engine.apply(
        document: _makeDoc({'nested': {'a': 1}}),
        operations: [
          FormPatchOperation(
            op: 'test',
            path: '/data/nested',
            value: {'a': 2},
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.test_failed');
    });

    test('test with non-matching list values fails', () {
      final result = engine.apply(
        document: _makeDoc({'items': [1, 2]}),
        operations: [
          FormPatchOperation(
            op: 'test',
            path: '/data/items',
            value: [1, 3],
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.test_failed');
    });

    test('test with different length maps fails', () {
      final result = engine.apply(
        document: _makeDoc({'nested': {'a': 1}}),
        operations: [
          FormPatchOperation(
            op: 'test',
            path: '/data/nested',
            value: {'a': 1, 'b': 2},
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.test_failed');
    });

    test('test with different length lists fails', () {
      final result = engine.apply(
        document: _makeDoc({'items': [1, 2]}),
        operations: [
          FormPatchOperation(
            op: 'test',
            path: '/data/items',
            value: [1, 2, 3],
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.test_failed');
    });
  });

  group('PatchEngine - copy without from', () {
    test('copy without from fails validation', () {
      final errors = engine.validateOperations(
        document: _makeDoc(),
        operations: [
          FormPatchOperation(op: 'copy', path: '/data/x'),
        ],
      );
      expect(errors.length, 1);
      expect(errors[0].code, 'patch.invalid_from');
    });
  });

  group('PatchEngine - test without value', () {
    test('test without value fails validation', () {
      final errors = engine.validateOperations(
        document: _makeDoc(),
        operations: [
          FormPatchOperation(op: 'test', path: '/data/x'),
        ],
      );
      expect(errors.length, 1);
      expect(errors[0].code, 'patch.invalid_value');
    });
  });

  group('PatchEngine - resolve through list paths', () {
    test('resolves nested value through array index', () {
      final doc = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
        sections: [
          FormSection(
            sectionId: 'sec-1',
            index: 0,
            blocks: [
              FormTextBlock(blockId: 'blk-1', index: 0, content: 'Target'),
            ],
          ),
        ],
      );

      // Test operation to verify resolving through array
      final result = engine.apply(
        document: doc,
        operations: [
          FormPatchOperation(
            op: 'test',
            path: '/sections/0/sectionId',
            value: 'sec-1',
          ),
        ],
      );
      expect(result.isSuccess, isTrue);
    });

    test('resolving through array with out-of-bounds index fails', () {
      final doc = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
        sections: [
          const FormSection(sectionId: 'sec-1', index: 0),
        ],
      );

      final result = engine.apply(
        document: doc,
        operations: [
          FormPatchOperation(
            op: 'test',
            path: '/sections/5/sectionId',
            value: 'sec-1',
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
    });

    test('resolving through scalar value fails', () {
      final result = engine.apply(
        document: _makeDoc({'name': 'Alice'}),
        operations: [
          FormPatchOperation(
            op: 'test',
            path: '/data/name/sub',
            value: 'x',
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
    });
  });

  group('PatchEngine - parent resolution through list', () {
    test('parent resolution through array with invalid index returns error',
        () {
      final doc = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
        sections: [
          const FormSection(sectionId: 'sec-1', index: 0),
        ],
      );

      // Try to add deep within an invalid array index
      final result = engine.apply(
        document: doc,
        operations: [
          FormPatchOperation(
            op: 'add',
            path: '/sections/99/blocks/0',
            value: {'type': 'text', 'blockId': 'x', 'index': 0},
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.invalid_path');
    });

    test('parent resolution through scalar value returns error', () {
      final result = engine.apply(
        document: _makeDoc({'name': 'Alice'}),
        operations: [
          FormPatchOperation(
            op: 'add',
            path: '/data/name/sub/deep',
            value: 'x',
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
      expect(result.errors[0].code, 'patch.invalid_path');
    });
  });

  group('PatchEngine - non-String-keyed Map deep copy', () {
    test('deep copies data containing non-String-keyed Map', () {
      // Create document with data containing a plain Map (not Map<String, dynamic>)
      // by using a Map literal that Dart infers as Map<dynamic, dynamic>
      final Map<dynamic, dynamic> plainMap = {1: 'one', 2: 'two'};
      final doc = _makeDoc({'nested': plainMap});

      final result = engine.apply(
        document: doc,
        operations: [
          FormPatchOperation(op: 'add', path: '/data/extra', value: 'ok'),
        ],
      );
      expect(result.isSuccess, isTrue);
      expect(result.document!.data['extra'], 'ok');
    });
  });

  group('PatchEngine - non-container operations', () {
    test('remove from non-container path fails', () {
      // Set up a document where the parent is a scalar
      final doc = _makeDoc({'level': 'top'});

      final result = engine.apply(
        document: doc,
        operations: [
          // First add a nested structure, then try to remove from scalar
          FormPatchOperation(op: 'add', path: '/data/obj', value: 'scalar'),
          FormPatchOperation(op: 'remove', path: '/data/obj/child'),
        ],
      );
      expect(result.isSuccess, isFalse);
    });

    test('replace on non-container path fails', () {
      final doc = _makeDoc({'level': 'top'});

      final result = engine.apply(
        document: doc,
        operations: [
          FormPatchOperation(op: 'add', path: '/data/obj', value: 'scalar'),
          FormPatchOperation(
            op: 'replace',
            path: '/data/obj/child',
            value: 'x',
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
    });

    test('add on non-container path fails', () {
      final doc = _makeDoc({'level': 'top'});

      final result = engine.apply(
        document: doc,
        operations: [
          FormPatchOperation(op: 'add', path: '/data/obj', value: 'scalar'),
          FormPatchOperation(
            op: 'add',
            path: '/data/obj/child',
            value: 'x',
          ),
        ],
      );
      expect(result.isSuccess, isFalse);
    });
  });
}
