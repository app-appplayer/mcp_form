import 'package:mcp_bundle/mcp_bundle.dart';

/// Result of an auto-fix operation.
class AutoFixResult {
  const AutoFixResult({
    required this.document,
    this.fixes = const [],
  });

  /// The document after fixes were applied.
  final FormDocument document;

  /// List of fixes that were applied.
  final List<FormAutoFixAction> fixes;
}

/// Engine that applies automatic corrections to fixable validation issues.
///
/// Supports strategies:
/// - Text truncation for length violations
/// - Default value insertion for missing required fields
class AutoFixEngine {
  const AutoFixEngine();

  /// Apply auto-fixes to the [document] for the given [issues].
  ///
  /// Only fixable issues are corrected. Non-fixable issues remain
  /// in the validation result for the caller to handle.
  AutoFixResult applyFixes({
    required FormDocument document,
    required List<FormValidationIssue> issues,
    required FormSchema schema,
  }) {
    final fixes = <FormAutoFixAction>[];
    var data = Map<String, dynamic>.from(document.data);

    for (final issue in issues) {
      final fix = _tryFix(issue, data, schema);
      if (fix != null) {
        fixes.add(fix.action);
        data = fix.updatedData;
      }
    }

    if (fixes.isEmpty) {
      return AutoFixResult(document: document, fixes: fixes);
    }

    final fixedDocument = FormDocument(
      documentId: document.documentId,
      templateId: document.templateId,
      templateVersion: document.templateVersion,
      metadata: FormDocumentMetadata(
        author: document.metadata.author,
        createdAt: document.metadata.createdAt,
        modifiedAt: DateTime.now(),
        publishedAt: document.metadata.publishedAt,
        dataSource: document.metadata.dataSource,
        engineVersion: document.metadata.engineVersion,
      ),
      status: document.status,
      version: document.version,
      sections: document.sections,
      data: data,
      bindings: document.bindings,
      validationIssues: document.validationIssues,
    );

    return AutoFixResult(document: fixedDocument, fixes: fixes);
  }

  _FixAttempt? _tryFix(
    FormValidationIssue issue,
    Map<String, dynamic> data,
    FormSchema schema,
  ) {
    switch (issue.code) {
      case 'schema.required_missing':
        return _trySetDefault(issue, data, schema);
      case 'schema.constraint_violated':
        return _tryTruncate(issue, data, schema);
      default:
        return null;
    }
  }

  _FixAttempt? _trySetDefault(
    FormValidationIssue issue,
    Map<String, dynamic> data,
    FormSchema schema,
  ) {
    final fieldName = _extractFieldName(issue.path);
    if (fieldName == null) return null;

    final field = schema.fields.cast<FormSchemaField?>().firstWhere(
          (f) => f?.name == fieldName,
          orElse: () => null,
        );
    if (field == null) return null;

    // Set default value based on field type
    final dynamic defaultValue = switch (field.type) {
      'string' => '',
      'number' => 0,
      'date' => DateTime.now().toIso8601String(),
      _ => null,
    };

    if (defaultValue == null) return null;

    final updatedData = Map<String, dynamic>.from(data);
    updatedData[fieldName] = defaultValue;

    return _FixAttempt(
      action: FormAutoFixAction(
        action: 'set_default',
        path: issue.path,
        description:
            'Set default value for required field "$fieldName"',
      ),
      updatedData: updatedData,
    );
  }

  _FixAttempt? _tryTruncate(
    FormValidationIssue issue,
    Map<String, dynamic> data,
    FormSchema schema,
  ) {
    if (!issue.message.contains('exceeds maximum length')) return null;

    final fieldName = _extractFieldName(issue.path);
    if (fieldName == null) return null;

    final field = schema.fields.cast<FormSchemaField?>().firstWhere(
          (f) => f?.name == fieldName,
          orElse: () => null,
        );
    if (field == null) return null;

    final value = data[fieldName];
    if (value is! String) return null;
    if (field.maxValue is! int) return null;

    final maxLen = field.maxValue as int;
    final truncated = value.substring(0, maxLen);
    final updatedData = Map<String, dynamic>.from(data);
    updatedData[fieldName] = truncated;

    return _FixAttempt(
      action: FormAutoFixAction(
        action: 'truncate',
        path: issue.path,
        description:
            'Truncated field "$fieldName" to $maxLen characters',
      ),
      updatedData: updatedData,
    );
  }

  String? _extractFieldName(String path) {
    // Path format: /data/fieldName
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2 && segments[0] == 'data') {
      return segments[1];
    }
    return null;
  }
}

class _FixAttempt {
  const _FixAttempt({required this.action, required this.updatedData});

  final FormAutoFixAction action;
  final Map<String, dynamic> updatedData;
}
