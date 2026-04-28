import 'package:mcp_bundle/mcp_bundle.dart';

/// Lightweight summary of a FormTemplate for list/search operations.
///
/// This is a local mcp_form type (not from mcp_bundle).
/// Contains only identity and metadata fields, excluding
/// the full schema, layout policy, and component details.
/// Derived from full FormTemplate instances returned by
/// FormTemplatePort.listTemplates().
class TemplateSummary {
  TemplateSummary({
    required this.templateId,
    required this.version,
    required this.name,
    this.description,
    required this.fieldCount,
    required this.sectionCount,
    this.componentCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Unique template identifier.
  final String templateId;

  /// Semantic version string.
  final String version;

  /// Human-readable template name.
  final String name;

  /// Optional description.
  final String? description;

  /// Number of schema fields defined.
  final int fieldCount;

  /// Number of sections defined.
  final int sectionCount;

  /// Number of component references.
  final int componentCount;

  /// Template creation timestamp.
  final DateTime createdAt;

  /// Last modification timestamp.
  final DateTime updatedAt;
}

/// Extension to create a TemplateSummary from a full FormTemplate.
extension TemplateProjection on FormTemplate {
  /// Creates a lightweight summary projection.
  /// Creates a lightweight summary projection.
  ///
  /// Optional [createdAt] and [updatedAt] timestamps can be provided
  /// when the caller has metadata from storage. If omitted, falls back
  /// to the current time.
  TemplateSummary toSummary({DateTime? createdAt, DateTime? updatedAt}) {
    return TemplateSummary(
      templateId: templateId,
      version: version,
      name: name,
      description: description,
      fieldCount: schema.fields.length,
      sectionCount: defaultSections.length,
      componentCount: components?.length ?? 0,
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
