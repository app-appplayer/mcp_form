import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/core/schema/json_schema_export.dart';
import 'package:test/test.dart';

/// C1 — Template → JSON Schema (draft 2020-12). An LLM constrained to this
/// schema fills only the fields the template declares, with the right types and
/// constraints, so the produced data is guaranteed valid for the form.
void main() {
  FormSchema schema(List<FormSchemaField> fields, {bool strict = false}) =>
      FormSchema(fields: fields, strict: strict);

  test('object schema with draft 2020-12 and field properties', () {
    final js = formSchemaToJsonSchema(
      schema([
        FormSchemaField(name: 'title', type: 'string', required: true),
        FormSchemaField(name: 'count', type: 'number'),
      ]),
      title: 'Report',
    );
    expect(js[r'$schema'], contains('2020-12'));
    expect(js['type'], 'object');
    expect(js['title'], 'Report');
    final props = js['properties'] as Map<String, dynamic>;
    expect((props['title'] as Map)['type'], 'string');
    expect((props['count'] as Map)['type'], 'number');
  });

  test('required list collects only required fields', () {
    final js = formSchemaToJsonSchema(schema([
      FormSchemaField(name: 'a', type: 'string', required: true),
      FormSchemaField(name: 'b', type: 'string'),
      FormSchemaField(name: 'c', type: 'number', required: true),
    ]));
    expect(js['required'], containsAll(['a', 'c']));
    expect((js['required'] as List).contains('b'), isFalse);
  });

  test('strict schema forbids extra properties', () {
    final loose = formSchemaToJsonSchema(schema([]));
    final strict = formSchemaToJsonSchema(schema([], strict: true));
    expect(loose['additionalProperties'], isTrue);
    expect(strict['additionalProperties'], isFalse);
  });

  test('type mapping: date / integer / boolean', () {
    final props = formSchemaToJsonSchema(schema([
      FormSchemaField(name: 'when', type: 'date'),
      FormSchemaField(name: 'n', type: 'integer'),
      FormSchemaField(name: 'ok', type: 'boolean'),
    ]))['properties'] as Map<String, dynamic>;
    expect((props['when'] as Map)['type'], 'string');
    expect((props['when'] as Map)['format'], 'date');
    expect((props['n'] as Map)['type'], 'integer');
    expect((props['ok'] as Map)['type'], 'boolean');
  });

  test('constraints: enum, pattern, numeric bounds, format, description', () {
    final props = formSchemaToJsonSchema(schema([
      FormSchemaField(
          name: 'status',
          type: 'enum',
          enumValues: ['draft', 'final'],
          description: 'Doc status'),
      FormSchemaField(name: 'code', type: 'string', pattern: r'^\d{3}$'),
      FormSchemaField(
          name: 'score', type: 'number', minValue: 0, maxValue: 100),
      FormSchemaField(name: 'email', type: 'string', format: 'email'),
    ]))['properties'] as Map<String, dynamic>;

    expect((props['status'] as Map)['enum'], ['draft', 'final']);
    expect((props['status'] as Map)['description'], 'Doc status');
    expect((props['code'] as Map)['pattern'], r'^\d{3}$');
    expect((props['score'] as Map)['minimum'], 0);
    expect((props['score'] as Map)['maximum'], 100);
    expect((props['email'] as Map)['format'], 'email');
  });

  test('sensitive field annotated writeOnly; placeholder → examples', () {
    final props = formSchemaToJsonSchema(schema([
      FormSchemaField(name: 'ssn', type: 'string', sensitive: true),
      FormSchemaField(name: 'name', type: 'string', placeholder: 'Jane Doe'),
    ]))['properties'] as Map<String, dynamic>;
    expect((props['ssn'] as Map)['writeOnly'], isTrue);
    expect((props['name'] as Map)['examples'], ['Jane Doe']);
  });

  test('templateToJsonSchema uses the template name as title', () {
    final layout = FormLayoutPolicy(
      pageSize: const FormPageSize(size: 'A4', width: 210, height: 297),
      margins: const FormMargins(top: 20, right: 20, bottom: 20, left: 20),
      fontPolicy: const FormFontPolicy(
          defaultFont: 'x',
          defaultSize: 12,
          headingSize: 18,
          bodySize: 12,
          minSize: 8),
    );
    final t = FormTemplate(
      templateId: 't',
      version: '1.0.0',
      name: 'Monthly Report',
      schema: schema([FormSchemaField(name: 'x', type: 'string')]),
      layoutPolicy: layout,
    );
    expect(templateToJsonSchema(t)['title'], 'Monthly Report');
  });
}
