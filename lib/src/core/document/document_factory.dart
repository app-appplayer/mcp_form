import 'package:mcp_bundle/mcp_bundle.dart';

/// Factory for creating [FormDocument] instances from [FormTemplate]s.
///
/// Handles document ID generation, metadata initialization,
/// section construction from template defaults, and initial data
/// application to matching block fields.
class DocumentFactory {
  const DocumentFactory();

  /// Create a new [FormDocument] from a [FormTemplate] with initial data.
  ///
  /// The document is created in [FormDocumentStatus.draft] status
  /// with version 1. Sections are built from the template's
  /// [FormTemplate.defaultSections], with [data] values applied
  /// to matching [FormFieldBlock] fields.
  ///
  /// If [documentId] is not provided, a UUID-style ID is auto-generated.
  FormDocument createFromTemplate({
    required FormTemplate template,
    Map<String, dynamic> data = const {},
    String? documentId,
    String? author,
  }) {
    final now = DateTime.now();
    final id = documentId ?? _generateId(now);

    return FormDocument(
      documentId: id,
      templateId: template.templateId,
      templateVersion: template.version,
      metadata: FormDocumentMetadata(
        author: author ?? 'system',
        createdAt: now,
      ),
      status: FormDocumentStatus.draft,
      version: 1,
      sections: _buildSectionsFromTemplate(template, data),
      data: data,
    );
  }

  /// Build sections from template, applying initial data to field blocks.
  List<FormSection> _buildSectionsFromTemplate(
    FormTemplate template,
    Map<String, dynamic> data,
  ) {
    if (template.defaultSections.isEmpty) {
      return const [FormSection(sectionId: 'main', index: 0)];
    }

    final sections = <FormSection>[];
    for (var i = 0; i < template.defaultSections.length; i++) {
      final templateSection = template.defaultSections[i];
      final blocks = _buildBlocksForSection(templateSection.blocks, data);
      sections.add(FormSection(
        sectionId: templateSection.sectionId,
        index: i,
        title: templateSection.title,
        description: templateSection.description,
        blocks: blocks,
      ));
    }
    return sections;
  }

  /// Build blocks for a section, applying data values to FormFieldBlocks.
  List<FormBlock> _buildBlocksForSection(
    List<FormBlock> templateBlocks,
    Map<String, dynamic> data,
  ) {
    if (data.isEmpty) return List.of(templateBlocks);

    return templateBlocks.map((block) {
      if (block is FormFieldBlock && data.containsKey(block.fieldName)) {
        // Apply initial data to matching field block
        return FormFieldBlock(
          blockId: block.blockId,
          index: block.index,
          fieldName: block.fieldName,
          fieldType: block.fieldType,
          placeholder: block.placeholder,
          options: block.options,
          constraints: block.constraints,
          style: block.style,
        );
      }
      return block;
    }).toList();
  }

  /// Generate a UUID-style document ID.
  String _generateId(DateTime now) {
    final ms = now.microsecondsSinceEpoch;
    final hex = ms.toRadixString(16).padLeft(12, '0');
    return 'doc-${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${now.millisecondsSinceEpoch.toRadixString(16).padLeft(8, '0')}';
  }
}
