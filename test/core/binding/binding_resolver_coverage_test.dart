import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/core/binding/binding_exceptions.dart';
import 'package:mcp_form/src/core/binding/binding_resolver.dart';
import 'package:test/test.dart';

// Fake implementation of CanvasSceneProvider for testing.
class FakeCanvasSceneProvider implements CanvasSceneProvider {
  FakeCanvasSceneProvider({
    this.available = true,
    CanvasRenderResult? result,
  }) : _result = result ??
            const CanvasRenderResult(
              format: 'svg',
              mime: 'image/svg+xml',
              svg: '<svg/>',
            );

  final bool available;
  final CanvasRenderResult _result;

  String? lastTarget;
  String? lastMode;
  String? lastFormat;
  Map<String, dynamic>? lastViewport;

  @override
  Future<CanvasRenderResult> renderScene({
    required String target,
    required String mode,
    required String format,
    Map<String, dynamic>? viewport,
  }) async {
    lastTarget = target;
    lastMode = mode;
    lastFormat = format;
    lastViewport = viewport;
    return _result;
  }

  @override
  Future<bool> isAvailable() async => available;
}

void main() {
  group('CanvasRenderResult', () {
    test('constructs with format, mime, svg', () {
      const result = CanvasRenderResult(
        format: 'svg',
        mime: 'image/svg+xml',
        svg: '<svg><rect/></svg>',
      );
      expect(result.format, 'svg');
      expect(result.mime, 'image/svg+xml');
      expect(result.svg, '<svg><rect/></svg>');
      expect(result.bytes, isNull);
    });

    test('constructs with format, mime, bytes', () {
      const result = CanvasRenderResult(
        format: 'png',
        mime: 'image/png',
        bytes: [0x89, 0x50, 0x4e, 0x47],
      );
      expect(result.format, 'png');
      expect(result.mime, 'image/png');
      expect(result.bytes, [0x89, 0x50, 0x4e, 0x47]);
      expect(result.svg, isNull);
    });
  });

  group('CanvasBindingResolver', () {
    test('sourceType is canvas', () {
      final resolver = CanvasBindingResolver(FakeCanvasSceneProvider());
      expect(resolver.sourceType, FormDataSourceType.canvas);
    });

    test('resolve delegates to provider with dataPath as target', () async {
      final provider = FakeCanvasSceneProvider();
      final resolver = CanvasBindingResolver(provider);
      final binding = FormDataBinding(
        bindingId: 'b1',
        fieldPath: '/data/scene',
        dataPath: 'canvas://main',
        source: FormDataSourceType.canvas,
      );
      final result = await resolver.resolve(binding);
      expect(result, isA<CanvasRenderResult>());
      expect(provider.lastTarget, 'canvas://main');
      // Default mode and format when toolParams is null.
      expect(provider.lastMode, 'canvas');
      expect(provider.lastFormat, 'svg');
      expect(provider.lastViewport, isNull);
    });

    test('resolve uses sourceQuery over dataPath when present', () async {
      final provider = FakeCanvasSceneProvider();
      final resolver = CanvasBindingResolver(provider);
      final binding = FormDataBinding(
        bindingId: 'b2',
        fieldPath: '/data/scene',
        dataPath: 'canvas://fallback',
        source: FormDataSourceType.canvas,
        sourceQuery: 'canvas://schematic.main',
      );
      await resolver.resolve(binding);
      expect(provider.lastTarget, 'canvas://schematic.main');
    });

    test('resolve passes toolParams hints through', () async {
      final provider = FakeCanvasSceneProvider();
      final resolver = CanvasBindingResolver(provider);
      final binding = FormDataBinding(
        bindingId: 'b3',
        fieldPath: '/data/scene',
        dataPath: 'canvas://scene',
        source: FormDataSourceType.canvas,
        toolParams: {
          'mode': 'ui',
          'format': 'png',
          'viewport': {'width': 800, 'height': 600},
        },
      );
      await resolver.resolve(binding);
      expect(provider.lastMode, 'ui');
      expect(provider.lastFormat, 'png');
      expect(provider.lastViewport, {'width': 800, 'height': 600});
    });

    test('throws BindingSourceUnavailableException when provider unavailable',
        () {
      final provider = FakeCanvasSceneProvider(available: false);
      final resolver = CanvasBindingResolver(provider);
      final binding = FormDataBinding(
        bindingId: 'b4',
        fieldPath: '/data/scene',
        dataPath: 'canvas://scene',
        source: FormDataSourceType.canvas,
      );
      expect(
        () => resolver.resolve(binding),
        throwsA(isA<BindingSourceUnavailableException>()),
      );
    });

    test('isAvailable delegates to provider', () async {
      final available = CanvasBindingResolver(FakeCanvasSceneProvider());
      final unavailable = CanvasBindingResolver(
        FakeCanvasSceneProvider(available: false),
      );
      expect(await available.isAvailable(), isTrue);
      expect(await unavailable.isAvailable(), isFalse);
    });
  });
}
