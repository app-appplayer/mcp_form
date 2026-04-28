import 'package:mcp_bundle/mcp_bundle.dart';

import 'binding_exceptions.dart';

/// Abstract resolver for a specific binding source type.
abstract class BindingResolver {
  /// The source type this resolver handles.
  FormDataSourceType get sourceType;

  /// Resolve a binding to a value.
  ///
  /// Throws [BindingSourceUnavailableException] if source is unavailable.
  /// Throws [BindingMappingException] if mapping fails.
  Future<dynamic> resolve(FormDataBinding binding);

  /// Check whether the source is currently available.
  Future<bool> isAvailable();
}

/// Provides tool execution results for binding resolution.
abstract class ToolResultProvider {
  Future<dynamic> executeAndGetResult(
    String toolName,
    Map<String, dynamic> args,
  );
  Future<bool> isAvailable();
}

/// Provides analysis results for binding resolution.
abstract class AnalysisResultProvider {
  Future<dynamic> getResult(String query, Map<String, dynamic> params);
  Future<bool> isAvailable();
}

/// Resolves bindings from user-provided input data.
class UserInputBindingResolver implements BindingResolver {
  const UserInputBindingResolver(this._userData);

  final Map<String, dynamic> _userData;

  @override
  FormDataSourceType get sourceType => FormDataSourceType.userInput;

  @override
  Future<dynamic> resolve(FormDataBinding binding) async {
    final value = _userData[binding.dataPath];
    if (value == null) {
      throw BindingMappingException(
        'No user data found for path "${binding.dataPath}"',
      );
    }
    return value;
  }

  @override
  Future<bool> isAvailable() async => true;
}

/// Resolves bindings from tool execution results.
class ToolBindingResolver implements BindingResolver {
  const ToolBindingResolver(this._provider);

  final ToolResultProvider _provider;

  @override
  FormDataSourceType get sourceType => FormDataSourceType.tool;

  @override
  Future<dynamic> resolve(FormDataBinding binding) async {
    if (!await _provider.isAvailable()) {
      throw const BindingSourceUnavailableException('tool');
    }
    return _provider.executeAndGetResult(
      binding.toolName ?? binding.dataPath,
      binding.toolParams ?? {},
    );
  }

  @override
  Future<bool> isAvailable() => _provider.isAvailable();
}

/// Provides FactGraph query results for binding resolution.
abstract class FactGraphQueryProvider {
  Future<dynamic> queryFacts(String query, Map<String, dynamic> params);
  Future<bool> isAvailable();
}

/// Resolves bindings from FactGraph query results.
class FactGraphBindingResolver implements BindingResolver {
  const FactGraphBindingResolver(this._provider);

  final FactGraphQueryProvider _provider;

  @override
  FormDataSourceType get sourceType => FormDataSourceType.factgraph;

  @override
  Future<dynamic> resolve(FormDataBinding binding) async {
    if (!await _provider.isAvailable()) {
      throw const BindingSourceUnavailableException('factgraph');
    }
    return _provider.queryFacts(
      binding.sourceQuery ?? binding.dataPath,
      binding.toolParams ?? {},
    );
  }

  @override
  Future<bool> isAvailable() => _provider.isAvailable();
}

/// Resolves bindings from analysis service results.
class AnalysisBindingResolver implements BindingResolver {
  const AnalysisBindingResolver(this._provider);

  final AnalysisResultProvider _provider;

  @override
  FormDataSourceType get sourceType => FormDataSourceType.analysis;

  @override
  Future<dynamic> resolve(FormDataBinding binding) async {
    if (!await _provider.isAvailable()) {
      throw const BindingSourceUnavailableException('analysis');
    }
    return _provider.getResult(
      binding.sourceQuery ?? binding.dataPath,
      binding.toolParams ?? {},
    );
  }

  @override
  Future<bool> isAvailable() => _provider.isAvailable();
}

/// Rendered bytes of a canvas scene for a given [format].
class CanvasRenderResult {
  const CanvasRenderResult({
    required this.format,
    required this.mime,
    this.svg,
    this.bytes,
  });

  /// Format actually produced — may differ from the requested format if the
  /// provider downgraded (e.g. `'svg'` → `'png'`).
  final String format;

  /// MIME type of the payload (`image/svg+xml` · `image/png` · …).
  final String mime;

  /// SVG source as string, when [format] == `'svg'`.
  final String? svg;

  /// Binary payload for raster / vector-binary formats (`png`, `pdf-vector`).
  final List<int>? bytes;
}

/// Provides live rendering of a canvas scene referenced by a `canvas://`
/// URI. Implementations live in the host (e.g. Designer's FormAdapter wires
/// one that delegates to `DesignerServer.internalRender`).
abstract class CanvasSceneProvider {
  /// Render [target] (a `canvas://...` URI) in [mode] at the requested
  /// [format]. [viewport] is an opaque hint map carried through from
  /// `FormCanvasBlock.viewport`. May throw to signal a hard failure —
  /// in which case the caller must either use the block's `fallback`
  /// strategy or surface an UnfilledField.
  Future<CanvasRenderResult> renderScene({
    required String target,
    required String mode,
    required String format,
    Map<String, dynamic>? viewport,
  });

  Future<bool> isAvailable();
}

/// Resolves `canvas://` bindings by delegating to a [CanvasSceneProvider].
///
/// The binding's [FormDataBinding.dataPath] is expected to contain the
/// `canvas://` URI (typically copied from the enclosing
/// `FormCanvasBlock.target`). [FormDataBinding.toolParams] carries the
/// `mode` / `format` / `viewport` hints — providers that ignore unknown
/// keys are fine.
class CanvasBindingResolver implements BindingResolver {
  const CanvasBindingResolver(this._provider);

  final CanvasSceneProvider _provider;

  @override
  FormDataSourceType get sourceType => FormDataSourceType.canvas;

  @override
  Future<dynamic> resolve(FormDataBinding binding) async {
    if (!await _provider.isAvailable()) {
      throw const BindingSourceUnavailableException('canvas');
    }
    final hints = binding.toolParams ?? const <String, dynamic>{};
    return _provider.renderScene(
      target: binding.sourceQuery ?? binding.dataPath,
      mode: (hints['mode'] as String?) ?? 'canvas',
      format: (hints['format'] as String?) ?? 'svg',
      viewport: hints['viewport'] as Map<String, dynamic>?,
    );
  }

  @override
  Future<bool> isAvailable() => _provider.isAvailable();
}
