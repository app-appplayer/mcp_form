/// Supported data types for schema fields.
///
/// Maps to the string-based `type` field on [FormSchemaField] from mcp_bundle.
/// Each type determines what values are accepted during validation and
/// which constraints are applicable.
enum FieldType {
  /// Text/string value.
  /// Applicable constraints: minLength, maxLength, regex (pattern).
  string,

  /// Numeric value (int or double).
  /// Applicable constraints: min, max.
  number,

  /// Date/datetime value (ISO 8601 string or DateTime).
  /// Applicable constraints: min (earliest), max (latest).
  date,

  /// Enumeration value (one of a predefined set).
  /// Applicable constraints: enumValues (required for this type).
  enumType,

  /// Nested object value (Map<String, dynamic>).
  object,

  /// Array/list value.
  /// Applicable constraints: min (minItems), max (maxItems).
  array;

  /// Parse a [FieldType] from its string name.
  ///
  /// Returns [FieldType.string] if the value does not match any known type.
  static FieldType fromString(String value) {
    return switch (value) {
      'string' => FieldType.string,
      'number' => FieldType.number,
      'date' => FieldType.date,
      'enumType' || 'enum' => FieldType.enumType,
      'object' => FieldType.object,
      'array' => FieldType.array,
      _ => FieldType.string,
    };
  }
}
