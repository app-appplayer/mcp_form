import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/adapters/form_renderer_port_impl.dart';
import 'package:mcp_form/src/adapters/form_template_port_impl.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderer_registry.dart';
import 'package:test/test.dart';

class MockRenderer implements DocumentRenderer {
  @override
  final List<String> supportedFormats = ['html'];

  @override
  String? get supportedTemplateRange => null;

  @override
  Future<FormRenderOutput> render(RenderContext context) async {
    return FormRenderOutput(
      format: 'html',
      content: '<p>rendered</p>',
      pageCount: 1,
      generatedAt: DateTime(2026),
    );
  }
}

FormTemplate _makeTemplate() {
  return FormTemplate(
    templateId: 'tpl-1',
    version: '1.0.0',
    name: 'Test',
    schema: FormSchema(fields: [
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

FormDocument _makeDoc() {
  return FormDocument(
    documentId: 'doc-1',
    templateId: 'tpl-1',
    templateVersion: '1.0.0',
    metadata: FormDocumentMetadata(
      author: 'tester',
      createdAt: DateTime(2026),
    ),
  );
}

void main() {
  group('FormRendererPortImpl', () {
    late FormTemplatePortImpl templatePort;
    late RendererRegistry registry;
    late FormRendererPortImpl port;

    setUp(() async {
      templatePort = FormTemplatePortImpl();
      await templatePort.saveTemplate(template: _makeTemplate());

      registry = RendererRegistry();
      registry.register(MockRenderer());

      port = FormRendererPortImpl(
        registry: registry,
        templatePort: templatePort,
      );
    });

    // --- render ---

    test('render delegates to registry and returns output', () async {
      final result = await port.render(
        document: _makeDoc(),
        format: 'html',
      );

      expect(result.success, isTrue);
      expect(result.data?.format, 'html');
      expect(result.data?.content, '<p>rendered</p>');
    });

    test('render fails for unsupported format', () async {
      final result = await port.render(
        document: _makeDoc(),
        format: 'pdf',
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'render.unsupported_format');
    });

    test('render fails for non-existent template', () async {
      final doc = FormDocument(
        documentId: 'doc-1',
        templateId: 'unknown',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
      );

      final result = await port.render(document: doc, format: 'html');
      expect(result.success, isFalse);
      expect(result.error?.code, 'render.template_not_found');
    });

    test('render passes options to renderer', () async {
      final result = await port.render(
        document: _makeDoc(),
        format: 'html',
        options: {'includeMetadata': true, 'applyWatermark': true},
      );

      expect(result.success, isTrue);
    });

    // --- supportedFormats ---

    test('supportedFormats returns registered formats', () {
      expect(port.supportedFormats(), contains('html'));
    });

    test('supportedFormats reflects registry state', () {
      registry.register(MockMarkdownRenderer());
      expect(port.supportedFormats(), containsAll(['html', 'markdown']));
    });

    // --- getMetadata ---

    test('getMetadata returns renderer info', () {
      final meta = port.getMetadata();
      expect(meta.rendererId, 'mcp_form');
      expect(meta.version, '0.1.0');
      expect(meta.supportedFormats, contains('html'));
    });

    test('getMetadata uses custom rendererId', () {
      final customPort = FormRendererPortImpl(
        registry: registry,
        templatePort: templatePort,
        rendererId: 'custom-renderer',
        version: '2.0.0',
      );

      final meta = customPort.getMetadata();
      expect(meta.rendererId, 'custom-renderer');
      expect(meta.version, '2.0.0');
    });

    // --- render catches FormError thrown by renderer ---

    test('render returns fail result when renderer throws FormError', () async {
      final errorRegistry = RendererRegistry();
      errorRegistry.register(ErrorThrowingRenderer());

      final errorPort = FormRendererPortImpl(
        registry: errorRegistry,
        templatePort: templatePort,
      );

      final result = await errorPort.render(
        document: _makeDoc(),
        format: 'html',
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'render.custom_error');
    });
  });
}

class ErrorThrowingRenderer implements DocumentRenderer {
  @override
  final List<String> supportedFormats = ['html'];

  @override
  String? get supportedTemplateRange => null;

  @override
  Future<FormRenderOutput> render(RenderContext context) async {
    throw FormError(
      code: 'render.custom_error',
      message: 'Rendering failed intentionally',
    );
  }
}

class MockMarkdownRenderer implements DocumentRenderer {
  @override
  final List<String> supportedFormats = ['markdown'];

  @override
  String? get supportedTemplateRange => null;

  @override
  Future<FormRenderOutput> render(RenderContext context) async {
    return FormRenderOutput(
      format: 'markdown',
      content: '# Hello',
      pageCount: 1,
      generatedAt: DateTime(2026),
    );
  }
}
