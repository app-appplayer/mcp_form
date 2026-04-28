import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/core/patch/conflict_detector.dart';
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
  const detector = ConflictDetector();

  group('ConflictDetector - version check', () {
    // TC-245: Version match - no conflict
    test('no conflict when versions match', () {
      final conflict = detector.check(
        currentDocument: _makeDoc(version: 3),
        expectedVersion: 3,
        operations: [
          FormPatchOperation(op: 'add', path: '/data/x', value: 1),
        ],
      );
      expect(conflict, isNull);
    });

    // TC-246: Version mismatch - conflict
    test('detects conflict when versions differ', () {
      final conflict = detector.check(
        currentDocument: _makeDoc(version: 5),
        expectedVersion: 3,
        operations: [
          FormPatchOperation(op: 'add', path: '/data/x', value: 1),
        ],
      );
      expect(conflict, isNotNull);
      expect(conflict!.currentVersion, 5);
      expect(conflict.expectedVersion, 3);
    });
  });

  group('ConflictDetector - path conflicts', () {
    // TC-247: Non-overlapping paths
    test('no path conflicts for non-overlapping operations', () {
      final conflicts = detector.findPathConflicts(
        operationsA: [
          FormPatchOperation(op: 'replace', path: '/data/a', value: 1),
        ],
        operationsB: [
          FormPatchOperation(op: 'replace', path: '/data/b', value: 2),
        ],
      );
      expect(conflicts, isEmpty);
    });

    // TC-248: Overlapping paths
    test('detects path conflicts for overlapping operations', () {
      final conflicts = detector.findPathConflicts(
        operationsA: [
          FormPatchOperation(op: 'replace', path: '/data/name', value: 'A'),
        ],
        operationsB: [
          FormPatchOperation(op: 'replace', path: '/data/name', value: 'B'),
        ],
      );
      expect(conflicts.length, 1);
      expect(conflicts[0].path, '/data/name');
    });

    test('detects hierarchical path conflicts', () {
      final conflicts = detector.findPathConflicts(
        operationsA: [
          FormPatchOperation(
            op: 'replace',
            path: '/sections/0',
            value: 'A',
          ),
        ],
        operationsB: [
          FormPatchOperation(
            op: 'add',
            path: '/sections/0/blocks/1',
            value: 'B',
          ),
        ],
      );
      expect(conflicts.length, 1);
      expect(conflicts[0].path, '/sections/0/blocks/1');
      expect(conflicts[0].operationA, 'replace');
      expect(conflicts[0].operationB, 'add');
    });
  });

  group('ConflictDetector - hierarchical overlap in check', () {
    test('detects overlapping paths among incoming operations', () {
      // Operations with hierarchical overlap: /sections/0 and /sections/0/blocks/1
      // and version gap of 1, so overlap drives reject
      final conflict = detector.check(
        currentDocument: _makeDoc(version: 2),
        expectedVersion: 1,
        operations: [
          FormPatchOperation(
            op: 'replace',
            path: '/sections/0',
            value: 'A',
          ),
          FormPatchOperation(
            op: 'add',
            path: '/sections/0/blocks/1',
            value: 'B',
          ),
        ],
      );
      expect(conflict, isNotNull);
      expect(conflict!.suggestedResolution, ConflictResolution.reject);
    });

    test('suggests merge for non-overlapping paths with version gap 1', () {
      final conflict = detector.check(
        currentDocument: _makeDoc(version: 2),
        expectedVersion: 1,
        operations: [
          FormPatchOperation(op: 'add', path: '/data/a', value: 1),
          FormPatchOperation(op: 'add', path: '/data/b', value: 2),
        ],
      );
      expect(conflict, isNotNull);
      expect(conflict!.suggestedResolution, ConflictResolution.merge);
    });

    test('suggests reject for large version gap even without overlap', () {
      final conflict = detector.check(
        currentDocument: _makeDoc(version: 5),
        expectedVersion: 2,
        operations: [
          FormPatchOperation(op: 'add', path: '/data/a', value: 1),
        ],
      );
      expect(conflict, isNotNull);
      expect(conflict!.suggestedResolution, ConflictResolution.reject);
    });
  });
}
