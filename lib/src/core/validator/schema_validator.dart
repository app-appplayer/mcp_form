import 'package:mcp_bundle/mcp_bundle.dart';

import '../template/field_type.dart';

/// Validates a [FormDocument]'s data against a [FormSchema].
///
/// Checks type correctness, required field presence, and constraint
/// compliance. Collects all errors in a single pass (never fail-fast).
class SchemaValidator {
  const SchemaValidator();

  /// Validate the entire [document] against the given [schema].
  ///
  /// Returns a list of [FormValidationIssue] entries.
  /// Empty list means the document passes all schema checks.
  List<FormValidationIssue> validate({
    required FormDocument document,
    required FormSchema schema,
  }) {
    final issues = <FormValidationIssue>[];

    // Validate document data against schema fields
    for (var i = 0; i < schema.fields.length; i++) {
      final field = schema.fields[i];
      final value = document.data[field.name];

      issues.addAll(_validateField(
        fieldName: field.name,
        value: value,
        field: field,
        path: '/data/${field.name}',
      ));
    }

    // Check for unknown fields in strict mode
    if (schema.strict) {
      final knownNames = schema.fields.map((f) => f.name).toSet();
      for (final key in document.data.keys) {
        if (!knownNames.contains(key)) {
          issues.add(FormValidationIssue(
            code: 'schema.unknown_field',
            message: 'Field "$key" is not defined in schema',
            path: '/data/$key',
            severity: 'error',
          ));
        }
      }
    }

    return issues;
  }

  List<FormValidationIssue> _validateField({
    required String fieldName,
    required dynamic value,
    required FormSchemaField field,
    required String path,
  }) {
    final issues = <FormValidationIssue>[];

    // Required check
    if (field.required && (value == null || _isEmpty(value))) {
      issues.add(FormValidationIssue(
        code: 'schema.required_missing',
        message: 'Required field "$fieldName" is missing',
        path: path,
        severity: 'error',
      ));
      return issues;
    }

    // Skip further checks if value is null (optional field)
    if (value == null) return issues;

    // Type check
    final fieldType = FieldType.fromString(field.type);
    final typeError = _checkType(
      value: value,
      expectedType: fieldType,
      path: path,
      fieldName: fieldName,
    );
    if (typeError != null) {
      issues.add(typeError);
      return issues;
    }

    // Constraint checks
    issues.addAll(_checkConstraints(
      value: value,
      field: field,
      fieldType: fieldType,
      path: path,
      fieldName: fieldName,
    ));

    return issues;
  }

  bool _isEmpty(dynamic value) {
    if (value is String) return value.isEmpty;
    if (value is List) return value.isEmpty;
    if (value is Map) return value.isEmpty;
    return false;
  }

  FormValidationIssue? _checkType({
    required dynamic value,
    required FieldType expectedType,
    required String path,
    required String fieldName,
  }) {
    final isValid = switch (expectedType) {
      FieldType.string => value is String,
      FieldType.number => value is num,
      FieldType.date => value is String && DateTime.tryParse(value) != null,
      FieldType.enumType => value is String,
      FieldType.object => value is Map,
      FieldType.array => value is List,
    };

    if (!isValid) {
      return FormValidationIssue(
        code: 'schema.type_mismatch',
        message:
            'Expected ${expectedType.name} for "$fieldName", '
            'got ${value.runtimeType}',
        path: path,
        severity: 'error',
      );
    }
    return null;
  }

  List<FormValidationIssue> _checkConstraints({
    required dynamic value,
    required FormSchemaField field,
    required FieldType fieldType,
    required String path,
    required String fieldName,
  }) {
    final issues = <FormValidationIssue>[];

    switch (fieldType) {
      case FieldType.string:
        final str = value as String;
        if (field.minValue != null && field.minValue is int) {
          if (str.length < (field.minValue as int)) {
            issues.add(FormValidationIssue(
              code: 'schema.constraint_violated',
              message:
                  'Field "$fieldName" is shorter than minimum length '
                  '${field.minValue} (got ${str.length})',
              path: path,
              severity: 'error',
            ));
          }
        }
        if (field.maxValue != null && field.maxValue is int) {
          if (str.length > (field.maxValue as int)) {
            issues.add(FormValidationIssue(
              code: 'schema.constraint_violated',
              message:
                  'Field "$fieldName" exceeds maximum length '
                  '${field.maxValue} (got ${str.length})',
              path: path,
              severity: 'error',
            ));
          }
        }
        if (field.pattern != null) {
          try {
            final regex = RegExp(field.pattern!);
            if (!regex.hasMatch(str)) {
              issues.add(FormValidationIssue(
                code: 'schema.constraint_violated',
                message:
                    'Field "$fieldName" does not match pattern "${field.pattern}"',
                path: path,
                severity: 'error',
              ));
            }
          } catch (_) {
            // Invalid regex pattern - emit warning and skip constraint
            issues.add(FormValidationIssue(
              code: 'schema.constraint_violated',
              message:
                  'Invalid regex pattern "${field.pattern}" for '
                  'field "$fieldName" - constraint skipped',
              path: path,
              severity: 'warning',
            ));
          }
        }

      case FieldType.number:
        final num val = value as num;
        if (field.minValue != null && field.minValue is num) {
          if (val < (field.minValue as num)) {
            issues.add(FormValidationIssue(
              code: 'schema.constraint_violated',
              message:
                  'Field "$fieldName" is below minimum ${field.minValue} '
                  '(got $val)',
              path: path,
              severity: 'error',
            ));
          }
        }
        if (field.maxValue != null && field.maxValue is num) {
          if (val > (field.maxValue as num)) {
            issues.add(FormValidationIssue(
              code: 'schema.constraint_violated',
              message:
                  'Field "$fieldName" exceeds maximum ${field.maxValue} '
                  '(got $val)',
              path: path,
              severity: 'error',
            ));
          }
        }

      case FieldType.enumType:
        if (field.enumValues != null) {
          if (!field.enumValues!.contains(value)) {
            issues.add(FormValidationIssue(
              code: 'schema.constraint_violated',
              message:
                  'Field "$fieldName" value "$value" is not in '
                  'allowed values: ${field.enumValues}',
              path: path,
              severity: 'error',
            ));
          }
        }

      case FieldType.array:
        final list = value as List;
        if (field.minValue != null && field.minValue is num) {
          if (list.length < (field.minValue as num)) {
            issues.add(FormValidationIssue(
              code: 'schema.constraint_violated',
              message:
                  'Field "$fieldName" has too few items: '
                  '${list.length} (min: ${field.minValue})',
              path: path,
              severity: 'error',
            ));
          }
        }
        if (field.maxValue != null && field.maxValue is num) {
          if (list.length > (field.maxValue as num)) {
            issues.add(FormValidationIssue(
              code: 'schema.constraint_violated',
              message:
                  'Field "$fieldName" has too many items: '
                  '${list.length} (max: ${field.maxValue})',
              path: path,
              severity: 'error',
            ));
          }
        }

      case FieldType.date:
      case FieldType.object:
        break;
    }

    return issues;
  }
}
