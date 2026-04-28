import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/adapters/form_template_port_impl.dart';
import 'package:test/test.dart';

FormTemplate _makeTemplate({
  String id = 'tpl-1',
  String version = '1.0.0',
  String name = 'Test Template',
  FormSchema? schema,
}) {
  return FormTemplate(
    templateId: id,
    version: version,
    name: name,
    schema: schema ??
        FormSchema(fields: [
          FormSchemaField(name: 'field1', type: 'string'),
        ]),
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
  );
}

void main() {
  group('FormTemplatePortImpl', () {
    late FormTemplatePortImpl port;

    setUp(() {
      port = FormTemplatePortImpl();
    });

    // --- saveTemplate ---

    test('saveTemplate stores template', () async {
      final template = _makeTemplate();
      final result = await port.saveTemplate(template: template);

      expect(result.success, isTrue);
      expect(result.data?.templateId, 'tpl-1');
    });

    test('saveTemplate records version history', () async {
      await port.saveTemplate(template: _makeTemplate());

      final versions = await port.getTemplateVersions(templateId: 'tpl-1');
      expect(versions.success, isTrue);
      expect(versions.data!.length, 1);
      expect(versions.data!.first.version, '1.0.0');
    });

    test('saveTemplate rejects duplicate templateId+version', () async {
      await port.saveTemplate(template: _makeTemplate(name: 'Original'));
      final result =
          await port.saveTemplate(template: _makeTemplate(name: 'Updated'));

      expect(result.success, isFalse);
      expect(result.error?.code, 'template.duplicate');
    });

    test('saveTemplate allows same templateId with different version', () async {
      await port.saveTemplate(template: _makeTemplate(version: '1.0.0'));
      final result = await port.saveTemplate(
        template: _makeTemplate(version: '1.1.0'),
      );

      expect(result.success, isTrue);
    });

    test('saveTemplate rejects template with empty schema', () async {
      final result = await port.saveTemplate(
        template: _makeTemplate(
          id: 'tpl-empty',
          schema: const FormSchema(),
        ),
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'template.invalid_schema');
    });

    // --- getTemplate ---

    test('getTemplate returns stored template', () async {
      await port.saveTemplate(template: _makeTemplate());

      final result = await port.getTemplate(templateId: 'tpl-1');
      expect(result.success, isTrue);
      expect(result.data?.name, 'Test Template');
    });

    test('getTemplate fails for non-existent template', () async {
      final result = await port.getTemplate(templateId: 'unknown');

      expect(result.success, isFalse);
      expect(result.error?.code, 'template.not_found');
    });

    test('getTemplate with matching version succeeds', () async {
      await port.saveTemplate(template: _makeTemplate());

      final result = await port.getTemplate(
        templateId: 'tpl-1',
        version: '1.0.0',
      );
      expect(result.success, isTrue);
    });

    test('getTemplate with mismatched version fails', () async {
      await port.saveTemplate(template: _makeTemplate());

      final result = await port.getTemplate(
        templateId: 'tpl-1',
        version: '2.0.0',
      );
      expect(result.success, isFalse);
      expect(result.error?.code, 'template.version_not_found');
    });

    // --- listTemplates ---

    test('listTemplates returns all templates', () async {
      await port.saveTemplate(template: _makeTemplate(id: 'tpl-1'));
      await port.saveTemplate(template: _makeTemplate(id: 'tpl-2'));

      final result = await port.listTemplates();
      expect(result.success, isTrue);
      expect(result.data!.length, 2);
    });

    test('listTemplates filters by search', () async {
      await port.saveTemplate(
        template: _makeTemplate(id: 'tpl-1', name: 'Invoice Template'),
      );
      await port.saveTemplate(
        template: _makeTemplate(id: 'tpl-2', name: 'Report Template'),
      );

      final result = await port.listTemplates(search: 'Invoice');
      expect(result.data!.length, 1);
      expect(result.data!.first.name, 'Invoice Template');
    });

    test('listTemplates respects limit and offset', () async {
      for (var i = 0; i < 5; i++) {
        await port.saveTemplate(
          template: _makeTemplate(id: 'tpl-$i', name: 'Template $i'),
        );
      }

      final result = await port.listTemplates(limit: 2, offset: 1);
      expect(result.data!.length, 2);
    });

    // --- deleteTemplate ---

    test('deleteTemplate removes template', () async {
      await port.saveTemplate(template: _makeTemplate());

      final result = await port.deleteTemplate(templateId: 'tpl-1');
      expect(result.success, isTrue);

      final get = await port.getTemplate(templateId: 'tpl-1');
      expect(get.success, isFalse);
    });

    test('deleteTemplate fails for non-existent', () async {
      final result = await port.deleteTemplate(templateId: 'unknown');
      expect(result.success, isFalse);
      expect(result.error?.code, 'template.not_found');
    });

    test('deleteTemplate with specific version removes matching', () async {
      await port.saveTemplate(template: _makeTemplate());

      final result = await port.deleteTemplate(
        templateId: 'tpl-1',
        version: '1.0.0',
      );
      expect(result.success, isTrue);

      final get = await port.getTemplate(templateId: 'tpl-1');
      expect(get.success, isFalse);
    });

    // --- getTemplateVersions ---

    test('getTemplateVersions returns empty for unknown template', () async {
      final result = await port.getTemplateVersions(templateId: 'unknown');
      expect(result.success, isTrue);
      expect(result.data, isEmpty);
    });

    test('getTemplateVersions tracks multiple version saves', () async {
      await port.saveTemplate(template: _makeTemplate(version: '1.0.0'));
      await port.saveTemplate(template: _makeTemplate(version: '1.1.0'));

      final versions = await port.getTemplateVersions(templateId: 'tpl-1');
      expect(versions.data!.length, 2);
    });
  });
}
