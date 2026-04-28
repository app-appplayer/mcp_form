import 'package:mcp_bundle/mcp_bundle.dart';

/// Options for rendering a document.
class RenderOptions {
  const RenderOptions({
    this.includeMetadata = false,
    this.applyWatermark = false,
    this.watermarkText,
  });

  final bool includeMetadata;
  final bool applyWatermark;
  final String? watermarkText;
}

/// Context passed to renderers during rendering.
class RenderContext {
  const RenderContext({
    required this.document,
    required this.layoutPolicy,
    required this.template,
    this.options = const RenderOptions(),
  });

  final FormDocument document;
  final FormLayoutPolicy layoutPolicy;
  final FormTemplate template;
  final RenderOptions options;

  String? get effectiveWatermark =>
      options.applyWatermark ? options.watermarkText : null;
}
