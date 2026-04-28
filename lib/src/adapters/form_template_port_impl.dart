import 'package:mcp_bundle/mcp_bundle.dart';

import '../core/template/schema_validator.dart';

/// In-memory implementation of [FormTemplatePort].
///
/// Stores templates keyed by templateId, with version history tracking.
class FormTemplatePortImpl implements FormTemplatePort {
  final Map<String, FormTemplate> _templates = {};
  final Map<String, List<FormTemplateVersion>> _versions = {};

  @override
  Future<FormResult<FormTemplate>> saveTemplate({
    required FormTemplate template,
  }) async {
    // FR-TMPL-001: Reject duplicate templateId+version
    final existing = _templates[template.templateId];
    if (existing != null && existing.version == template.version) {
      return FormResult.fail(FormError(
        code: 'template.duplicate',
        message:
            'Template "${template.templateId}" version "${template.version}" '
            'already exists',
        path: '/templateId',
      ));
    }

    // FR-TMPL-002: Validate schema has at least one field
    final schemaErrors = validateSchema(template.schema);
    if (schemaErrors.isNotEmpty) {
      return FormResult.fail(FormError(
        code: 'template.invalid_schema',
        message:
            'Template schema validation failed: ${schemaErrors.first.message}',
        path: '/schema',
      ));
    }

    _templates[template.templateId] = template;

    // Record version history
    _versions.putIfAbsent(template.templateId, () => []);
    _versions[template.templateId]!.add(FormTemplateVersion(
      templateId: template.templateId,
      version: template.version,
      createdAt: DateTime.now(),
    ));

    return FormResult.ok(template);
  }

  @override
  Future<FormResult<FormTemplate>> getTemplate({
    required String templateId,
    String? version,
  }) async {
    final template = _templates[templateId];
    if (template == null) {
      return FormResult.fail(FormError(
        code: 'template.not_found',
        message: 'Template "$templateId" not found',
      ));
    }

    // If a specific version is requested and doesn't match current
    if (version != null && template.version != version) {
      return FormResult.fail(FormError(
        code: 'template.version_not_found',
        message: 'Template "$templateId" version "$version" not found',
      ));
    }

    return FormResult.ok(template);
  }

  @override
  Future<FormResult<List<FormTemplate>>> listTemplates({
    String? search,
    int? limit,
    int? offset,
  }) async {
    var results = _templates.values.toList();

    if (search != null) {
      results = results
          .where((t) =>
              t.name.toLowerCase().contains(search.toLowerCase()) ||
              (t.description?.toLowerCase().contains(search.toLowerCase()) ??
                  false))
          .toList();
    }

    final start = offset ?? 0;
    if (start >= results.length) {
      return FormResult.ok(const []);
    }
    if (start > 0) {
      results = results.sublist(start);
    }
    if (limit != null && limit < results.length) {
      results = results.sublist(0, limit);
    }

    return FormResult.ok(results);
  }

  @override
  Future<FormResult<List<FormTemplateVersion>>> getTemplateVersions({
    required String templateId,
  }) async {
    final versions = _versions[templateId] ?? [];
    return FormResult.ok(versions);
  }

  @override
  Future<FormResult<void>> deleteTemplate({
    required String templateId,
    String? version,
  }) async {
    if (!_templates.containsKey(templateId)) {
      return FormResult.fail(FormError(
        code: 'template.not_found',
        message: 'Template "$templateId" not found',
      ));
    }

    if (version != null) {
      // Remove specific version from history
      final versions = _versions[templateId];
      if (versions != null) {
        versions.removeWhere((v) => v.version == version);
      }

      // Only remove template if the current version matches
      final template = _templates[templateId]!;
      if (template.version == version) {
        _templates.remove(templateId);
      }
    } else {
      // Remove all
      _templates.remove(templateId);
      _versions.remove(templateId);
    }

    return const FormResult<void>(success: true);
  }
}
