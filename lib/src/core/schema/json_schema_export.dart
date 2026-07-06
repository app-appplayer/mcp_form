/// Derive a JSON Schema (draft 2020-12) from a form's [FormSchema].
///
/// This is the LLM-native differentiator: an agent asked to fill a template can
/// be constrained to the returned schema (structured output / tool-call
/// `input_schema`), so the data it produces is *guaranteed* to satisfy the
/// form's field types, requiredness and constraints — the template stays fixed
/// and only validated content flows in. The schema describes the shape of the
/// `FormDocument.data` map (keyed by field name) that the binding engine fills.
///
/// `strict` schemas emit `additionalProperties: false` so the LLM cannot invent
/// fields the template does not declare.
library;

import 'package:mcp_bundle/mcp_bundle.dart';

import 'capacity.dart';

/// JSON Schema for the data map of a template's [schema].
Map<String, dynamic> formSchemaToJsonSchema(
  FormSchema schema, {
  String? title,
  String? description,
  Map<String, FieldCapacity>? capacities,
}) {
  final properties = <String, dynamic>{};
  final required = <String>[];

  for (final field in schema.fields) {
    properties[field.name] = _fieldToProperty(field, capacities?[field.name]);
    if (field.required) required.add(field.name);
  }

  return {
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
    'type': 'object',
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    'properties': properties,
    if (required.isNotEmpty) 'required': required,
    'additionalProperties': !schema.strict,
  };
}

/// Convenience: derive the schema from a whole [template] (uses its name and,
/// by default, folds in per-field box capacity as `maxLength` so the LLM writes
/// to fit). Pass `withCapacity: false` to omit the capacity feed-forward.
Map<String, dynamic> templateToJsonSchema(
  FormTemplate template, {
  bool withCapacity = true,
}) =>
    formSchemaToJsonSchema(
      template.schema,
      title: template.name,
      capacities: withCapacity ? estimateFieldCapacities(template) : null,
    );

Map<String, dynamic> _fieldToProperty(
    FormSchemaField field, FieldCapacity? capacity) {
  final prop = <String, dynamic>{};

  // Base type. `date` / `datetime` map to a string with a JSON Schema format
  // unless the field already declares an explicit format.
  switch (field.type) {
    case 'number':
      prop['type'] = 'number';
    case 'integer':
    case 'int':
      prop['type'] = 'integer';
    case 'boolean':
    case 'bool':
      prop['type'] = 'boolean';
    case 'object':
      prop['type'] = 'object';
    case 'array':
      prop['type'] = 'array';
    case 'date':
      prop['type'] = 'string';
      prop['format'] = 'date';
    case 'datetime':
    case 'date-time':
      prop['type'] = 'string';
      prop['format'] = 'date-time';
    case 'enum':
    case 'enumType':
      // Type inferred from the enum members (default string).
      prop['type'] =
          field.enumValues != null && field.enumValues!.every((e) => e is num)
              ? 'number'
              : 'string';
    default:
      prop['type'] = 'string';
  }

  // An explicit field format (email / url / date-time …) wins.
  if (field.format != null) prop['format'] = field.format;

  final desc = field.description ?? field.label;
  if (desc != null) prop['description'] = desc;
  if (field.placeholder != null) prop['examples'] = [field.placeholder];

  if (field.enumValues != null && field.enumValues!.isNotEmpty) {
    prop['enum'] = field.enumValues;
  }
  if (field.pattern != null) prop['pattern'] = field.pattern;

  // Numeric bounds map to minimum / maximum.
  final isNumeric = prop['type'] == 'number' || prop['type'] == 'integer';
  if (isNumeric) {
    final min = _asNum(field.minValue);
    final max = _asNum(field.maxValue);
    if (min != null) prop['minimum'] = min;
    if (max != null) prop['maximum'] = max;
  }

  // Annotate sensitive fields so consumers can mask them.
  if (field.sensitive) prop['writeOnly'] = true;

  // Capacity feed-forward: a fixed-height box caps how much text fits. For text
  // fields, surface it as `maxLength` and note it in the description so the LLM
  // sizes its answer to the space.
  if (capacity != null && capacity.maxChars > 0 && prop['type'] == 'string') {
    prop['maxLength'] = capacity.maxChars;
    final note = 'fits about ${capacity.maxChars} characters '
        '(${capacity.lines} lines)';
    prop['description'] =
        prop.containsKey('description') ? '${prop['description']} — $note' : note;
  }

  return prop;
}

num? _asNum(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}
