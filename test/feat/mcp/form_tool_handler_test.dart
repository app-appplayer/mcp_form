import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/adapters/form_port_impl.dart';
import 'package:mcp_form/src/adapters/form_renderer_port_impl.dart';
import 'package:mcp_form/src/adapters/form_template_port_impl.dart';
import 'package:mcp_form/src/feat/mcp/form_tool_handler.dart';
import 'package:mcp_form/src/feat/mcp/mcp_types.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderer_registry.dart';
import 'package:test/test.dart';

// --- Stub ports for failure scenarios ---

/// A FormTemplatePort that always fails on listTemplates.
class FailingTemplatePort implements FormTemplatePort {
  @override
  Future<FormResult<List<FormTemplate>>> listTemplates({
    String? search,
    int? limit,
    int? offset,
  }) async {
    return FormResult.fail(FormError(
      code: 'template.list_failed',
      message: 'Simulated failure',
    ));
  }

  @override
  Future<FormResult<FormTemplate>> getTemplate({
    required String templateId,
    String? version,
  }) async {
    return FormResult.fail(FormError(
      code: 'template.not_found',
      message: 'Not found',
    ));
  }

  @override
  Future<FormResult<FormTemplate>> saveTemplate({
    required FormTemplate template,
  }) async {
    return FormResult.fail(FormError(
      code: 'template.save_failed',
      message: 'Not implemented',
    ));
  }

  @override
  Future<FormResult<List<FormTemplateVersion>>> getTemplateVersions({
    required String templateId,
  }) async {
    return FormResult.ok([]);
  }

  @override
  Future<FormResult<void>> deleteTemplate({
    required String templateId,
    String? version,
  }) async {
    return FormResult.ok(null);
  }
}

/// A FormPort that always returns fail results.
class FailingFormPort implements FormPort {
  @override
  Future<FormResult<FormDocument>> createDocument({
    required String templateId,
    required Map<String, dynamic> initialData,
    String? documentId,
    String? author,
  }) async {
    return FormResult.fail(FormError(
      code: 'document.create_failed',
      message: 'Simulated create failure',
    ));
  }

  @override
  Future<FormResult<FormDocument>> getDocument({
    required String documentId,
  }) async {
    return FormResult.fail(FormError(
      code: 'form.document_not_found',
      message: 'Simulated not found',
    ));
  }

  @override
  Future<FormResult<List<FormDocument>>> listDocuments({
    String? templateId,
    String? status,
    int? limit,
    int? offset,
  }) async {
    return FormResult.fail(FormError(
      code: 'form.list_failed',
      message: 'Simulated list failure',
    ));
  }

  @override
  Future<FormResult<FormDocument>> patch({
    required String documentId,
    required List<FormPatchOperation> operations,
    required int targetVersion,
  }) async {
    return FormResult.fail(FormError(
      code: 'patch.failed',
      message: 'Simulated patch failure',
    ));
  }

  @override
  Future<FormResult<FormValidationResult>> validate({
    required FormDocument document,
    bool autoFix = false,
  }) async {
    return FormResult.fail(FormError(
      code: 'validation.failed',
      message: 'Simulated validation failure',
    ));
  }

  @override
  Future<FormResult<List<FormDocumentVersion>>> getDocumentHistory({
    required String documentId,
  }) async {
    return FormResult.ok([]);
  }
}

/// A FormPort that returns a document but validate fails.
class DocExistsButValidateFailsFormPort implements FormPort {
  final FormDocument _doc;

  DocExistsButValidateFailsFormPort(this._doc);

  @override
  Future<FormResult<FormDocument>> getDocument({
    required String documentId,
  }) async {
    return FormResult.ok(_doc);
  }

  @override
  Future<FormResult<FormValidationResult>> validate({
    required FormDocument document,
    bool autoFix = false,
  }) async {
    return FormResult.fail(FormError(
      code: 'validation.failed',
      message: 'Simulated validation failure',
    ));
  }

  @override
  Future<FormResult<FormDocument>> createDocument({
    required String templateId,
    required Map<String, dynamic> initialData,
    String? documentId,
    String? author,
  }) async =>
      FormResult.fail(FormError(code: 'err', message: 'err'));

  @override
  Future<FormResult<List<FormDocument>>> listDocuments({
    String? templateId,
    String? status,
    int? limit,
    int? offset,
  }) async =>
      FormResult.ok([]);

  @override
  Future<FormResult<FormDocument>> patch({
    required String documentId,
    required List<FormPatchOperation> operations,
    required int targetVersion,
  }) async {
    return FormResult.fail(FormError(
      code: 'patch.failed',
      message: 'Simulated patch failure',
    ));
  }

  @override
  Future<FormResult<List<FormDocumentVersion>>> getDocumentHistory({
    required String documentId,
  }) async =>
      FormResult.ok([]);
}

/// A FormRendererPort that always fails.
class FailingRendererPort implements FormRendererPort {
  @override
  Future<FormResult<FormRenderOutput>> render({
    required FormDocument document,
    required String format,
    Map<String, dynamic>? options,
  }) async {
    return FormResult.fail(FormError(
      code: 'render.failed',
      message: 'Simulated render failure',
    ));
  }

  @override
  List<String> supportedFormats() => ['html'];

  @override
  FormRendererMetadata getMetadata() => FormRendererMetadata(
        rendererId: 'test',
        version: '1.0.0',
        supportedFormats: ['html'],
      );
}

/// A StubHtmlRenderer that returns string content (not List<int>).
class StubHtmlStringRenderer implements DocumentRenderer {
  @override
  final List<String> supportedFormats = ['html'];

  @override
  String? get supportedTemplateRange => null;

  @override
  Future<FormRenderOutput> render(RenderContext context) async {
    return FormRenderOutput(
      format: 'html',
      content: '<p>rendered as string</p>',
      pageCount: 1,
      generatedAt: DateTime(2026),
    );
  }
}

class StubHtmlRenderer implements DocumentRenderer {
  @override
  final List<String> supportedFormats = ['html'];

  @override
  String? get supportedTemplateRange => null;

  @override
  Future<FormRenderOutput> render(RenderContext context) async {
    return FormRenderOutput(
      format: 'html',
      content: utf8.encode('<p>rendered</p>'),
      pageCount: 1,
      generatedAt: DateTime(2026),
    );
  }
}

FormTemplate _makeTemplate({String id = 'tpl-1', String name = 'Test'}) {
  return FormTemplate(
    templateId: id,
    version: '1.0.0',
    name: name,
    schema: FormSchema(fields: [
      FormSchemaField(name: 'name', type: 'string'),
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
  group('FormToolHandler', () {
    late FormTemplatePortImpl templatePort;
    late FormPortImpl formPort;
    late FormRendererPortImpl rendererPort;
    late FormToolHandler handler;

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

      final registry = RendererRegistry();
      registry.register(StubHtmlRenderer());
      rendererPort = FormRendererPortImpl(
        registry: registry,
        templatePort: templatePort,
      );

      handler = FormToolHandler(
        formPort: formPort,
        templatePort: templatePort,
        rendererPort: rendererPort,
      );
    });

    // --- TC-349: Tool dispatch ---

    test('routes form.list_templates correctly', () async {
      final result = await handler.handleToolCall(
        toolName: 'form.list_templates',
        arguments: {},
      );

      expect(result['templates'], isList);
      expect(result['total'], 2);
    });

    // TC-350: form.render
    test('routes form.render correctly', () async {
      final result = await handler.handleToolCall(
        toolName: 'form.render',
        arguments: {'documentId': 'doc-1', 'format': 'html'},
      );

      expect(result['format'], 'html');
      expect(result['data'], isNotEmpty); // base64
    });

    // TC-351: form.validate
    test('routes form.validate correctly', () async {
      final result = await handler.handleToolCall(
        toolName: 'form.validate',
        arguments: {'documentId': 'doc-1'},
      );

      expect(result.containsKey('isValid'), isTrue);
      expect(result.containsKey('errors'), isTrue);
    });

    // TC-352: form.patch
    test('routes form.patch correctly', () async {
      final result = await handler.handleToolCall(
        toolName: 'form.patch',
        arguments: {
          'documentId': 'doc-1',
          'patches': [
            {'op': 'replace', 'path': '/data/name', 'value': 'Bob'},
          ],
        },
      );

      expect(result['documentId'], 'doc-1');
      expect(result['version'], 2);
      expect(result['patchCount'], 1);
    });

    // TC-353: form.export
    test('routes form.export correctly', () async {
      final result = await handler.handleToolCall(
        toolName: 'form.export',
        arguments: {'documentId': 'doc-1', 'format': 'html'},
      );

      expect(result['format'], 'html');
      expect(result['data'], isNotEmpty);
    });

    // TC-354: form.create_document
    test('routes form.create_document correctly', () async {
      final result = await handler.handleToolCall(
        toolName: 'form.create_document',
        arguments: {'templateId': 'tpl-1', 'data': {'name': 'Test'}},
      );

      expect(result['templateId'], 'tpl-1');
      expect(result['status'], 'draft');
      expect(result['version'], 1);
    });

    // TC-355: form.get_status
    test('routes form.get_status correctly', () async {
      final result = await handler.handleToolCall(
        toolName: 'form.get_status',
        arguments: {'documentId': 'doc-1'},
      );

      expect(result['status'], 'draft');
      expect(result['validTransitions'], contains('review'));
    });

    // TC-356: Unknown tool
    test('throws McpToolError for unknown tool', () async {
      expect(
        () => handler.handleToolCall(
          toolName: 'form.unknown',
          arguments: {},
        ),
        throwsA(isA<McpToolError>()
            .having((e) => e.code, 'code', 'tool.not_found')),
      );
    });

    // --- TC-357-359: form.list_templates ---

    test('default pagination returns templates', () async {
      final result = await handler.handleToolCall(
        toolName: 'form.list_templates',
        arguments: {},
      );

      expect(result['templates'], hasLength(2));
      expect(result['total'], 2);
    });

    test('custom limit and offset forwarded', () async {
      final result = await handler.handleToolCall(
        toolName: 'form.list_templates',
        arguments: {'limit': 1, 'offset': 0},
      );

      expect(result['templates'], hasLength(1));
    });

    test('empty template list returns total=0', () async {
      final emptyTemplatePort = FormTemplatePortImpl();
      final emptyHandler = FormToolHandler(
        formPort: FormPortImpl(templatePort: emptyTemplatePort),
        templatePort: emptyTemplatePort,
        rendererPort: rendererPort,
      );

      final result = await emptyHandler.handleToolCall(
        toolName: 'form.list_templates',
        arguments: {},
      );

      expect(result['templates'], isEmpty);
      expect(result['total'], 0);
    });

    // --- TC-360-362: form.validate ---

    test('validate with autoFix', () async {
      final result = await handler.handleToolCall(
        toolName: 'form.validate',
        arguments: {'documentId': 'doc-1', 'autoFix': true},
      );

      expect(result.containsKey('isValid'), isTrue);
    });

    test('validate non-existent document throws', () async {
      expect(
        () => handler.handleToolCall(
          toolName: 'form.validate',
          arguments: {'documentId': 'doc_nonexistent'},
        ),
        throwsA(isA<McpToolError>()
            .having((e) => e.code, 'code', 'NOT_FOUND')),
      );
    });

    // --- TC-363-364: form.create_document ---

    test('create document with empty data', () async {
      final result = await handler.handleToolCall(
        toolName: 'form.create_document',
        arguments: {'templateId': 'tpl-1'},
      );

      expect(result['status'], 'draft');
      expect(result['version'], 1);
    });

    // --- TC-365-366: form.get_status ---

    test('get_status includes validTransitions for draft', () async {
      final result = await handler.handleToolCall(
        toolName: 'form.get_status',
        arguments: {'documentId': 'doc-1'},
      );

      expect(result['validTransitions'], ['review']);
    });

    // --- TC-367-373: Error mapping ---

    test('template.not_found maps to NOT_FOUND', () {
      final error = FormToolHandler.mapFormErrorToMcpError(
        FormError(code: 'template.not_found', message: 'not found'),
      );
      expect(error.code, 'NOT_FOUND');
    });

    test('schema.required_missing maps to INVALID_PARAMS', () {
      final error = FormToolHandler.mapFormErrorToMcpError(
        FormError(code: 'schema.required_missing', message: 'missing'),
      );
      expect(error.code, 'INVALID_PARAMS');
    });

    test('schema.type_mismatch maps to INVALID_PARAMS', () {
      final error = FormToolHandler.mapFormErrorToMcpError(
        FormError(code: 'schema.type_mismatch', message: 'wrong type'),
      );
      expect(error.code, 'INVALID_PARAMS');
    });

    test('schema.constraint_violated maps to INVALID_PARAMS', () {
      final error = FormToolHandler.mapFormErrorToMcpError(
        FormError(code: 'schema.constraint_violated', message: 'violated'),
      );
      expect(error.code, 'INVALID_PARAMS');
    });

    test('schema.unknown_field maps to INVALID_PARAMS', () {
      final error = FormToolHandler.mapFormErrorToMcpError(
        FormError(code: 'schema.unknown_field', message: 'unknown'),
      );
      expect(error.code, 'INVALID_PARAMS');
    });

    test('layout.table_overflow maps to INVALID_PARAMS', () {
      final error = FormToolHandler.mapFormErrorToMcpError(
        FormError(code: 'layout.table_overflow', message: 'too many rows'),
      );
      expect(error.code, 'INVALID_PARAMS');
    });

    test('workflow.invalid_transition maps to CONFLICT', () {
      final error = FormToolHandler.mapFormErrorToMcpError(
        FormError(code: 'workflow.invalid_transition', message: 'bad'),
      );
      expect(error.code, 'CONFLICT');
    });

    test('workflow.approval_denied maps to FORBIDDEN', () {
      final error = FormToolHandler.mapFormErrorToMcpError(
        FormError(code: 'workflow.approval_denied', message: 'denied'),
      );
      expect(error.code, 'FORBIDDEN');
    });

    test('render.failed maps to INTERNAL_ERROR', () {
      final error = FormToolHandler.mapFormErrorToMcpError(
        FormError(code: 'render.failed', message: 'fail'),
      );
      expect(error.code, 'INTERNAL_ERROR');
    });

    test('unknown error code maps to INTERNAL_ERROR', () {
      final error = FormToolHandler.mapFormErrorToMcpError(
        FormError(code: 'some.unknown.code', message: 'unknown'),
      );
      expect(error.code, 'INTERNAL_ERROR');
    });

    test('McpToolError.data preserves formErrorCode and path', () {
      final error = FormToolHandler.mapFormErrorToMcpError(
        FormError(
          code: 'patch.invalid_path',
          message: 'bad path',
          path: '/sections/0',
        ),
      );
      expect(error.data?['formErrorCode'], 'patch.invalid_path');
      expect(error.data?['path'], '/sections/0');
    });

    // TC-378: toolDefinitions
    test('toolDefinitions returns 7 tool definitions', () {
      final definitions = handler.toolDefinitions;
      expect(definitions, hasLength(7));

      final names = definitions.map((d) => d.name).toSet();
      expect(names, containsAll([
        'form.list_templates',
        'form.render',
        'form.validate',
        'form.patch',
        'form.export',
        'form.create_document',
        'form.get_status',
      ]));
    });

    // --- Error paths: listTemplates failure ---

    test('list_templates throws when templatePort fails', () async {
      final failHandler = FormToolHandler(
        formPort: formPort,
        templatePort: FailingTemplatePort(),
        rendererPort: rendererPort,
      );

      expect(
        () => failHandler.handleToolCall(
          toolName: 'form.list_templates',
          arguments: {},
        ),
        throwsA(isA<McpToolError>()),
      );
    });

    // --- Error paths: render document not found ---

    test('render throws when document not found', () async {
      final failHandler = FormToolHandler(
        formPort: FailingFormPort(),
        templatePort: templatePort,
        rendererPort: rendererPort,
      );

      expect(
        () => failHandler.handleToolCall(
          toolName: 'form.render',
          arguments: {'documentId': 'no-such-doc', 'format': 'html'},
        ),
        throwsA(isA<McpToolError>()),
      );
    });

    // --- Error paths: render fails from renderer ---

    test('render throws when renderer port fails', () async {
      final doc = FormDocument(
        documentId: 'doc-render-fail',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
      );

      final failHandler = FormToolHandler(
        formPort: DocExistsButValidateFailsFormPort(doc),
        templatePort: templatePort,
        rendererPort: FailingRendererPort(),
      );

      expect(
        () => failHandler.handleToolCall(
          toolName: 'form.render',
          arguments: {'documentId': 'doc-render-fail', 'format': 'html'},
        ),
        throwsA(isA<McpToolError>()),
      );
    });

    // --- render with string content (non List<int>) ---

    test('render encodes string content via utf8', () async {
      final stringRegistry = RendererRegistry();
      stringRegistry.register(StubHtmlStringRenderer());
      final stringRendererPort = FormRendererPortImpl(
        registry: stringRegistry,
        templatePort: templatePort,
      );

      final stringHandler = FormToolHandler(
        formPort: formPort,
        templatePort: templatePort,
        rendererPort: stringRendererPort,
      );

      final result = await stringHandler.handleToolCall(
        toolName: 'form.render',
        arguments: {'documentId': 'doc-1', 'format': 'html'},
      );

      expect(result['format'], 'html');
      expect(result['data'], isNotEmpty);
      // Verify it can be decoded back
      final decoded = utf8.decode(base64Decode(result['data'] as String));
      expect(decoded, '<p>rendered as string</p>');
    });

    // --- Error paths: validate document not found is already tested ---
    // --- Error paths: validate result failure ---

    test('validate throws when validation port fails', () async {
      final doc = FormDocument(
        documentId: 'doc-val-fail',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
      );

      final failHandler = FormToolHandler(
        formPort: DocExistsButValidateFailsFormPort(doc),
        templatePort: templatePort,
        rendererPort: rendererPort,
      );

      expect(
        () => failHandler.handleToolCall(
          toolName: 'form.validate',
          arguments: {'documentId': 'doc-val-fail'},
        ),
        throwsA(isA<McpToolError>()),
      );
    });

    // --- Error paths: patch document not found ---

    test('patch throws when document not found', () async {
      final failHandler = FormToolHandler(
        formPort: FailingFormPort(),
        templatePort: templatePort,
        rendererPort: rendererPort,
      );

      expect(
        () => failHandler.handleToolCall(
          toolName: 'form.patch',
          arguments: {
            'documentId': 'no-doc',
            'patches': [
              {'op': 'replace', 'path': '/data/name', 'value': 'Bob'},
            ],
          },
        ),
        throwsA(isA<McpToolError>()),
      );
    });

    // --- Error paths: patch operation fails ---

    test('patch throws when patch operation fails', () async {
      final doc = FormDocument(
        documentId: 'doc-patch-fail',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
      );

      final failHandler = FormToolHandler(
        formPort: DocExistsButValidateFailsFormPort(doc),
        templatePort: templatePort,
        rendererPort: rendererPort,
      );

      expect(
        () => failHandler.handleToolCall(
          toolName: 'form.patch',
          arguments: {
            'documentId': 'doc-patch-fail',
            'patches': [
              {'op': 'replace', 'path': '/data/name', 'value': 'Bob'},
            ],
          },
        ),
        throwsA(isA<McpToolError>()),
      );
    });

    // --- Error paths: create_document fails ---

    test('create_document throws when formPort fails', () async {
      final failHandler = FormToolHandler(
        formPort: FailingFormPort(),
        templatePort: templatePort,
        rendererPort: rendererPort,
      );

      expect(
        () => failHandler.handleToolCall(
          toolName: 'form.create_document',
          arguments: {'templateId': 'tpl-1'},
        ),
        throwsA(isA<McpToolError>()),
      );
    });

    // --- Error paths: get_status document not found ---

    test('get_status throws when document not found', () async {
      final failHandler = FormToolHandler(
        formPort: FailingFormPort(),
        templatePort: templatePort,
        rendererPort: rendererPort,
      );

      expect(
        () => failHandler.handleToolCall(
          toolName: 'form.get_status',
          arguments: {'documentId': 'no-doc'},
        ),
        throwsA(isA<McpToolError>()),
      );
    });

    // --- FormError catch in handleToolCall ---

    test('handleToolCall maps FormError to McpToolError', () async {
      // Use a handler with FailingFormPort that will trigger a FormError
      // through the catch block
      final failHandler = FormToolHandler(
        formPort: FailingFormPort(),
        templatePort: FailingTemplatePort(),
        rendererPort: rendererPort,
      );

      // list_templates will throw FormError (not McpToolError) which gets
      // caught by the on FormError catch
      expect(
        () => failHandler.handleToolCall(
          toolName: 'form.list_templates',
          arguments: {},
        ),
        throwsA(isA<McpToolError>()),
      );
    });

    // --- validate result with actual errors, warnings, and fixes ---

    test('validate returns error and warning issues mapped correctly',
        () async {
      // Register a template with a required field and a pattern field
      final strictTemplate = FormTemplate(
        templateId: 'tpl-strict',
        version: '1.0.0',
        name: 'Strict',
        schema: FormSchema(fields: [
          FormSchemaField(name: 'name', type: 'string', required: true),
          FormSchemaField(
            name: 'code',
            type: 'string',
            pattern: r'^[A-Z]+$',
          ),
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
      await templatePort.saveTemplate(template: strictTemplate);

      // Create document missing required 'name' and with 'code' that
      // violates the uppercase-only pattern constraint
      await formPort.createDocument(
        templateId: 'tpl-strict',
        initialData: {'code': 'test'},
        documentId: 'doc-strict',
      );

      final result = await handler.handleToolCall(
        toolName: 'form.validate',
        arguments: {'documentId': 'doc-strict'},
      );

      expect(result['isValid'], isFalse);
      // Should have at least one error (required_missing for 'name')
      final errors = result['errors'] as List;
      expect(errors, isNotEmpty);
      expect(errors.first, containsPair('code', 'schema.required_missing'));
      expect(errors.first, containsPair('path', '/data/name'));

      // Should also have a constraint_violated error (pattern mismatch)
      final constraintErrors = errors
          .where((e) =>
              (e as Map)['code'] == 'schema.constraint_violated')
          .toList();
      expect(constraintErrors, isNotEmpty);
    });

    test('validate with autoFix returns appliedFixes', () async {
      // Register a template with required field
      final fixTemplate = FormTemplate(
        templateId: 'tpl-fix',
        version: '1.0.0',
        name: 'Fixable',
        schema: FormSchema(fields: [
          FormSchemaField(name: 'title', type: 'string', required: true),
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
      await templatePort.saveTemplate(template: fixTemplate);

      // Create document without required 'title'
      await formPort.createDocument(
        templateId: 'tpl-fix',
        initialData: {},
        documentId: 'doc-fix',
      );

      final result = await handler.handleToolCall(
        toolName: 'form.validate',
        arguments: {'documentId': 'doc-fix', 'autoFix': true},
      );

      // appliedFixes should have at least one fix
      final fixes = result['appliedFixes'] as List;
      expect(fixes, isNotEmpty);
      expect(fixes.first, containsPair('action', 'set_default'));
    });
  });

  // --- McpToolError.toString() ---

  group('McpToolError', () {
    test('toString returns formatted message', () {
      final error = McpToolError(
        code: 'TEST_CODE',
        message: 'Test message',
      );
      expect(error.toString(), 'McpToolError(TEST_CODE): Test message');
    });
  });
}
