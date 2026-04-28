import 'package:mcp_bundle/mcp_bundle.dart';

import '../infra/renderer/render_context.dart';
import '../infra/renderer/renderer_registry.dart';

/// Implementation of [FormRendererPort] that delegates to [RendererRegistry].
///
/// Bridges the mcp_bundle port interface with the internal renderer system,
/// requiring a [FormTemplatePort] to resolve templates for rendering context.
class FormRendererPortImpl implements FormRendererPort {
  FormRendererPortImpl({
    required RendererRegistry registry,
    required FormTemplatePort templatePort,
    String rendererId = 'mcp_form',
    String version = '0.1.0',
  })  : _registry = registry,
        _templatePort = templatePort,
        _rendererId = rendererId,
        _version = version;

  final RendererRegistry _registry;
  final FormTemplatePort _templatePort;
  final String _rendererId;
  final String _version;

  @override
  Future<FormResult<FormRenderOutput>> render({
    required FormDocument document,
    required String format,
    Map<String, dynamic>? options,
  }) async {
    if (!_registry.isFormatSupported(format)) {
      return FormResult.fail(FormError(
        code: 'render.unsupported_format',
        message: 'Format "$format" is not supported',
      ));
    }

    final templateResult = await _templatePort.getTemplate(
      templateId: document.templateId,
      version: document.templateVersion,
    );
    if (!templateResult.success || templateResult.data == null) {
      return FormResult.fail(FormError(
        code: 'render.template_not_found',
        message:
            'Template "${document.templateId}" not found for rendering',
      ));
    }

    final renderOptions = _parseOptions(options);

    try {
      final output = await _registry.render(
        document: document,
        template: templateResult.data!,
        format: format,
        options: renderOptions,
      );
      return FormResult.ok(output);
    } on FormError catch (e) {
      return FormResult.fail(e);
    }
  }

  @override
  List<String> supportedFormats() => _registry.registeredFormats;

  @override
  FormRendererMetadata getMetadata() => FormRendererMetadata(
        rendererId: _rendererId,
        version: _version,
        supportedFormats: _registry.registeredFormats,
      );

  RenderOptions _parseOptions(Map<String, dynamic>? options) {
    if (options == null) return const RenderOptions();
    return RenderOptions(
      includeMetadata: options['includeMetadata'] as bool? ?? false,
      applyWatermark: options['applyWatermark'] as bool? ?? false,
      watermarkText: options['watermarkText'] as String?,
    );
  }
}
