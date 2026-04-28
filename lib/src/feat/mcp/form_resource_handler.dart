import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';

import 'mcp_types.dart';

/// Exposes form-related data as MCP resources.
///
/// Resources allow MCP clients to discover and inspect form data
/// without calling tools. Two resource types are exposed:
/// - Template list (browsable template catalog)
/// - Document status (current state of a specific document)
class FormResourceHandler {
  FormResourceHandler({
    required FormPort formPort,
    required FormTemplatePort templatePort,
  })  : _formPort = formPort,
        _templatePort = templatePort;

  final FormPort _formPort;
  final FormTemplatePort _templatePort;

  /// List all registered resource definitions.
  List<McpResourceDefinition> get resourceDefinitions => const [
        McpResourceDefinition(
          uri: 'form://templates',
          name: 'Form Templates',
          description: 'List of available form templates',
        ),
        McpResourceDefinition(
          uri: 'form://documents/{documentId}/status',
          name: 'Document Status',
          description: 'Current workflow status of a document',
        ),
      ];

  /// Resolve a resource URI and return its content.
  ///
  /// Throws [McpToolError] if the URI is unknown or the resource
  /// cannot be found.
  Future<McpResourceContent> resolveResource(String uri) async {
    if (uri == 'form://templates') {
      return _resolveTemplateList();
    }

    final docStatusMatch =
        RegExp(r'^form://documents/(.+)/status$').firstMatch(uri);
    if (docStatusMatch != null) {
      final documentId = docStatusMatch.group(1)!;
      return _resolveDocumentStatus(documentId);
    }

    throw McpToolError(
      code: 'resource.not_found',
      message: 'Unknown resource: $uri',
    );
  }

  Future<McpResourceContent> _resolveTemplateList() async {
    final result = await _templatePort.listTemplates();
    final templates = result.data ?? [];

    return McpResourceContent(
      uri: 'form://templates',
      mimeType: 'application/json',
      text: jsonEncode({
        'templates': templates
            .map((t) => {
                  'templateId': t.templateId,
                  'name': t.name,
                  'version': t.version,
                  'fieldCount': t.schema.fields.length,
                })
            .toList(),
      }),
    );
  }

  Future<McpResourceContent> _resolveDocumentStatus(String documentId) async {
    final result = await _formPort.getDocument(documentId: documentId);
    if (!result.success || result.data == null) {
      throw McpToolError(
        code: 'resource.not_found',
        message: 'Document not found: $documentId',
      );
    }

    final doc = result.data!;
    return McpResourceContent(
      uri: 'form://documents/$documentId/status',
      mimeType: 'application/json',
      text: jsonEncode({
        'documentId': doc.documentId,
        'status': doc.status.name,
        'version': doc.version,
        'author': doc.metadata.author,
        'updatedAt': (doc.metadata.modifiedAt ?? doc.metadata.createdAt)
            .toIso8601String(),
      }),
    );
  }
}
