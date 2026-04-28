import 'package:mcp_bundle/mcp_bundle.dart';

// ============================================================================
// DocumentVersioning Extension (DDD: core-document/02-model.md S5.1)
// ============================================================================

/// Extension to create a new version of a document with incremented version.
///
/// Used by MOD-CORE-005 (Patch) and MOD-CORE-004 (Binding) when
/// producing modified documents.
extension DocumentVersioning on FormDocument {
  /// Create a new version with incremented version number and updated
  /// modifiedAt timestamp.
  FormDocument incrementVersion() {
    final now = DateTime.now();
    return FormDocument(
      documentId: documentId,
      templateId: templateId,
      templateVersion: templateVersion,
      metadata: FormDocumentMetadata(
        author: metadata.author,
        createdAt: metadata.createdAt,
        modifiedAt: now,
        publishedAt: metadata.publishedAt,
        dataSource: metadata.dataSource,
        engineVersion: metadata.engineVersion,
      ),
      status: status,
      version: version + 1,
      sections: sections,
      data: data,
      bindings: bindings,
      validationIssues: validationIssues,
    );
  }
}

// ============================================================================
// DocumentCloning Extension (DDD: core-document/02-model.md S5.2)
// ============================================================================

/// Extension to clone a document as a new draft with fresh identity.
extension DocumentCloning on FormDocument {
  /// Create a new document as a clone of the current one.
  /// Resets status to draft, generates a new documentId,
  /// and sets version to 1.
  FormDocument cloneAsNewDocument({String? newDocumentId}) {
    final now = DateTime.now();
    return FormDocument(
      documentId: newDocumentId ?? _generateUuid(now),
      templateId: templateId,
      templateVersion: templateVersion,
      metadata: FormDocumentMetadata(
        author: metadata.author,
        createdAt: now,
        modifiedAt: now,
        dataSource: metadata.dataSource,
        engineVersion: metadata.engineVersion,
      ),
      status: FormDocumentStatus.draft,
      version: 1,
      sections: sections,
      data: data,
      bindings: bindings,
      validationIssues: validationIssues,
    );
  }
}

// ============================================================================
// FormDocumentStatusExtension (DDD: core-document/05-metadata.md S3.2)
// ============================================================================

/// Extension providing convenience properties for [FormDocumentStatus].
extension FormDocumentStatusExtension on FormDocumentStatus {
  /// Whether the document content can be modified in this status.
  bool get isEditable => this == FormDocumentStatus.draft;

  /// Whether the document can be rendered/exported in this status.
  bool get isExportable =>
      this == FormDocumentStatus.approved ||
      this == FormDocumentStatus.published;

  /// Whether the document is in a terminal state.
  bool get isTerminal => this == FormDocumentStatus.published;

  /// Human-readable display name for the status.
  String get displayName {
    return switch (this) {
      FormDocumentStatus.draft => 'Draft',
      FormDocumentStatus.review => 'Under Review',
      FormDocumentStatus.approved => 'Approved',
      FormDocumentStatus.published => 'Published',
    };
  }
}

// ============================================================================
// Transition Utility Functions (DDD: core-document/05-metadata.md S4.4)
// ============================================================================

/// Validates whether a state transition is allowed.
///
/// Returns true if the transition from [current] to [target] is valid
/// per the document lifecycle state machine.
bool isValidTransition(
  FormDocumentStatus current,
  FormDocumentStatus target,
) {
  return switch ((current, target)) {
    (FormDocumentStatus.draft, FormDocumentStatus.review) => true,
    (FormDocumentStatus.review, FormDocumentStatus.approved) => true,
    (FormDocumentStatus.review, FormDocumentStatus.draft) => true,
    (FormDocumentStatus.approved, FormDocumentStatus.published) => true,
    _ => false,
  };
}

/// Returns the set of valid target states from the given current state.
Set<FormDocumentStatus> validTransitionsFrom(FormDocumentStatus current) {
  return switch (current) {
    FormDocumentStatus.draft => {FormDocumentStatus.review},
    FormDocumentStatus.review => {
      FormDocumentStatus.approved,
      FormDocumentStatus.draft,
    },
    FormDocumentStatus.approved => {FormDocumentStatus.published},
    FormDocumentStatus.published => {},
  };
}

/// Check whether a modifying operation is permitted on this document.
///
/// Returns a [FormError] if the operation is not allowed, null if allowed.
FormError? checkModificationAllowed(FormDocument document) {
  if (document.status != FormDocumentStatus.draft) {
    return FormError(
      code: 'document.invalid_state',
      message: 'Document in "${document.status.name}" state cannot be modified. '
          'Only documents in "draft" state allow content modifications.',
      path: '/status',
    );
  }
  return null;
}

// ============================================================================
// Block Path Utilities (FR-DOM-002)
// ============================================================================

/// Generate the JSON Pointer path for a block within a document.
///
/// Returns a path like `/sections/0/blocks/2` for the block at
/// section index 0, block index 2.
/// Returns null if the block is not found in the document.
String? blockPath(FormDocument document, String blockId) {
  for (var si = 0; si < document.sections.length; si++) {
    final section = document.sections[si];
    for (var bi = 0; bi < section.blocks.length; bi++) {
      if (section.blocks[bi].blockId == blockId) {
        return '/sections/$si/blocks/$bi';
      }
    }
  }
  return null;
}

/// Generate paths for all blocks in a document.
///
/// Returns a map of blockId to JSON Pointer path.
Map<String, String> allBlockPaths(FormDocument document) {
  final paths = <String, String>{};
  for (var si = 0; si < document.sections.length; si++) {
    final section = document.sections[si];
    for (var bi = 0; bi < section.blocks.length; bi++) {
      paths[section.blocks[bi].blockId] = '/sections/$si/blocks/$bi';
    }
  }
  return paths;
}

// ============================================================================
// Private helpers
// ============================================================================

/// Generate a UUID-style document ID.
String _generateUuid(DateTime now) {
  final ms = now.microsecondsSinceEpoch;
  final hex = ms.toRadixString(16).padLeft(12, '0');
  return 'doc-${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${now.millisecondsSinceEpoch.toRadixString(16).padLeft(8, '0')}';
}
