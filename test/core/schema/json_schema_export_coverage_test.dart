import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/core/schema/json_schema_export.dart';
import 'package:test/test.dart';

/// Coverage tests for json_schema_export.dart branches not reached by the
/// primary suite:
///   - description parameter (line 37)
///   - 'object' field type (line 73)
///   - 'array' field type (line 75)
///   - 'datetime' / 'date-time' field type (lines 81-82)
void main() {
  FormSchema schema(List<FormSchemaField> fields) =>
      FormSchema(fields: fields);

  group('formSchemaToJsonSchema — description parameter', () {
    test('description is emitted when provided', () {
      final js = formSchemaToJsonSchema(
        schema([FormSchemaField(name: 'f', type: 'string')]),
        description: 'Monthly budget report schema',
      );
      expect(js['description'], 'Monthly budget report schema');
    });

    test('description is absent when not provided', () {
      final js = formSchemaToJsonSchema(
        schema([FormSchemaField(name: 'f', type: 'string')]),
      );
      expect(js.containsKey('description'), isFalse);
    });

    test('title and description can be combined', () {
      final js = formSchemaToJsonSchema(
        schema([]),
        title: 'My Form',
        description: 'A test form',
      );
      expect(js['title'], 'My Form');
      expect(js['description'], 'A test form');
    });
  });

  group('formSchemaToJsonSchema — object and array field types', () {
    test('object field maps to JSON Schema object type', () {
      final props = formSchemaToJsonSchema(schema([
        FormSchemaField(name: 'meta', type: 'object'),
      ]))['properties'] as Map<String, dynamic>;
      expect((props['meta'] as Map)['type'], 'object');
    });

    test('array field maps to JSON Schema array type', () {
      final props = formSchemaToJsonSchema(schema([
        FormSchemaField(name: 'tags', type: 'array'),
      ]))['properties'] as Map<String, dynamic>;
      expect((props['tags'] as Map)['type'], 'array');
    });

    test('both object and array types in one schema', () {
      final props = formSchemaToJsonSchema(schema([
        FormSchemaField(name: 'data', type: 'object'),
        FormSchemaField(name: 'items', type: 'array'),
      ]))['properties'] as Map<String, dynamic>;
      expect((props['data'] as Map)['type'], 'object');
      expect((props['items'] as Map)['type'], 'array');
    });
  });

  group('formSchemaToJsonSchema — datetime field types', () {
    test('"datetime" type maps to string with date-time format', () {
      final props = formSchemaToJsonSchema(schema([
        FormSchemaField(name: 'ts', type: 'datetime'),
      ]))['properties'] as Map<String, dynamic>;
      expect((props['ts'] as Map)['type'], 'string');
      expect((props['ts'] as Map)['format'], 'date-time');
    });

    test('"date-time" type maps to string with date-time format', () {
      final props = formSchemaToJsonSchema(schema([
        FormSchemaField(name: 'ts', type: 'date-time'),
      ]))['properties'] as Map<String, dynamic>;
      expect((props['ts'] as Map)['type'], 'string');
      expect((props['ts'] as Map)['format'], 'date-time');
    });
  });
}
