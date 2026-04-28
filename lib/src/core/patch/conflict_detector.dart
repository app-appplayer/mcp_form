import 'package:mcp_bundle/mcp_bundle.dart';

/// Suggested resolution strategy for a patch conflict.
enum ConflictResolution { reject, merge, forceApply }

/// Represents a detected patch conflict.
class PatchConflict {
  const PatchConflict({
    required this.currentVersion,
    required this.expectedVersion,
    this.conflictingPaths = const [],
    required this.suggestedResolution,
  });

  final int currentVersion;
  final int expectedVersion;
  final List<String> conflictingPaths;
  final ConflictResolution suggestedResolution;
}

/// Represents a path-level conflict between two operation sets.
class PathConflict {
  const PathConflict({
    required this.path,
    required this.operationA,
    required this.operationB,
  });

  final String path;
  final String operationA;
  final String operationB;
}

/// Detects conflicts in concurrent patch operations using
/// optimistic concurrency control (version-based).
class ConflictDetector {
  const ConflictDetector();

  /// Check for version-based conflicts.
  ///
  /// Returns a [PatchConflict] if the expected version does not match
  /// the current document version; null if no conflict.
  ///
  /// When a conflict is detected, uses [findPathConflicts] to determine
  /// whether paths overlap. If non-overlapping, suggests merge;
  /// if overlapping, suggests reject.
  PatchConflict? check({
    required FormDocument currentDocument,
    required int expectedVersion,
    required List<FormPatchOperation> operations,
  }) {
    if (currentDocument.version == expectedVersion) {
      return null;
    }

    // Find overlapping paths between incoming operations
    // Since we don't have the actual operations applied between
    // expectedVersion and currentVersion, we compare incoming
    // paths against each other for structural overlap
    final incomingPaths = operations.map((op) => op.path).toSet();

    // Check for hierarchical path overlap among incoming operations
    final overlappingPaths = <String>[];
    for (final path in incomingPaths) {
      for (final other in incomingPaths) {
        if (path != other && _pathsOverlap(path, other)) {
          overlappingPaths.add(path);
          break;
        }
      }
    }

    // If there are overlapping paths among incoming operations,
    // or if the version gap is > 1 (indicating multiple concurrent edits),
    // suggest reject. Otherwise, suggest merge.
    final versionGap = currentDocument.version - expectedVersion;
    final hasOverlap = overlappingPaths.isNotEmpty || versionGap > 1;

    return PatchConflict(
      currentVersion: currentDocument.version,
      expectedVersion: expectedVersion,
      conflictingPaths: incomingPaths.toList(),
      suggestedResolution:
          hasOverlap ? ConflictResolution.reject : ConflictResolution.merge,
    );
  }

  /// Find path-level conflicts between two sets of operations.
  ///
  /// Returns a list of [PathConflict] entries for overlapping paths.
  /// Detects both exact matches and hierarchical overlaps
  /// (e.g., /sections/0 overlaps with /sections/0/blocks/1).
  List<PathConflict> findPathConflicts({
    required List<FormPatchOperation> operationsA,
    required List<FormPatchOperation> operationsB,
  }) {
    final conflicts = <PathConflict>[];
    final pathsA = <String, List<String>>{};

    // Collect all operations per path for operationsA
    for (final op in operationsA) {
      pathsA.putIfAbsent(op.path, () => []).add(op.op);
    }

    for (final op in operationsB) {
      // Check exact match
      if (pathsA.containsKey(op.path)) {
        conflicts.add(PathConflict(
          path: op.path,
          operationA: pathsA[op.path]!.first,
          operationB: op.op,
        ));
        continue;
      }

      // Check hierarchical overlap
      for (final pathA in pathsA.keys) {
        if (_pathsOverlap(pathA, op.path)) {
          conflicts.add(PathConflict(
            path: op.path,
            operationA: pathsA[pathA]!.first,
            operationB: op.op,
          ));
          break;
        }
      }
    }

    return conflicts;
  }

  /// Check if two JSON Pointer paths overlap hierarchically.
  ///
  /// Returns true if one path is a prefix of the other.
  /// E.g., /sections/0 and /sections/0/blocks/1 overlap.
  bool _pathsOverlap(String pathA, String pathB) {
    // Normalize paths
    final a = pathA.endsWith('/') ? pathA : '$pathA/';
    final b = pathB.endsWith('/') ? pathB : '$pathB/';
    return a.startsWith(b) || b.startsWith(a);
  }
}
