import 'package:mcp_bundle/mcp_bundle.dart';

/// Result of a patch operation.
class PatchResult {
  const PatchResult({
    this.document,
    required this.isSuccess,
    this.affectedPaths = const [],
    this.errors = const [],
    this.newVersion,
  });

  /// The patched document, null on failure.
  final FormDocument? document;

  /// Whether the patch operation succeeded.
  final bool isSuccess;

  /// Paths that were modified by the patch.
  final List<String> affectedPaths;

  /// Errors encountered during patching.
  final List<PatchError> errors;

  /// The new document version after patching.
  final int? newVersion;
}

/// Error from a patch operation.
class PatchError {
  const PatchError({
    required this.code,
    required this.message,
    this.path,
    this.operationIndex,
  });

  final String code;
  final String message;
  final String? path;
  final int? operationIndex;
}

/// Read-only paths that cannot be patched.
const _readOnlyPaths = {
  '/documentId',
  '/templateId',
  '/templateVersion',
  '/metadata/createdAt',
};

/// RFC 6902 JSON Patch engine for [FormDocument].
///
/// Operates on the full document structure via JSON Pointer paths,
/// supporting /data/*, /sections/*, /metadata/*, and /status paths.
/// All operations succeed or all are rolled back (atomicity).
class PatchEngine {
  const PatchEngine();

  /// Validate patch operations without applying them.
  List<PatchError> validateOperations({
    required FormDocument document,
    required List<FormPatchOperation> operations,
  }) {
    final errors = <PatchError>[];

    for (var i = 0; i < operations.length; i++) {
      final op = operations[i];

      // Check read-only paths
      if (_readOnlyPaths.contains(op.path)) {
        errors.add(PatchError(
          code: 'patch.invalid_path',
          message: 'Path "${op.path}" is read-only',
          path: op.path,
          operationIndex: i,
        ));
        continue;
      }

      // Validate operation has required fields
      switch (op.op) {
        case 'add':
        case 'replace':
        case 'test':
          if (op.value == null) {
            errors.add(PatchError(
              code: 'patch.invalid_value',
              message: 'Operation "${op.op}" requires a value',
              path: op.path,
              operationIndex: i,
            ));
          }
        case 'move':
        case 'copy':
          if (op.from == null) {
            errors.add(PatchError(
              code: 'patch.invalid_from',
              message: 'Operation "${op.op}" requires a "from" path',
              path: op.path,
              operationIndex: i,
            ));
          }
        case 'remove':
          break;
        default:
          errors.add(PatchError(
            code: 'patch.unknown_operation',
            message: 'Unknown operation "${op.op}"',
            path: op.path,
            operationIndex: i,
          ));
      }
    }

    return errors;
  }

  /// Apply a list of patch operations to a document atomically.
  ///
  /// Returns a [PatchResult] with the patched document on success,
  /// or errors on failure. On any failure, all changes are rolled back.
  PatchResult apply({
    required FormDocument document,
    required List<FormPatchOperation> operations,
  }) {
    // Pre-validate
    final validationErrors = validateOperations(
      document: document,
      operations: operations,
    );
    if (validationErrors.isNotEmpty) {
      return PatchResult(
        isSuccess: false,
        errors: validationErrors,
      );
    }

    // Convert document to deep mutable JSON for patch operations
    final json = _documentToMutableJson(document);
    final affectedPaths = <String>[];

    for (var i = 0; i < operations.length; i++) {
      final op = operations[i];
      final error = _applyOperation(json, op, i);

      if (error != null) {
        // Atomicity: rollback all changes
        return PatchResult(
          isSuccess: false,
          errors: [
            error,
            PatchError(
              code: 'patch.atomic_rollback',
              message:
                  'Operation ${i + 1} of ${operations.length} failed; '
                  'all changes rolled back',
              operationIndex: i,
            ),
          ],
        );
      }

      affectedPaths.add(op.path);
      if (op.op == 'move' && op.from != null) {
        affectedPaths.add(op.from!);
      }
    }

    // Reconstruct document from modified JSON
    final newVersion = document.version + 1;

    // Update modifiedAt timestamp
    final metadataJson = json['metadata'] as Map<String, dynamic>;
    metadataJson['modifiedAt'] = DateTime.now().toIso8601String();

    // Preserve createdAt from original (read-only)
    metadataJson['createdAt'] =
        document.metadata.createdAt.toIso8601String();

    // Update version
    json['version'] = newVersion;

    // Preserve bindings and validationIssues from original
    if (document.bindings != null) {
      json['bindings'] =
          document.bindings!.map((b) => b.toJson()).toList();
    }
    if (document.validationIssues != null) {
      json['validationIssues'] =
          document.validationIssues!.map((v) => v.toJson()).toList();
    }

    final patchedDocument = FormDocument.fromJson(json);

    return PatchResult(
      document: patchedDocument,
      isSuccess: true,
      affectedPaths: affectedPaths,
      newVersion: newVersion,
    );
  }

  /// Apply a single patch operation.
  PatchResult applySingle({
    required FormDocument document,
    required FormPatchOperation operation,
  }) {
    return apply(document: document, operations: [operation]);
  }

  /// Convert document to a deep mutable JSON map.
  Map<String, dynamic> _documentToMutableJson(FormDocument doc) {
    final json = _deepCopyJson(doc.toJson()) as Map<String, dynamic>;
    // Ensure data is always present (toJson omits when empty)
    json.putIfAbsent('data', () => <String, dynamic>{});
    // Ensure sections is always present
    json.putIfAbsent('sections', () => <dynamic>[]);
    return json;
  }

  /// Deep copy a JSON value to ensure full mutability.
  dynamic _deepCopyJson(dynamic value) {
    if (value is Map<String, dynamic>) {
      return {for (final e in value.entries) e.key: _deepCopyJson(e.value)};
    }
    if (value is Map) {
      return {
        for (final e in value.entries)
          e.key.toString(): _deepCopyJson(e.value),
      };
    }
    if (value is List) {
      return [for (final e in value) _deepCopyJson(e)];
    }
    return value;
  }

  /// Parse a JSON Pointer path into segments.
  List<String> _parsePath(String path) {
    return path.split('/').where((s) => s.isNotEmpty).toList();
  }

  /// Apply a single patch operation on the JSON map.
  PatchError? _applyOperation(
    Map<String, dynamic> root,
    FormPatchOperation op,
    int index,
  ) {
    switch (op.op) {
      case 'add':
        return _addAtPath(root, op.path, op.value, index);
      case 'remove':
        return _removeAtPath(root, op.path, index);
      case 'replace':
        return _replaceAtPath(root, op.path, op.value, index);
      case 'move':
        return _moveAtPath(root, op.from!, op.path, index);
      case 'copy':
        return _copyAtPath(root, op.from!, op.path, index);
      case 'test':
        return _testAtPath(root, op.path, op.value, index);
      default:
        return PatchError(
          code: 'patch.unknown_operation',
          message: 'Unknown operation "${op.op}"',
          path: op.path,
          operationIndex: index,
        );
    }
  }

  /// Resolve a value at a JSON Pointer path.
  dynamic _resolveValue(Map<String, dynamic> root, String path) {
    final segments = _parsePath(path);
    dynamic current = root;

    for (final seg in segments) {
      if (current is Map<String, dynamic>) {
        if (!current.containsKey(seg)) return _notFound;
        current = current[seg];
      } else if (current is List) {
        final idx = int.tryParse(seg);
        if (idx == null || idx < 0 || idx >= current.length) {
          return _notFound;
        }
        current = current[idx];
      } else {
        return _notFound;
      }
    }
    return current;
  }

  /// Resolve the parent container and the last segment of a path.
  _PathTarget? _resolveParent(Map<String, dynamic> root, String path) {
    final segments = _parsePath(path);
    if (segments.isEmpty) return null;

    dynamic current = root;
    for (var i = 0; i < segments.length - 1; i++) {
      final seg = segments[i];
      if (current is Map<String, dynamic>) {
        if (!current.containsKey(seg)) return null;
        current = current[seg];
      } else if (current is List) {
        final idx = int.tryParse(seg);
        if (idx == null || idx < 0 || idx >= current.length) return null;
        current = current[idx];
      } else {
        return null;
      }
    }

    return _PathTarget(parent: current, lastSegment: segments.last);
  }

  PatchError? _addAtPath(
    Map<String, dynamic> root,
    String path,
    dynamic value,
    int index,
  ) {
    final target = _resolveParent(root, path);
    if (target == null) {
      return PatchError(
        code: 'patch.invalid_path',
        message: 'Cannot resolve path "$path"',
        path: path,
        operationIndex: index,
      );
    }

    final parent = target.parent;
    final key = target.lastSegment;

    if (parent is Map<String, dynamic>) {
      parent[key] = _deepCopyJson(value);
    } else if (parent is List) {
      if (key == '-') {
        // RFC 6901: '-' means append to end of array
        parent.add(_deepCopyJson(value));
      } else {
        final idx = int.tryParse(key);
        if (idx == null || idx < 0 || idx > parent.length) {
          return PatchError(
            code: 'patch.invalid_path',
            message: 'Invalid array index "$key" in path "$path"',
            path: path,
            operationIndex: index,
          );
        }
        parent.insert(idx, _deepCopyJson(value));
      }
    } else {
      return PatchError(
        code: 'patch.invalid_path',
        message: 'Cannot add to non-container at "$path"',
        path: path,
        operationIndex: index,
      );
    }
    return null;
  }

  PatchError? _removeAtPath(
    Map<String, dynamic> root,
    String path,
    int index,
  ) {
    final target = _resolveParent(root, path);
    if (target == null) {
      return PatchError(
        code: 'patch.invalid_path',
        message: 'Cannot resolve path "$path"',
        path: path,
        operationIndex: index,
      );
    }

    final parent = target.parent;
    final key = target.lastSegment;

    if (parent is Map<String, dynamic>) {
      if (!parent.containsKey(key)) {
        return PatchError(
          code: 'patch.invalid_path',
          message: 'Path "$path" does not exist',
          path: path,
          operationIndex: index,
        );
      }
      parent.remove(key);
    } else if (parent is List) {
      final idx = int.tryParse(key);
      if (idx == null || idx < 0 || idx >= parent.length) {
        return PatchError(
          code: 'patch.invalid_path',
          message: 'Path "$path" does not exist',
          path: path,
          operationIndex: index,
        );
      }
      parent.removeAt(idx);
    } else {
      return PatchError(
        code: 'patch.invalid_path',
        message: 'Cannot remove from non-container at "$path"',
        path: path,
        operationIndex: index,
      );
    }
    return null;
  }

  PatchError? _replaceAtPath(
    Map<String, dynamic> root,
    String path,
    dynamic value,
    int index,
  ) {
    final target = _resolveParent(root, path);
    if (target == null) {
      return PatchError(
        code: 'patch.invalid_path',
        message: 'Cannot resolve path "$path"',
        path: path,
        operationIndex: index,
      );
    }

    final parent = target.parent;
    final key = target.lastSegment;

    if (parent is Map<String, dynamic>) {
      if (!parent.containsKey(key)) {
        return PatchError(
          code: 'patch.invalid_path',
          message: 'Path "$path" does not exist',
          path: path,
          operationIndex: index,
        );
      }
      parent[key] = _deepCopyJson(value);
    } else if (parent is List) {
      final idx = int.tryParse(key);
      if (idx == null || idx < 0 || idx >= parent.length) {
        return PatchError(
          code: 'patch.invalid_path',
          message: 'Path "$path" does not exist',
          path: path,
          operationIndex: index,
        );
      }
      parent[idx] = _deepCopyJson(value);
    } else {
      return PatchError(
        code: 'patch.invalid_path',
        message: 'Cannot replace in non-container at "$path"',
        path: path,
        operationIndex: index,
      );
    }
    return null;
  }

  PatchError? _moveAtPath(
    Map<String, dynamic> root,
    String fromPath,
    String toPath,
    int index,
  ) {
    // Get value at source
    final value = _resolveValue(root, fromPath);
    if (identical(value, _notFound)) {
      return PatchError(
        code: 'patch.invalid_from',
        message: 'Source path "$fromPath" does not exist',
        path: toPath,
        operationIndex: index,
      );
    }

    // Remove from source
    final removeError = _removeAtPath(root, fromPath, index);
    if (removeError != null) return removeError;

    // Add to target
    final addError = _addAtPath(root, toPath, value, index);
    if (addError != null) return addError;

    return null;
  }

  PatchError? _copyAtPath(
    Map<String, dynamic> root,
    String fromPath,
    String toPath,
    int index,
  ) {
    // Get value at source
    final value = _resolveValue(root, fromPath);
    if (identical(value, _notFound)) {
      return PatchError(
        code: 'patch.invalid_from',
        message: 'Source path "$fromPath" does not exist',
        path: toPath,
        operationIndex: index,
      );
    }

    // Add copy to target
    return _addAtPath(root, toPath, value, index);
  }

  PatchError? _testAtPath(
    Map<String, dynamic> root,
    String path,
    dynamic expectedValue,
    int index,
  ) {
    final value = _resolveValue(root, path);
    if (identical(value, _notFound)) {
      return PatchError(
        code: 'patch.invalid_path',
        message: 'Path "$path" does not exist',
        path: path,
        operationIndex: index,
      );
    }

    if (!_deepEquals(value, expectedValue)) {
      return PatchError(
        code: 'patch.test_failed',
        message: 'Test failed: expected $expectedValue, got $value',
        path: path,
        operationIndex: index,
      );
    }
    return null;
  }

  /// Deep equality comparison for JSON values.
  bool _deepEquals(dynamic a, dynamic b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) {
          return false;
        }
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}

/// Sentinel value for "not found" in JSON traversal.
final _notFound = Object();

/// Resolved parent container and last path segment.
class _PathTarget {
  const _PathTarget({required this.parent, required this.lastSegment});

  final dynamic parent;
  final String lastSegment;
}
