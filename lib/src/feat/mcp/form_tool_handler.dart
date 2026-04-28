import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';

import '../../core/workflow/workflow_engine.dart';
import 'mcp_types.dart';

/// Handles MCP tool calls for the form.* namespace.
///
/// Each tool call is dispatched to the appropriate port method.
/// Input is validated and output is serialized to MCP-compliant JSON.
/// All [FormError] exceptions are caught and mapped to [McpToolError].
class FormToolHandler {
  FormToolHandler({
    required FormPort formPort,
    required FormTemplatePort templatePort,
    required FormRendererPort rendererPort,
  })  : _formPort = formPort,
        _templatePort = templatePort,
        _rendererPort = rendererPort;

  final FormPort _formPort;
  final FormTemplatePort _templatePort;
  final FormRendererPort _rendererPort;

  /// Route an MCP tool call to the appropriate handler.
  ///
  /// Returns a JSON-serializable result map on success.
  /// Throws [McpToolError] on failure.
  Future<Map<String, dynamic>> handleToolCall({
    required String toolName,
    required Map<String, dynamic> arguments,
  }) async {
    try {
      return switch (toolName) {
        'form.list_templates' => await _handleListTemplates(arguments),
        'form.render' => await _handleRender(arguments),
        'form.validate' => await _handleValidate(arguments),
        'form.patch' => await _handlePatch(arguments),
        'form.export' => await _handleExport(arguments),
        'form.create_document' => await _handleCreateDocument(arguments),
        'form.get_status' => await _handleGetStatus(arguments),
        _ => throw McpToolError(
              code: 'tool.not_found',
              message: 'Unknown tool: $toolName',
            ),
      };
    } on McpToolError {
      rethrow;
    } on FormError catch (e) {
      throw mapFormErrorToMcpError(e);
    }
  }

  /// List all registered tool definitions for MCP discovery.
  List<McpToolDefinition> get toolDefinitions => [
        _listTemplatesDefinition,
        _renderDefinition,
        _validateDefinition,
        _patchDefinition,
        _exportDefinition,
        _createDocumentDefinition,
        _getStatusDefinition,
      ];

  // --- Tool Definitions ---

  static const _listTemplatesDefinition = McpToolDefinition(
    name: 'form.list_templates',
    description: 'List available form templates with summary information',
    inputSchema: {
      'type': 'object',
      'properties': {
        'limit': {
          'type': 'integer',
          'default': 20,
          'minimum': 1,
          'maximum': 100,
        },
        'offset': {
          'type': 'integer',
          'default': 0,
          'minimum': 0,
        },
      },
    },
  );

  static const _renderDefinition = McpToolDefinition(
    name: 'form.render',
    description:
        'Render a document to a specified output format '
        '(PDF, HTML, DOCX, Markdown, UI DSL)',
    inputSchema: {
      'type': 'object',
      'required': ['documentId', 'format'],
      'properties': {
        'documentId': {'type': 'string'},
        'format': {
          'type': 'string',
          'enum': ['pdf', 'html', 'docx', 'markdown', 'uiDsl'],
        },
        'options': {
          'type': 'object',
          'description': 'Optional rendering options',
        },
      },
    },
  );

  static const _validateDefinition = McpToolDefinition(
    name: 'form.validate',
    description:
        'Validate a document against its template schema '
        'and layout constraints',
    inputSchema: {
      'type': 'object',
      'required': ['documentId'],
      'properties': {
        'documentId': {'type': 'string'},
        'autoFix': {'type': 'boolean', 'default': false},
      },
    },
  );

  static const _patchDefinition = McpToolDefinition(
    name: 'form.patch',
    description:
        'Apply JSON Patch operations to a document '
        '(must be in draft state)',
    inputSchema: {
      'type': 'object',
      'required': ['documentId', 'patches'],
      'properties': {
        'documentId': {'type': 'string'},
        'patches': {
          'type': 'array',
          'items': {
            'type': 'object',
            'required': ['op', 'path'],
            'properties': {
              'op': {
                'type': 'string',
                'enum': ['add', 'remove', 'replace', 'move', 'copy', 'test'],
              },
              'path': {'type': 'string'},
              'value': <String, dynamic>{},
              'from': {'type': 'string'},
            },
          },
        },
      },
    },
  );

  static const _exportDefinition = McpToolDefinition(
    name: 'form.export',
    description: 'Export a document to a file in the specified format',
    inputSchema: {
      'type': 'object',
      'required': ['documentId', 'format'],
      'properties': {
        'documentId': {'type': 'string'},
        'format': {
          'type': 'string',
          'enum': ['pdf', 'html', 'docx', 'markdown', 'uiDsl'],
        },
      },
    },
  );

  static const _createDocumentDefinition = McpToolDefinition(
    name: 'form.create_document',
    description:
        'Create a new document from a template with optional initial data',
    inputSchema: {
      'type': 'object',
      'required': ['templateId', 'data'],
      'properties': {
        'templateId': {'type': 'string'},
        'data': {'type': 'object'},
      },
    },
  );

  static const _getStatusDefinition = McpToolDefinition(
    name: 'form.get_status',
    description: 'Get the current workflow status of a document',
    inputSchema: {
      'type': 'object',
      'required': ['documentId'],
      'properties': {
        'documentId': {'type': 'string'},
      },
    },
  );

  // --- Handler Methods ---

  Future<Map<String, dynamic>> _handleListTemplates(
    Map<String, dynamic> arguments,
  ) async {
    final limit = arguments['limit'] as int? ?? 20;
    final offset = arguments['offset'] as int? ?? 0;

    final result = await _templatePort.listTemplates(
      limit: limit,
      offset: offset,
    );

    if (!result.success) {
      throw FormError(
        code: result.error?.code ?? 'template.list_failed',
        message: result.error?.message ?? 'Failed to list templates',
        path: result.error?.path,
      );
    }

    final templates = result.data ?? [];
    return {
      'templates': templates
          .map((t) => {
                'templateId': t.templateId,
                'name': t.name,
                'version': t.version,
                'fieldCount': t.schema.fields.length,
              })
          .toList(),
      'total': templates.length,
    };
  }

  Future<Map<String, dynamic>> _handleRender(
    Map<String, dynamic> arguments,
  ) async {
    final documentId = arguments['documentId'] as String;
    final format = arguments['format'] as String;
    final options = arguments['options'] as Map<String, dynamic>?;

    final docResult = await _formPort.getDocument(documentId: documentId);
    if (!docResult.success || docResult.data == null) {
      throw FormError(
        code: docResult.error?.code ?? 'document.not_found',
        message: docResult.error?.message ?? 'Document not found: $documentId',
        path: docResult.error?.path,
      );
    }

    final renderResult = await _rendererPort.render(
      document: docResult.data!,
      format: format,
      options: options,
    );

    if (!renderResult.success || renderResult.data == null) {
      throw FormError(
        code: renderResult.error?.code ?? 'render.failed',
        message: renderResult.error?.message ?? 'Rendering failed',
        path: renderResult.error?.path,
      );
    }

    final output = renderResult.data!;
    final contentBytes = output.content is List<int>
        ? output.content as List<int>
        : utf8.encode(output.content.toString());

    return {
      'format': output.format,
      'data': base64Encode(contentBytes),
      'pageCount': output.pageCount,
      'generatedAt': output.generatedAt.toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> _handleValidate(
    Map<String, dynamic> arguments,
  ) async {
    final documentId = arguments['documentId'] as String;
    final autoFix = arguments['autoFix'] as bool? ?? false;

    final docResult = await _formPort.getDocument(documentId: documentId);
    if (!docResult.success || docResult.data == null) {
      throw FormError(
        code: docResult.error?.code ?? 'document.not_found',
        message: docResult.error?.message ?? 'Document not found: $documentId',
        path: docResult.error?.path,
      );
    }

    final valResult = await _formPort.validate(
      document: docResult.data!,
      autoFix: autoFix,
    );

    if (!valResult.success || valResult.data == null) {
      throw FormError(
        code: valResult.error?.code ?? 'validation.failed',
        message: valResult.error?.message ?? 'Validation failed',
        path: valResult.error?.path,
      );
    }

    final result = valResult.data!;
    return {
      'isValid': result.isValid,
      'errors': result.issues
          .where((i) => i.severity == 'error' || i.severity == null)
          .map((i) => {
                'code': i.code,
                'message': i.message,
                'path': i.path,
              })
          .toList(),
      'warnings': result.issues
          .where((i) => i.severity == 'warning')
          .map((i) => {
                'code': i.code,
                'message': i.message,
                'path': i.path,
              })
          .toList(),
      'appliedFixes': (result.appliedFixes ?? [])
          .map((f) => {
                'action': f.action,
                'path': f.path,
                'description': f.description,
              })
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _handlePatch(
    Map<String, dynamic> arguments,
  ) async {
    final documentId = arguments['documentId'] as String;
    final patchesJson = arguments['patches'] as List<dynamic>;

    // Get current document to know target version
    final docResult = await _formPort.getDocument(documentId: documentId);
    if (!docResult.success || docResult.data == null) {
      throw FormError(
        code: docResult.error?.code ?? 'document.not_found',
        message: docResult.error?.message ?? 'Document not found: $documentId',
        path: docResult.error?.path,
      );
    }

    final operations = patchesJson
        .map((p) => FormPatchOperation.fromJson(p as Map<String, dynamic>))
        .toList();

    final result = await _formPort.patch(
      documentId: documentId,
      operations: operations,
      targetVersion: docResult.data!.version,
    );

    if (!result.success || result.data == null) {
      throw FormError(
        code: result.error?.code ?? 'patch.failed',
        message: result.error?.message ?? 'Patch operation failed',
        path: result.error?.path,
      );
    }

    return {
      'documentId': result.data!.documentId,
      'version': result.data!.version,
      'patchCount': operations.length,
      'status': result.data!.status.name,
    };
  }

  Future<Map<String, dynamic>> _handleExport(
    Map<String, dynamic> arguments,
  ) async {
    return _handleRender(arguments);
  }

  Future<Map<String, dynamic>> _handleCreateDocument(
    Map<String, dynamic> arguments,
  ) async {
    final templateId = arguments['templateId'] as String;
    final data = arguments['data'] as Map<String, dynamic>? ?? {};

    final result = await _formPort.createDocument(
      templateId: templateId,
      initialData: data,
    );

    if (!result.success || result.data == null) {
      throw FormError(
        code: result.error?.code ?? 'document.create_failed',
        message: result.error?.message ?? 'Failed to create document',
        path: result.error?.path,
      );
    }

    final doc = result.data!;
    return {
      'documentId': doc.documentId,
      'templateId': doc.templateId,
      'templateVersion': doc.templateVersion,
      'status': doc.status.name,
      'version': doc.version,
      'createdAt': doc.metadata.createdAt.toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> _handleGetStatus(
    Map<String, dynamic> arguments,
  ) async {
    final documentId = arguments['documentId'] as String;

    final docResult = await _formPort.getDocument(documentId: documentId);
    if (!docResult.success || docResult.data == null) {
      throw FormError(
        code: docResult.error?.code ?? 'document.not_found',
        message:
            docResult.error?.message ?? 'Document not found: $documentId',
        path: docResult.error?.path,
      );
    }

    final doc = docResult.data!;

    // Compute valid transitions from default workflow rules
    final validTargets = WorkflowEngine.defaultRules
        .where((r) => r.from == doc.status)
        .map((r) => r.to.name)
        .toList();

    return {
      'documentId': doc.documentId,
      'status': doc.status.name,
      'version': doc.version,
      'templateId': doc.templateId,
      'author': doc.metadata.author,
      'updatedAt': (doc.metadata.modifiedAt ?? doc.metadata.createdAt)
          .toIso8601String(),
      'validTransitions': validTargets,
    };
  }

  /// Maps [FormError] codes to MCP-compliant error responses.
  static McpToolError mapFormErrorToMcpError(FormError error) {
    final mcpCode = switch (error.code) {
      'template.not_found' => 'NOT_FOUND',
      'template.version_not_found' => 'NOT_FOUND',
      'document.not_found' => 'NOT_FOUND',
      'form.document_not_found' => 'NOT_FOUND',
      'form.template_not_found' => 'NOT_FOUND',
      'schema.required_missing' => 'INVALID_PARAMS',
      'schema.type_mismatch' => 'INVALID_PARAMS',
      'schema.constraint_violated' => 'INVALID_PARAMS',
      'schema.unknown_field' => 'INVALID_PARAMS',
      'layout.overflow' => 'INVALID_PARAMS',
      'layout.table_overflow' => 'INVALID_PARAMS',
      'patch.invalid_path' => 'INVALID_PARAMS',
      'form.version_conflict' => 'CONFLICT',
      'render.unsupported_format' => 'INVALID_PARAMS',
      'render.failed' => 'INTERNAL_ERROR',
      'workflow.invalid_transition' => 'CONFLICT',
      'workflow.approval_denied' => 'FORBIDDEN',
      _ => 'INTERNAL_ERROR',
    };

    return McpToolError(
      code: mcpCode,
      message: error.message,
      data: {
        'formErrorCode': error.code,
        if (error.path != null) 'path': error.path,
      },
    );
  }
}
