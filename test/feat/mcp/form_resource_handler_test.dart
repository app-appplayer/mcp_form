import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/adapters/form_port_impl.dart';
import 'package:mcp_form/src/adapters/form_template_port_impl.dart';
import 'package:mcp_form/src/feat/mcp/form_resource_handler.dart';
import 'package:mcp_form/src/feat/mcp/mcp_types.dart';
import 'package:test/test.dart';

FormTemplate _makeTemplate({String id = 'tpl-1', String name = 'Test'}) {
  return FormTemplate(
    templateId: id,
    version: '1.0.0',
    name: name,
    schema: FormSchema(fields: [
      FormSchemaField(name: 'name', type: 'string'),
      FormSchemaField(name: 'age', type: 'number'),
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
  group('FormResourceHandler', () {
    late FormTemplatePortImpl templatePort;
    late FormPortImpl formPort;
    late FormResourceHandler handler;

    setUp(() async {
      templatePort = FormTemplatePortImpl();
      await templatePort.saveTemplate(template: _makeTemplate());
      await templatePort.saveTemplate(
        template: _makeTemplate(id: 'tpl-2', name: 'Report'),
      );

      formPort = FormPortImpl(templatePort: templatePort);
      await formPort.createDocument(
        templateId: 'tpl-1',
        initialData: {'name': 'Alice'},
        documentId: 'doc-1',
      );

      handler = FormResourceHandler(
        formPort: formPort,
        templatePort: templatePort,
      );
    });

    // TC-374: Resolve form://templates
    test('resolves form://templates returns template list', () async {
      final content = await handler.resolveResource('form://templates');

      expect(content.uri, 'form://templates');
      expect(content.mimeType, 'application/json');

      final parsed = jsonDecode(content.text) as Map<String, dynamic>;
      final templates = parsed['templates'] as List<dynamic>;
      expect(templates, hasLength(2));
      final first = templates.first as Map<String, dynamic>;
      expect(first['templateId'], isNotNull);
      expect(first['fieldCount'], 2);
    });

    // TC-375: Resolve document status
    test('resolves form://documents/{id}/status', () async {
      final content = await handler.resolveResource(
        'form://documents/doc-1/status',
      );

      expect(content.mimeType, 'application/json');

      final parsed = jsonDecode(content.text) as Map<String, dynamic>;
      expect(parsed['documentId'], 'doc-1');
      expect(parsed['status'], 'draft');
      expect(parsed['version'], 1);
      expect(parsed['author'], isNotNull);
    });

    // TC-376: Unknown URI throws
    test('throws for unknown URI', () async {
      expect(
        () => handler.resolveResource('form://unknown/resource'),
        throwsA(isA<McpToolError>()
            .having((e) => e.code, 'code', 'resource.not_found')),
      );
    });

    // TC-377: Non-existent document throws
    test('throws for non-existent document status', () async {
      expect(
        () => handler.resolveResource(
          'form://documents/doc_nonexistent/status',
        ),
        throwsA(isA<McpToolError>()
            .having((e) => e.code, 'code', 'resource.not_found')),
      );
    });

    // Resource definitions
    test('resourceDefinitions returns 2 definitions', () {
      expect(handler.resourceDefinitions, hasLength(2));
    });
  });
}
