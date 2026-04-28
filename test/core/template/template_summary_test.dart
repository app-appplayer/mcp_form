import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/mcp_form.dart';
import 'package:test/test.dart';

FormTemplate _makeTemplate({
  String id = 'tpl-1',
  String version = '1.0.0',
  String name = 'Test Template',
  String? description,
  List<FormSchemaField> fields = const [],
  List<FormSection> sections = const [],
  List<String>? components,
}) {
  return FormTemplate(
    templateId: id,
    version: version,
    name: name,
    description: description,
    schema: FormSchema(fields: fields),
    layoutPolicy: const FormLayoutPolicy(
      pageSize: FormPageSize(size: 'A4', width: 210, height: 297),
      margins: FormMargins(top: 20, right: 20, bottom: 20, left: 20),
      fontPolicy: FormFontPolicy(
        defaultFont: 'sans-serif',
        defaultSize: 12,
        headingSize: 18,
        bodySize: 12,
        minSize: 8,
      ),
    ),
    defaultSections: sections,
    components: components,
  );
}

void main() {
  group('TemplateSummary', () {
    test('constructs with required fields', () {
      final now = DateTime.now();
      final summary = TemplateSummary(
        templateId: 'tpl-1',
        version: '1.0.0',
        name: 'Invoice',
        fieldCount: 5,
        sectionCount: 3,
        createdAt: now,
        updatedAt: now,
      );

      expect(summary.templateId, 'tpl-1');
      expect(summary.version, '1.0.0');
      expect(summary.name, 'Invoice');
      expect(summary.description, isNull);
      expect(summary.fieldCount, 5);
      expect(summary.sectionCount, 3);
      expect(summary.componentCount, 0);
    });

    test('constructs with optional fields', () {
      final now = DateTime.now();
      final summary = TemplateSummary(
        templateId: 'tpl-2',
        version: '2.0.0',
        name: 'Report',
        description: 'A report template',
        fieldCount: 10,
        sectionCount: 5,
        componentCount: 2,
        createdAt: now,
        updatedAt: now,
      );

      expect(summary.description, 'A report template');
      expect(summary.componentCount, 2);
    });
  });

  group('TemplateProjection', () {
    test('toSummary extracts correct field count', () {
      final template = _makeTemplate(
        fields: [
          FormSchemaField(name: 'name', type: 'string'),
          FormSchemaField(name: 'age', type: 'number'),
          FormSchemaField(name: 'email', type: 'string'),
        ],
      );

      final summary = template.toSummary();
      expect(summary.fieldCount, 3);
    });

    test('toSummary extracts correct section count', () {
      final template = _makeTemplate(
        sections: const [
          FormSection(sectionId: 's1', index: 0),
          FormSection(sectionId: 's2', index: 1),
        ],
      );

      final summary = template.toSummary();
      expect(summary.sectionCount, 2);
    });

    test('toSummary extracts correct component count', () {
      final template = _makeTemplate(
        components: ['chart-lib', 'icon-set'],
      );

      final summary = template.toSummary();
      expect(summary.componentCount, 2);
    });

    test('toSummary handles null components as zero', () {
      final template = _makeTemplate();
      final summary = template.toSummary();
      expect(summary.componentCount, 0);
    });

    test('toSummary preserves identity fields', () {
      final template = _makeTemplate(
        id: 'tpl-99',
        version: '3.2.1',
        name: 'Equipment Inspection',
        description: 'Detailed inspection form',
      );

      final summary = template.toSummary();
      expect(summary.templateId, 'tpl-99');
      expect(summary.version, '3.2.1');
      expect(summary.name, 'Equipment Inspection');
      expect(summary.description, 'Detailed inspection form');
    });
  });
}
