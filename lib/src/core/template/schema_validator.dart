import 'package:mcp_bundle/mcp_bundle.dart';

import 'field_type.dart';

/// Validates the structural integrity of a [FormSchema].
///
/// This validates the schema definition itself, not document data.
/// Document-level validation is performed by MOD-CORE-003 (Validator).
///
/// Returns a list of validation errors. Empty list means valid.
///
/// Validation rules:
/// 1. Schema must have at least one field
/// 2. Field names must be unique
/// 3. Enum fields must have enumValues
/// 4. Constraint consistency (min <= max)
/// 5. Section IDs must be unique (when sections provided)
/// 6. Valid regex patterns
List<FormError> validateSchema(
  FormSchema schema, {
  List<FormSection>? sections,
}) {
  final errors = <FormError>[];

  // Rule 1: Schema must have at least one field
  if (schema.fields.isEmpty) {
    errors.add(FormError(
      code: 'template.invalid_schema',
      message: 'Schema must define at least one field',
      path: '/schema/fields',
    ));
  }

  // Rule 2: Field names must be unique
  final fieldNames = <String>{};
  for (var i = 0; i < schema.fields.length; i++) {
    final field = schema.fields[i];
    if (!fieldNames.add(field.name)) {
      errors.add(FormError(
        code: 'template.invalid_schema',
        message: 'Duplicate field name: "${field.name}"',
        path: '/schema/fields/$i',
      ));
    }
  }

  // Rule 3: Enum fields must have enumValues
  for (var i = 0; i < schema.fields.length; i++) {
    final field = schema.fields[i];
    final fieldType = FieldType.fromString(field.type);
    if (fieldType == FieldType.enumType) {
      if (field.enumValues == null || field.enumValues!.isEmpty) {
        errors.add(FormError(
          code: 'template.invalid_schema',
          message: 'Enum field "${field.name}" must define enumValues',
          path: '/schema/fields/$i/enumValues',
        ));
      }
    }
  }

  // Rule 4: Constraint consistency (min <= max)
  for (var i = 0; i < schema.fields.length; i++) {
    final field = schema.fields[i];
    final minVal = field.minValue;
    final maxVal = field.maxValue;
    if (minVal != null && maxVal != null) {
      if (minVal is num && maxVal is num && minVal > maxVal) {
        errors.add(FormError(
          code: 'template.invalid_schema',
          message: 'Field "${field.name}": minValue ($minVal) > maxValue ($maxVal)',
          path: '/schema/fields/$i',
        ));
      }
    }
  }

  // Rule 5: Section IDs must be unique (when sections provided)
  if (sections != null) {
    final sectionIds = <String>{};
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      if (!sectionIds.add(section.sectionId)) {
        errors.add(FormError(
          code: 'template.invalid_schema',
          message: 'Duplicate section ID: "${section.sectionId}"',
          path: '/schema/sections/$i',
        ));
      }
    }
  }

  // Rule 6: Valid regex patterns
  for (var i = 0; i < schema.fields.length; i++) {
    final field = schema.fields[i];
    final regex = field.pattern;
    if (regex != null) {
      try {
        RegExp(regex);
      } catch (_) {
        errors.add(FormError(
          code: 'template.invalid_schema',
          message: 'Field "${field.name}" has invalid regex pattern: "$regex"',
          path: '/schema/fields/$i/pattern',
        ));
      }
    }
  }

  return errors;
}
