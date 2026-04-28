import 'package:mcp_bundle/mcp_bundle.dart';

import '../../core/template/version_compatibility.dart';
import 'render_context.dart';

/// Renderer interface for the registry.
///
/// Unlike [FormRendererPort] from mcp_bundle, this provides a
/// simplified contract for internal renderers that receive a
/// [RenderContext] with pre-resolved layout and template info.
abstract class DocumentRenderer {
  /// Supported output formats (e.g., 'html', 'markdown').
  List<String> get supportedFormats;

  /// Semver range of template versions this renderer supports.
  /// Returns null to accept all versions (default).
  String? get supportedTemplateRange => null;

  /// Render a document to bytes.
  Future<FormRenderOutput> render(RenderContext context);
}

/// Registry for document renderers.
///
/// Manages format-to-renderer mappings and dispatches render
/// requests to the appropriate renderer.
class RendererRegistry {
  final Map<String, DocumentRenderer> _renderers = {};

  /// Register a renderer for its supported formats.
  ///
  /// Throws [FormError] with code `render.invalid_renderer` if
  /// the renderer declares no supported formats.
  void register(DocumentRenderer renderer) {
    if (renderer.supportedFormats.isEmpty) {
      throw FormError(
        code: 'render.invalid_renderer',
        message: 'Renderer declares no supported formats',
        path: '/renderer',
      );
    }
    for (final format in renderer.supportedFormats) {
      _renderers[format] = renderer;
    }
  }

  /// Unregister a renderer by format.
  bool unregister(String format) {
    return _renderers.remove(format) != null;
  }

  /// Get the renderer for a specific format.
  DocumentRenderer? getRenderer(String format) {
    return _renderers[format];
  }

  /// Check if a format is supported.
  bool isFormatSupported(String format) {
    return _renderers.containsKey(format);
  }

  /// List all registered formats.
  List<String> get registeredFormats => _renderers.keys.toList();

  /// Render a document in the specified format.
  ///
  /// Throws [FormError] if the format is not supported.
  Future<FormRenderOutput> render({
    required FormDocument document,
    required FormTemplate template,
    required String format,
    RenderOptions options = const RenderOptions(),
  }) async {
    final renderer = _renderers[format];
    if (renderer == null) {
      throw FormError(
        code: 'render.unsupported_format',
        message: 'No renderer registered for format "$format"',
        path: '/format',
      );
    }

    // Check template version compatibility
    if (renderer.supportedTemplateRange != null) {
      if (!isCompatibleWithRange(
        renderer.supportedTemplateRange,
        template.version,
      )) {
        throw FormError(
          code: 'render.incompatible_version',
          message:
              'Renderer does not support template version "${template.version}" '
              '(supported: ${renderer.supportedTemplateRange})',
          path: '/templateVersion',
        );
      }
    }

    final context = RenderContext(
      document: document,
      layoutPolicy: template.layoutPolicy,
      template: template,
      options: options,
    );

    try {
      return await renderer.render(context);
    } on FormError {
      rethrow;
    } catch (e) {
      throw FormError(
        code: 'render.failed',
        message: 'Rendering failed for format "$format": $e',
        path: '/format',
      );
    }
  }
}
