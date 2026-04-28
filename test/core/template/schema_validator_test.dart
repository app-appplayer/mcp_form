import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/mcp_form.dart';
import 'package:test/test.dart';

void main() {
  group('validateSchema', () {
    // TC-025: Rule 1 - empty fields list rejected
    test('rejects schema with empty fields list', () {
      const schema = FormSchema(fields: []);
      final errors = validateSchema(schema);

      expect(errors, hasLength(1));
      expect(errors.first.code, 'template.invalid_schema');
      expect(errors.first.path, '/schema/fields');
    });

    // TC-026: Rule 2 - duplicate field names rejected
    test('rejects duplicate field names', () {
      final schema = FormSchema(
        fields: [
          FormSchemaField(name: 'title', type: 'string'),
          FormSchemaField(name: 'title', type: 'number'),
        ],
      );
      final errors = validateSchema(schema);

      expect(errors.any((e) => e.message.contains('Duplicate field name')),
          isTrue);
    });

    // TC-027: Rule 3 - enum field without enumValues rejected
    test('rejects enum field without enumValues', () {
      final schema = FormSchema(
        fields: [
          FormSchemaField(name: 'status', type: 'enumType'),
        ],
      );
      final errors = validateSchema(schema);

      expect(
          errors.any((e) => e.message.contains('must define enumValues')),
          isTrue);
    });

    test('accepts enum field with enumValues', () {
      final schema = FormSchema(
        fields: [
          FormSchemaField(
            name: 'status',
            type: 'enumType',
            enumValues: const ['active', 'inactive'],
          ),
        ],
      );
      final errors = validateSchema(schema);

      expect(errors.where((e) => e.message.contains('enumValues')), isEmpty);
    });

    // TC-028: Rule 4 - min > max constraint rejected
    test('rejects min > max constraint', () {
      final schema = FormSchema(
        fields: [
          FormSchemaField(
            name: 'score',
            type: 'number',
            minValue: 100,
            maxValue: 10,
          ),
        ],
      );
      final errors = validateSchema(schema);

      expect(errors.any((e) => e.message.contains('minValue')), isTrue);
    });

    test('accepts valid min <= max constraint', () {
      final schema = FormSchema(
        fields: [
          FormSchemaField(
            name: 'score',
            type: 'number',
            minValue: 0,
            maxValue: 100,
          ),
        ],
      );
      final errors = validateSchema(schema);

      expect(
          errors.where((e) => e.message.contains('minValue')),
          isEmpty);
    });

    // TC-029: Rule 5 - duplicate section IDs rejected
    test('rejects duplicate section IDs', () {
      final schema = FormSchema(
        fields: [
          FormSchemaField(name: 'title', type: 'string'),
        ],
      );
      final sections = [
        const FormSection(sectionId: 'header', index: 0),
        const FormSection(sectionId: 'header', index: 1),
      ];
      final errors = validateSchema(schema, sections: sections);

      expect(errors.any((e) => e.message.contains('Duplicate section ID')),
          isTrue);
    });

    // Rule 6: invalid regex rejected
    test('rejects invalid regex pattern', () {
      final schema = FormSchema(
        fields: [
          FormSchemaField(
            name: 'code',
            type: 'string',
            pattern: '[invalid(regex',
          ),
        ],
      );
      final errors = validateSchema(schema);

      expect(
          errors.any((e) => e.message.contains('invalid regex pattern')),
          isTrue);
    });

    test('accepts valid regex pattern', () {
      final schema = FormSchema(
        fields: [
          FormSchemaField(
            name: 'code',
            type: 'string',
            pattern: r'^[A-Za-z0-9]+$',
          ),
        ],
      );
      final errors = validateSchema(schema);

      expect(
          errors.where((e) => e.path?.contains('pattern') ?? false), isEmpty);
    });

    // Valid schema passes all rules
    test('valid schema returns empty errors', () {
      final schema = FormSchema(
        fields: [
          FormSchemaField(name: 'title', type: 'string'),
          FormSchemaField(
            name: 'score',
            type: 'number',
            minValue: 0,
            maxValue: 100,
          ),
          FormSchemaField(
            name: 'status',
            type: 'enumType',
            enumValues: const ['pass', 'fail'],
          ),
        ],
      );
      final errors = validateSchema(schema);

      expect(errors, isEmpty);
    });
  });
}
