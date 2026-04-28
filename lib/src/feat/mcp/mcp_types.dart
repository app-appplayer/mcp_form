/// MCP protocol types for tool and resource handling.
library;

/// Definition of an MCP tool for discovery.
class McpToolDefinition {
  const McpToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
}

/// Error thrown by MCP tool/resource handlers.
class McpToolError implements Exception {
  McpToolError({
    required this.code,
    required this.message,
    this.data,
  });

  final String code;
  final String message;
  final Map<String, dynamic>? data;

  @override
  String toString() => 'McpToolError($code): $message';
}

/// Definition of an MCP resource for discovery.
class McpResourceDefinition {
  const McpResourceDefinition({
    required this.uri,
    required this.name,
    required this.description,
    this.mimeType = 'application/json',
  });

  final String uri;
  final String name;
  final String description;
  final String mimeType;
}

/// Content returned by an MCP resource resolution.
class McpResourceContent {
  const McpResourceContent({
    required this.uri,
    required this.mimeType,
    required this.text,
  });

  final String uri;
  final String mimeType;
  final String text;
}
