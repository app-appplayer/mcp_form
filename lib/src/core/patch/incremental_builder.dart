import 'package:mcp_bundle/mcp_bundle.dart';

/// Incrementally builds a [FormDocument] section-by-section and
/// block-by-block.
///
/// Used for progressive document generation (e.g., by LLM). Maintains
/// an operation history for audit trail. After [build()] is called,
/// further modifications throw [StateError].
///
/// Section and block indices are automatically assigned based on the
/// current count, regardless of the indices provided in the input.
class IncrementalBuilder {
  IncrementalBuilder({
    required String templateId,
    required String templateVersion,
    required String author,
  })  : _templateId = templateId,
        _templateVersion = templateVersion,
        _author = author,
        _createdAt = DateTime.now();

  final String _templateId;
  final String _templateVersion;
  final String _author;
  final DateTime _createdAt;
  final List<FormSection> _sections = [];
  final List<FormPatchOperation> _operations = [];
  bool _isFinalized = false;

  /// Add a section to the document.
  ///
  /// The section index is automatically assigned based on the current
  /// section count.
  void addSection(FormSection section) {
    _ensureNotFinalized();
    final autoIndex = _sections.length;
    final indexedSection = FormSection(
      sectionId: section.sectionId,
      index: autoIndex,
      title: section.title,
      description: section.description,
      blocks: section.blocks,
    );
    _sections.add(indexedSection);
    _operations.add(FormPatchOperation(
      op: 'add',
      path: '/sections/$autoIndex',
      value: indexedSection.toJson(),
    ));
  }

  /// Add a block to an existing section.
  ///
  /// The block index is automatically assigned based on the current
  /// block count within the section.
  void addBlock({required int sectionIndex, required FormBlock block}) {
    _ensureNotFinalized();
    if (sectionIndex < 0 || sectionIndex >= _sections.length) {
      throw RangeError.range(
        sectionIndex, 0, _sections.length - 1, 'sectionIndex',
      );
    }

    final section = _sections[sectionIndex];
    final autoBlockIndex = section.blocks.length;
    final indexedBlock = _withBlockIndex(block, autoBlockIndex);
    final blocks = List<FormBlock>.from(section.blocks)..add(indexedBlock);
    _sections[sectionIndex] = FormSection(
      sectionId: section.sectionId,
      index: section.index,
      title: section.title,
      description: section.description,
      blocks: blocks,
    );

    _operations.add(FormPatchOperation(
      op: 'add',
      path: '/sections/$sectionIndex/blocks/$autoBlockIndex',
      value: indexedBlock.toJson(),
    ));
  }

  /// Get the current in-progress document snapshot.
  FormDocument get currentDocument {
    return FormDocument(
      documentId: 'building',
      templateId: _templateId,
      templateVersion: _templateVersion,
      metadata: FormDocumentMetadata(
        author: _author,
        createdAt: _createdAt,
      ),
      status: FormDocumentStatus.draft,
      sections: List.unmodifiable(_sections),
    );
  }

  /// Finalize the document. Further modifications will throw.
  FormDocument build() {
    _isFinalized = true;
    final now = DateTime.now();
    final hex = now.microsecondsSinceEpoch.toRadixString(16).padLeft(12, '0');
    return FormDocument(
      documentId:
          'doc-${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
          '${now.millisecondsSinceEpoch.toRadixString(16).padLeft(8, '0')}',
      templateId: _templateId,
      templateVersion: _templateVersion,
      metadata: FormDocumentMetadata(
        author: _author,
        createdAt: _createdAt,
        modifiedAt: now,
      ),
      status: FormDocumentStatus.draft,
      sections: List.unmodifiable(_sections),
    );
  }

  /// History of all operations performed during building.
  List<FormPatchOperation> get operationHistory =>
      List.unmodifiable(_operations);

  void _ensureNotFinalized() {
    if (_isFinalized) {
      throw StateError('Builder has been finalized. Cannot add more content.');
    }
  }

  /// Create a new block with the given index, preserving the block type.
  FormBlock _withBlockIndex(FormBlock block, int index) {
    // Rebuild block from JSON with updated index
    final json = block.toJson();
    json['index'] = index;
    return FormBlock.fromJson(json);
  }
}
