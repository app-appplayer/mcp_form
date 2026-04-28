import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderer_registry.dart';
import 'package:test/test.dart';

class MockRenderer implements DocumentRenderer {
  MockRenderer(this.supportedFormats, {this.supportedTemplateRange});

  @override
  final List<String> supportedFormats;

  @override
  final String? supportedTemplateRange;

  int renderCount = 0;

  @override
  Future<FormRenderOutput> render(RenderContext context) async {
    renderCount++;
    return FormRenderOutput(
      format: supportedFormats.first,
      content: <int>[],
      pageCount: 1,
      generatedAt: DateTime(2026),
    );
  }
}

/// Renderer that throws a FormError on render.
class FormErrorRenderer implements DocumentRenderer {
  @override
  final List<String> supportedFormats = const ['err'];

  @override
  String? get supportedTemplateRange => null;

  @override
  Future<FormRenderOutput> render(RenderContext context) async {
    throw FormError(
      code: 'render.custom_error',
      message: 'Intentional FormError',
    );
  }
}

/// Renderer that throws a generic exception on render.
class GenericErrorRenderer implements DocumentRenderer {
  @override
  final List<String> supportedFormats = const ['gerr'];

  @override
  String? get supportedTemplateRange => null;

  @override
  Future<FormRenderOutput> render(RenderContext context) async {
    throw StateError('something went wrong');
  }
}

FormTemplate _makeTemplate() {
  return FormTemplate(
    templateId: 'tpl-1',
    version: '1.0.0',
    name: 'Test',
    schema: const FormSchema(),
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
  group('RendererRegistry', () {
    // TC-283: Register renderer
    test('register makes format available', () {
      final registry = RendererRegistry();
      registry.register(MockRenderer(['html']));

      expect(registry.isFormatSupported('html'), isTrue);
      expect(registry.registeredFormats, contains('html'));
    });

    // TC-284: Unregister renderer
    test('unregister removes format', () {
      final registry = RendererRegistry();
      registry.register(MockRenderer(['html']));
      final removed = registry.unregister('html');

      expect(removed, isTrue);
      expect(registry.isFormatSupported('html'), isFalse);
    });

    // TC-285: Unregister non-existent
    test('unregister returns false for unknown format', () {
      final registry = RendererRegistry();
      expect(registry.unregister('pdf'), isFalse);
    });

    // TC-286: Re-register (last-write-wins)
    test('re-register replaces renderer', () {
      final registry = RendererRegistry();
      final first = MockRenderer(['html']);
      final second = MockRenderer(['html']);
      registry.register(first);
      registry.register(second);

      expect(registry.getRenderer('html'), same(second));
    });

    // TC-287: Multiple formats
    test('supports multiple formats', () {
      final registry = RendererRegistry();
      registry.register(MockRenderer(['html']));
      registry.register(MockRenderer(['markdown']));

      expect(registry.registeredFormats.length, 2);
    });

    // TC-289: getRenderer
    test('getRenderer returns null for unknown format', () {
      final registry = RendererRegistry();
      expect(registry.getRenderer('pdf'), isNull);
    });

    // TC-292: Dispatch to renderer
    test('render dispatches to correct renderer', () async {
      final registry = RendererRegistry();
      final renderer = MockRenderer(['html']);
      registry.register(renderer);

      await registry.render(
        document: _makeDoc(),
        template: _makeTemplate(),
        format: 'html',
      );

      expect(renderer.renderCount, 1);
    });

    // TC-293: Unsupported format throws
    test('render throws for unsupported format', () {
      final registry = RendererRegistry();

      expect(
        () => registry.render(
          document: _makeDoc(),
          template: _makeTemplate(),
          format: 'pdf',
        ),
        throwsA(isA<FormError>().having(
          (e) => e.code,
          'code',
          'render.unsupported_format',
        )),
      );
    });

    // TC: Register renderer with empty supportedFormats
    test('register throws for renderer with no supported formats', () {
      final registry = RendererRegistry();

      expect(
        () => registry.register(MockRenderer([])),
        throwsA(isA<FormError>().having(
          (e) => e.code,
          'code',
          'render.invalid_renderer',
        )),
      );
    });

    // TC: FormError from renderer is rethrown as-is
    test('render rethrows FormError from renderer', () {
      final registry = RendererRegistry();
      registry.register(FormErrorRenderer());

      expect(
        () => registry.render(
          document: _makeDoc(),
          template: _makeTemplate(),
          format: 'err',
        ),
        throwsA(isA<FormError>().having(
          (e) => e.code,
          'code',
          'render.custom_error',
        )),
      );
    });

    // TC: Generic exception from renderer is wrapped in FormError
    test('render wraps non-FormError exception in render.failed', () {
      final registry = RendererRegistry();
      registry.register(GenericErrorRenderer());

      expect(
        () => registry.render(
          document: _makeDoc(),
          template: _makeTemplate(),
          format: 'gerr',
        ),
        throwsA(isA<FormError>().having(
          (e) => e.code,
          'code',
          'render.failed',
        )),
      );
    });

    // TC: Version compatibility check rejects incompatible template version
    test('render throws for incompatible template version', () {
      final registry = RendererRegistry();
      registry.register(
        MockRenderer(['html'], supportedTemplateRange: '>= 1.0.0 < 2.0.0'),
      );

      final incompatibleTemplate = FormTemplate(
        templateId: 'tpl-1',
        version: '3.0.0',
        name: 'Test',
        schema: const FormSchema(),
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

      expect(
        () => registry.render(
          document: _makeDoc(),
          template: incompatibleTemplate,
          format: 'html',
        ),
        throwsA(isA<FormError>().having(
          (e) => e.code,
          'code',
          'render.incompatible_version',
        )),
      );
    });

    // TC: Version compatibility check allows compatible template version
    test('render succeeds for compatible template version', () async {
      final registry = RendererRegistry();
      final renderer = MockRenderer(
        ['html'],
        supportedTemplateRange: '>= 1.0.0 < 2.0.0',
      );
      registry.register(renderer);

      await registry.render(
        document: _makeDoc(),
        template: _makeTemplate(),
        format: 'html',
      );

      expect(renderer.renderCount, 1);
    });

    // TC: Renderer with null supportedTemplateRange accepts any version
    test('render succeeds when supportedTemplateRange is null', () async {
      final registry = RendererRegistry();
      final renderer = MockRenderer(['html']);
      registry.register(renderer);

      final v3Template = FormTemplate(
        templateId: 'tpl-1',
        version: '3.0.0',
        name: 'Test',
        schema: const FormSchema(),
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

      await registry.render(
        document: _makeDoc(),
        template: v3Template,
        format: 'html',
      );

      expect(renderer.renderCount, 1);
    });
  });
}
