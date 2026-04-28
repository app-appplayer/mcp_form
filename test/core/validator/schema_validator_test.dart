import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/core/validator/schema_validator.dart';
import 'package:test/test.dart';

FormDocument _makeDoc(Map<String, dynamic> data) {
  return FormDocument(
    documentId: 'doc-1',
    templateId: 'tpl-1',
    templateVersion: '1.0.0',
    metadata: FormDocumentMetadata(
      author: 'tester',
      createdAt: DateTime(2026),
    ),
    data: data,
  );
}

void main() {
  const validator = SchemaValidator();

  group('SchemaValidator - type checks', () {
    // TC-142: String type passes
    test('string value passes string type check', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'title', type: 'string'),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'title': 'Hello'}),
        schema: schema,
      );
      expect(issues, isEmpty);
    });

    // TC-143: Number type passes (int and double)
    test('numeric value passes number type check', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'count', type: 'number'),
      ]);
      expect(
        validator.validate(document: _makeDoc({'count': 42}), schema: schema),
        isEmpty,
      );
      expect(
        validator.validate(
          document: _makeDoc({'count': 3.14}),
          schema: schema,
        ),
        isEmpty,
      );
    });

    // TC-144: Date type passes
    test('valid ISO date string passes date type check', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'dob', type: 'date'),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'dob': '2026-01-15'}),
        schema: schema,
      );
      expect(issues, isEmpty);
    });

    // TC-145: Type mismatch - number given for string
    test('number value fails string type check', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'title', type: 'string'),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'title': 123}),
        schema: schema,
      );
      expect(issues.length, 1);
      expect(issues[0].code, 'schema.type_mismatch');
    });

    // TC-146: Type mismatch - string given for number
    test('string value fails number type check', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'count', type: 'number'),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'count': 'abc'}),
        schema: schema,
      );
      expect(issues.length, 1);
      expect(issues[0].code, 'schema.type_mismatch');
    });

    // TC-147: Invalid date format
    test('invalid date string fails date type check', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'dob', type: 'date'),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'dob': 'not-a-date'}),
        schema: schema,
      );
      expect(issues.length, 1);
      expect(issues[0].code, 'schema.type_mismatch');
    });
  });

  group('SchemaValidator - enum validation', () {
    // TC-149: Enum value in allowed values passes
    test('enum value in allowed list passes', () {
      final schema = FormSchema(fields: [
        FormSchemaField(
          name: 'color',
          type: 'enum',
          enumValues: ['red', 'green', 'blue'],
        ),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'color': 'red'}),
        schema: schema,
      );
      expect(issues, isEmpty);
    });

    // TC-150: Enum value not in allowed values
    test('enum value not in allowed list fails', () {
      final schema = FormSchema(fields: [
        FormSchemaField(
          name: 'color',
          type: 'enum',
          enumValues: ['red', 'green', 'blue'],
        ),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'color': 'yellow'}),
        schema: schema,
      );
      expect(issues.length, 1);
      expect(issues[0].code, 'schema.constraint_violated');
    });
  });

  group('SchemaValidator - required field checks', () {
    // TC-151: Required field present passes
    test('required field with value passes', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'name', type: 'string', required: true),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'name': 'Alice'}),
        schema: schema,
      );
      expect(issues, isEmpty);
    });

    // TC-152: Required field null fails
    test('required field with null value fails', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'name', type: 'string', required: true),
      ]);
      final issues = validator.validate(
        document: _makeDoc({}),
        schema: schema,
      );
      expect(issues.length, 1);
      expect(issues[0].code, 'schema.required_missing');
      expect(issues[0].severity, 'error');
    });

    // TC-153: Required string field with empty string fails
    test('required field with empty string fails', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'name', type: 'string', required: true),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'name': ''}),
        schema: schema,
      );
      expect(issues.length, 1);
      expect(issues[0].code, 'schema.required_missing');
    });

    // TC-154: Optional field with null is OK
    test('optional field with null value is valid', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'nickname', type: 'string'),
      ]);
      final issues = validator.validate(
        document: _makeDoc({}),
        schema: schema,
      );
      expect(issues, isEmpty);
    });
  });

  group('SchemaValidator - constraint checks', () {
    // TC-156: String maxLength constraint
    test('string exceeding maxLength fails', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'title', type: 'string', maxValue: 10),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'title': 'This is too long text'}),
        schema: schema,
      );
      expect(issues.length, 1);
      expect(issues[0].code, 'schema.constraint_violated');
      expect(issues[0].message, contains('exceeds maximum length'));
    });

    // TC-157: String minLength constraint
    test('string shorter than minLength fails', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'title', type: 'string', minValue: 5),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'title': 'Hi'}),
        schema: schema,
      );
      expect(issues.length, 1);
      expect(issues[0].code, 'schema.constraint_violated');
    });

    // TC-158: String within length bounds passes
    test('string within length bounds passes', () {
      final schema = FormSchema(fields: [
        FormSchemaField(
          name: 'title',
          type: 'string',
          minValue: 2,
          maxValue: 20,
        ),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'title': 'Hello'}),
        schema: schema,
      );
      expect(issues, isEmpty);
    });

    // TC-159: Number min constraint
    test('number below minimum fails', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'age', type: 'number', minValue: 0),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'age': -1}),
        schema: schema,
      );
      expect(issues.length, 1);
      expect(issues[0].code, 'schema.constraint_violated');
    });

    // TC-160: Number max constraint
    test('number above maximum fails', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'age', type: 'number', maxValue: 150),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'age': 200}),
        schema: schema,
      );
      expect(issues.length, 1);
      expect(issues[0].code, 'schema.constraint_violated');
    });

    // TC-161: Regex pattern validation
    test('string not matching pattern fails', () {
      final schema = FormSchema(fields: [
        FormSchemaField(
          name: 'email',
          type: 'string',
          pattern: r'^[\w.]+@[\w.]+\.\w+$',
        ),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'email': 'not-an-email'}),
        schema: schema,
      );
      expect(issues.length, 1);
      expect(issues[0].code, 'schema.constraint_violated');
    });

    // TC-162: Regex pattern matching passes
    test('string matching pattern passes', () {
      final schema = FormSchema(fields: [
        FormSchemaField(
          name: 'email',
          type: 'string',
          pattern: r'^[\w.]+@[\w.]+\.\w+$',
        ),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'email': 'test@example.com'}),
        schema: schema,
      );
      expect(issues, isEmpty);
    });

    // TC-163: Array length constraints
    test('array exceeding maxValue fails', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'items', type: 'array', maxValue: 3),
      ]);
      final issues = validator.validate(
        document: _makeDoc({
          'items': [1, 2, 3, 4],
        }),
        schema: schema,
      );
      expect(issues.length, 1);
      expect(issues[0].code, 'schema.constraint_violated');
    });

    test('array with too few items fails', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'items', type: 'array', minValue: 2),
      ]);
      final issues = validator.validate(
        document: _makeDoc({
          'items': [1],
        }),
        schema: schema,
      );
      expect(issues.length, 1);
      expect(issues[0].code, 'schema.constraint_violated');
    });
  });

  group('SchemaValidator - multi-error collection', () {
    // TC-164: Multiple errors collected in single pass
    test('collects all errors in single pass without fail-fast', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'name', type: 'string', required: true),
        FormSchemaField(name: 'age', type: 'number', required: true),
        FormSchemaField(name: 'email', type: 'string', required: true),
      ]);
      final issues = validator.validate(
        document: _makeDoc({}),
        schema: schema,
      );
      expect(issues.length, 3);
      expect(issues.every((i) => i.code == 'schema.required_missing'), isTrue);
    });
  });

  group('SchemaValidator - strict mode', () {
    test('strict mode rejects unknown fields', () {
      final schema = FormSchema(
        fields: [FormSchemaField(name: 'name', type: 'string')],
        strict: true,
      );
      final issues = validator.validate(
        document: _makeDoc({'name': 'Alice', 'unknown': 'value'}),
        schema: schema,
      );
      expect(issues.length, 1);
      expect(issues[0].code, 'schema.unknown_field');
    });

    test('non-strict mode allows unknown fields', () {
      final schema = FormSchema(
        fields: [FormSchemaField(name: 'name', type: 'string')],
      );
      final issues = validator.validate(
        document: _makeDoc({'name': 'Alice', 'extra': 'value'}),
        schema: schema,
      );
      expect(issues, isEmpty);
    });
  });

  group('SchemaValidator - object type', () {
    test('map value passes object type check', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'config', type: 'object'),
      ]);
      final issues = validator.validate(
        document: _makeDoc({
          'config': {'key': 'value'},
        }),
        schema: schema,
      );
      expect(issues, isEmpty);
    });

    test('non-map value fails object type check', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'config', type: 'object'),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'config': 'not-a-map'}),
        schema: schema,
      );
      expect(issues.length, 1);
      expect(issues[0].code, 'schema.type_mismatch');
    });
  });

  group('SchemaValidator - isEmpty edge cases', () {
    // Coverage: _isEmpty for List type (required field with empty list)
    test('required field with empty list fails as missing', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'items', type: 'array', required: true),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'items': []}),
        schema: schema,
      );
      expect(issues.length, 1);
      expect(issues[0].code, 'schema.required_missing');
    });

    // Coverage: _isEmpty for Map type (required field with empty map)
    test('required field with empty map fails as missing', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'config', type: 'object', required: true),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'config': {}}),
        schema: schema,
      );
      expect(issues.length, 1);
      expect(issues[0].code, 'schema.required_missing');
    });
  });

  group('SchemaValidator - invalid regex pattern', () {
    // Coverage: catch block for invalid regex pattern (lines 185,187,188)
    test('invalid regex pattern emits warning and skips constraint', () {
      final schema = FormSchema(fields: [
        FormSchemaField(
          name: 'code',
          type: 'string',
          pattern: '[invalid regex((',
        ),
      ]);
      final issues = validator.validate(
        document: _makeDoc({'code': 'test'}),
        schema: schema,
      );
      expect(issues.length, 1);
      expect(issues[0].severity, 'warning');
      expect(issues[0].code, 'schema.constraint_violated');
      expect(issues[0].message, contains('Invalid regex pattern'));
    });
  });
}
