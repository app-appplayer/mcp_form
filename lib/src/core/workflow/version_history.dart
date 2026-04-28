import 'package:mcp_bundle/mcp_bundle.dart';

import 'transition_rule.dart';

/// A snapshot of a document version.
class VersionEntry {
  const VersionEntry({
    required this.documentId,
    required this.version,
    required this.snapshot,
    this.transition,
    required this.recordedAt,
  });

  final String documentId;
  final int version;
  final FormDocument snapshot;
  final TransitionResult? transition;
  final DateTime recordedAt;
}

/// Change type in a version diff.
enum DiffChangeType { added, removed, modified, moved }

/// A single change between two document versions.
class DiffEntry {
  const DiffEntry({
    required this.path,
    required this.changeType,
    this.oldValue,
    this.newValue,
    this.blockType,
  });

  final String path;
  final DiffChangeType changeType;
  final dynamic oldValue;
  final dynamic newValue;
  final String? blockType;
}

/// Result of comparing two document versions.
class VersionDiffResult {
  const VersionDiffResult({
    required this.documentId,
    required this.fromVersion,
    required this.toVersion,
    required this.changes,
    required this.computedAt,
  });

  final String documentId;
  final int fromVersion;
  final int toVersion;
  final List<DiffEntry> changes;
  final DateTime computedAt;
}

/// In-memory version history storage.
class VersionHistory {
  final Map<String, List<VersionEntry>> _store = {};

  /// Record a version snapshot.
  void recordVersion({
    required String documentId,
    required int version,
    required FormDocument document,
    TransitionResult? transition,
  }) {
    _store.putIfAbsent(documentId, () => []);
    _store[documentId]!.add(VersionEntry(
      documentId: documentId,
      version: version,
      snapshot: document,
      transition: transition,
      recordedAt: DateTime.now(),
    ));
  }

  /// List all versions for a document (descending order).
  List<VersionEntry> listVersions(String documentId) {
    final entries = _store[documentId] ?? [];
    return List.of(entries)..sort((a, b) => b.version.compareTo(a.version));
  }

  /// Get a specific version or null.
  VersionEntry? getVersion(String documentId, int version) {
    final entries = _store[documentId];
    if (entries == null) return null;
    for (final entry in entries) {
      if (entry.version == version) return entry;
    }
    return null;
  }

  /// Get the latest version or null.
  VersionEntry? getLatestVersion(String documentId) {
    final entries = _store[documentId];
    if (entries == null || entries.isEmpty) return null;
    return entries.reduce(
      (a, b) => a.version > b.version ? a : b,
    );
  }

  /// Compare two document versions using ID-based block matching
  /// with deep content comparison.
  VersionDiffResult compare(FormDocument fromDoc, FormDocument toDoc) {
    final changes = <DiffEntry>[];

    // Compare status
    if (fromDoc.status != toDoc.status) {
      changes.add(DiffEntry(
        path: '/status',
        changeType: DiffChangeType.modified,
        oldValue: fromDoc.status.name,
        newValue: toDoc.status.name,
      ));
    }

    // Compare metadata author
    if (fromDoc.metadata.author != toDoc.metadata.author) {
      changes.add(DiffEntry(
        path: '/metadata/author',
        changeType: DiffChangeType.modified,
        oldValue: fromDoc.metadata.author,
        newValue: toDoc.metadata.author,
      ));
    }

    // Compare sections using ID-based matching
    _compareSections(fromDoc.sections, toDoc.sections, changes);

    // Compare data fields
    final allKeys = {...fromDoc.data.keys, ...toDoc.data.keys};
    for (final key in allKeys) {
      final fromVal = fromDoc.data[key];
      final toVal = toDoc.data[key];
      if (fromVal == null && toVal != null) {
        changes.add(DiffEntry(
          path: '/data/$key',
          changeType: DiffChangeType.added,
          newValue: toVal,
        ));
      } else if (fromVal != null && toVal == null) {
        changes.add(DiffEntry(
          path: '/data/$key',
          changeType: DiffChangeType.removed,
          oldValue: fromVal,
        ));
      } else if (!_deepEquals(fromVal, toVal)) {
        changes.add(DiffEntry(
          path: '/data/$key',
          changeType: DiffChangeType.modified,
          oldValue: fromVal,
          newValue: toVal,
        ));
      }
    }

    return VersionDiffResult(
      documentId: fromDoc.documentId,
      fromVersion: fromDoc.version,
      toVersion: toDoc.version,
      changes: changes,
      computedAt: DateTime.now(),
    );
  }

  /// Compare sections using sectionId-based matching.
  void _compareSections(
    List<FormSection> fromSections,
    List<FormSection> toSections,
    List<DiffEntry> changes,
  ) {
    final fromMap = {for (final s in fromSections) s.sectionId: s};
    final toMap = {for (final s in toSections) s.sectionId: s};

    // Sections removed
    for (final entry in fromMap.entries) {
      if (!toMap.containsKey(entry.key)) {
        changes.add(DiffEntry(
          path: '/sections/${entry.value.index}',
          changeType: DiffChangeType.removed,
          oldValue: entry.value.toJson(),
        ));
      }
    }

    // Sections added
    for (final entry in toMap.entries) {
      if (!fromMap.containsKey(entry.key)) {
        changes.add(DiffEntry(
          path: '/sections/${entry.value.index}',
          changeType: DiffChangeType.added,
          newValue: entry.value.toJson(),
        ));
      }
    }

    // Sections present in both - compare blocks
    for (final entry in fromMap.entries) {
      final toSection = toMap[entry.key];
      if (toSection == null) continue;

      final fromSection = entry.value;
      final sectionPath = '/sections/${toSection.index}';

      _compareBlocks(
        fromSection.blocks,
        toSection.blocks,
        sectionPath,
        changes,
      );
    }
  }

  /// Compare blocks using blockId-based matching with deep equality.
  void _compareBlocks(
    List<FormBlock> fromBlocks,
    List<FormBlock> toBlocks,
    String sectionPath,
    List<DiffEntry> changes,
  ) {
    final fromMap = {for (final b in fromBlocks) b.blockId: b};
    final toMap = {for (final b in toBlocks) b.blockId: b};

    // Blocks removed
    for (final entry in fromMap.entries) {
      if (!toMap.containsKey(entry.key)) {
        final b = entry.value;
        changes.add(DiffEntry(
          path: '$sectionPath/blocks/${b.index}',
          changeType: DiffChangeType.removed,
          oldValue: b.toJson(),
          blockType: b.runtimeType.toString(),
        ));
      }
    }

    // Blocks added
    for (final entry in toMap.entries) {
      if (!fromMap.containsKey(entry.key)) {
        final b = entry.value;
        changes.add(DiffEntry(
          path: '$sectionPath/blocks/${b.index}',
          changeType: DiffChangeType.added,
          newValue: b.toJson(),
          blockType: b.runtimeType.toString(),
        ));
      }
    }

    // Blocks present in both - deep compare
    for (final entry in fromMap.entries) {
      final toBlock = toMap[entry.key];
      if (toBlock == null) continue;

      final fromBlock = entry.value;
      final fromJson = fromBlock.toJson();
      final toJson = toBlock.toJson();

      if (!_deepEquals(fromJson, toJson)) {
        changes.add(DiffEntry(
          path: '$sectionPath/blocks/${toBlock.index}',
          changeType: DiffChangeType.modified,
          oldValue: fromJson,
          newValue: toJson,
          blockType: toBlock.runtimeType.toString(),
        ));
      }
    }
  }

  /// Recursive deep equality for JSON-compatible values.
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
