import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/core/binding/binding_exceptions.dart';
import 'package:mcp_form/src/core/binding/binding_resolver.dart';
import 'package:test/test.dart';

// Fake providers for testing

class FakeToolResultProvider implements ToolResultProvider {
  FakeToolResultProvider({
    this.available = true,
    this.result,
  });

  final bool available;
  final dynamic result;

  String? lastToolName;
  Map<String, dynamic>? lastArgs;

  @override
  Future<dynamic> executeAndGetResult(
    String toolName,
    Map<String, dynamic> args,
  ) async {
    lastToolName = toolName;
    lastArgs = args;
    return result;
  }

  @override
  Future<bool> isAvailable() async => available;
}

class FakeFactGraphQueryProvider implements FactGraphQueryProvider {
  FakeFactGraphQueryProvider({
    this.available = true,
    this.result,
  });

  final bool available;
  final dynamic result;

  String? lastQuery;
  Map<String, dynamic>? lastParams;

  @override
  Future<dynamic> queryFacts(
    String query,
    Map<String, dynamic> params,
  ) async {
    lastQuery = query;
    lastParams = params;
    return result;
  }

  @override
  Future<bool> isAvailable() async => available;
}

class FakeAnalysisResultProvider implements AnalysisResultProvider {
  FakeAnalysisResultProvider({
    this.available = true,
    this.result,
  });

  final bool available;
  final dynamic result;

  String? lastQuery;
  Map<String, dynamic>? lastParams;

  @override
  Future<dynamic> getResult(
    String query,
    Map<String, dynamic> params,
  ) async {
    lastQuery = query;
    lastParams = params;
    return result;
  }

  @override
  Future<bool> isAvailable() async => available;
}

void main() {
  group('UserInputBindingResolver', () {
    test('sourceType is userInput', () {
      const resolver = UserInputBindingResolver({});
      expect(resolver.sourceType, FormDataSourceType.userInput);
    });

    test('resolves value from user data', () async {
      const resolver = UserInputBindingResolver({'name': 'Alice'});
      final binding = FormDataBinding(
        bindingId: 'b1',
        fieldPath: '/data/name',
        dataPath: 'name',
        source: FormDataSourceType.userInput,
      );
      final value = await resolver.resolve(binding);
      expect(value, 'Alice');
    });

    test('throws BindingMappingException when key not found', () async {
      const resolver = UserInputBindingResolver({});
      final binding = FormDataBinding(
        bindingId: 'b1',
        fieldPath: '/data/name',
        dataPath: 'missing',
        source: FormDataSourceType.userInput,
      );
      expect(
        () => resolver.resolve(binding),
        throwsA(isA<BindingMappingException>()),
      );
    });

    test('isAvailable always returns true', () async {
      const resolver = UserInputBindingResolver({});
      expect(await resolver.isAvailable(), isTrue);
    });
  });

  group('ToolBindingResolver', () {
    test('sourceType is tool', () {
      final resolver = ToolBindingResolver(FakeToolResultProvider());
      expect(resolver.sourceType, FormDataSourceType.tool);
    });

    test('resolves using toolName and toolParams', () async {
      final provider = FakeToolResultProvider(result: 'tool-result');
      final resolver = ToolBindingResolver(provider);
      final binding = FormDataBinding(
        bindingId: 'b1',
        fieldPath: '/data/x',
        dataPath: 'fallbackPath',
        source: FormDataSourceType.tool,
        toolName: 'myTool',
        toolParams: {'key': 'val'},
      );
      final value = await resolver.resolve(binding);
      expect(value, 'tool-result');
      expect(provider.lastToolName, 'myTool');
      expect(provider.lastArgs, {'key': 'val'});
    });

    test('falls back to dataPath when toolName is null', () async {
      final provider = FakeToolResultProvider(result: 42);
      final resolver = ToolBindingResolver(provider);
      final binding = FormDataBinding(
        bindingId: 'b1',
        fieldPath: '/data/x',
        dataPath: 'fallbackTool',
        source: FormDataSourceType.tool,
      );
      final value = await resolver.resolve(binding);
      expect(value, 42);
      expect(provider.lastToolName, 'fallbackTool');
      expect(provider.lastArgs, <String, dynamic>{});
    });

    test('throws BindingSourceUnavailableException when unavailable',
        () async {
      final provider = FakeToolResultProvider(available: false);
      final resolver = ToolBindingResolver(provider);
      final binding = FormDataBinding(
        bindingId: 'b1',
        fieldPath: '/data/x',
        dataPath: 'tool',
        source: FormDataSourceType.tool,
      );
      expect(
        () => resolver.resolve(binding),
        throwsA(isA<BindingSourceUnavailableException>()),
      );
    });

    test('isAvailable delegates to provider', () async {
      final available = ToolBindingResolver(
        FakeToolResultProvider(available: true),
      );
      final unavailable = ToolBindingResolver(
        FakeToolResultProvider(available: false),
      );
      expect(await available.isAvailable(), isTrue);
      expect(await unavailable.isAvailable(), isFalse);
    });
  });

  group('FactGraphBindingResolver', () {
    test('sourceType is factgraph', () {
      final resolver = FactGraphBindingResolver(
        FakeFactGraphQueryProvider(),
      );
      expect(resolver.sourceType, FormDataSourceType.factgraph);
    });

    test('resolves using sourceQuery and toolParams', () async {
      final provider = FakeFactGraphQueryProvider(result: 'fact-data');
      final resolver = FactGraphBindingResolver(provider);
      final binding = FormDataBinding(
        bindingId: 'b1',
        fieldPath: '/data/x',
        dataPath: 'fallbackPath',
        source: FormDataSourceType.factgraph,
        sourceQuery: 'myQuery',
        toolParams: {'p': 1},
      );
      final value = await resolver.resolve(binding);
      expect(value, 'fact-data');
      expect(provider.lastQuery, 'myQuery');
      expect(provider.lastParams, {'p': 1});
    });

    test('falls back to dataPath when sourceQuery is null', () async {
      final provider = FakeFactGraphQueryProvider(result: 'data');
      final resolver = FactGraphBindingResolver(provider);
      final binding = FormDataBinding(
        bindingId: 'b1',
        fieldPath: '/data/x',
        dataPath: 'fallbackQuery',
        source: FormDataSourceType.factgraph,
      );
      final value = await resolver.resolve(binding);
      expect(value, 'data');
      expect(provider.lastQuery, 'fallbackQuery');
      expect(provider.lastParams, <String, dynamic>{});
    });

    test('throws BindingSourceUnavailableException when unavailable',
        () async {
      final provider = FakeFactGraphQueryProvider(available: false);
      final resolver = FactGraphBindingResolver(provider);
      final binding = FormDataBinding(
        bindingId: 'b1',
        fieldPath: '/data/x',
        dataPath: 'q',
        source: FormDataSourceType.factgraph,
      );
      expect(
        () => resolver.resolve(binding),
        throwsA(isA<BindingSourceUnavailableException>()),
      );
    });

    test('isAvailable delegates to provider', () async {
      final available = FactGraphBindingResolver(
        FakeFactGraphQueryProvider(available: true),
      );
      final unavailable = FactGraphBindingResolver(
        FakeFactGraphQueryProvider(available: false),
      );
      expect(await available.isAvailable(), isTrue);
      expect(await unavailable.isAvailable(), isFalse);
    });
  });

  group('AnalysisBindingResolver', () {
    test('sourceType is analysis', () {
      final resolver = AnalysisBindingResolver(
        FakeAnalysisResultProvider(),
      );
      expect(resolver.sourceType, FormDataSourceType.analysis);
    });

    test('resolves using sourceQuery and toolParams', () async {
      final provider = FakeAnalysisResultProvider(result: 'analysis-data');
      final resolver = AnalysisBindingResolver(provider);
      final binding = FormDataBinding(
        bindingId: 'b1',
        fieldPath: '/data/x',
        dataPath: 'fallbackPath',
        source: FormDataSourceType.analysis,
        sourceQuery: 'analysisQuery',
        toolParams: {'a': 'b'},
      );
      final value = await resolver.resolve(binding);
      expect(value, 'analysis-data');
      expect(provider.lastQuery, 'analysisQuery');
      expect(provider.lastParams, {'a': 'b'});
    });

    test('falls back to dataPath when sourceQuery is null', () async {
      final provider = FakeAnalysisResultProvider(result: 99);
      final resolver = AnalysisBindingResolver(provider);
      final binding = FormDataBinding(
        bindingId: 'b1',
        fieldPath: '/data/x',
        dataPath: 'fallbackAnalysis',
        source: FormDataSourceType.analysis,
      );
      final value = await resolver.resolve(binding);
      expect(value, 99);
      expect(provider.lastQuery, 'fallbackAnalysis');
      expect(provider.lastParams, <String, dynamic>{});
    });

    test('throws BindingSourceUnavailableException when unavailable',
        () async {
      final provider = FakeAnalysisResultProvider(available: false);
      final resolver = AnalysisBindingResolver(provider);
      final binding = FormDataBinding(
        bindingId: 'b1',
        fieldPath: '/data/x',
        dataPath: 'q',
        source: FormDataSourceType.analysis,
      );
      expect(
        () => resolver.resolve(binding),
        throwsA(isA<BindingSourceUnavailableException>()),
      );
    });

    test('isAvailable delegates to provider', () async {
      final available = AnalysisBindingResolver(
        FakeAnalysisResultProvider(available: true),
      );
      final unavailable = AnalysisBindingResolver(
        FakeAnalysisResultProvider(available: false),
      );
      expect(await available.isAvailable(), isTrue);
      expect(await unavailable.isAvailable(), isFalse);
    });
  });
}
