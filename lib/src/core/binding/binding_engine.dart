import 'package:mcp_bundle/mcp_bundle.dart';

import 'binding_exceptions.dart';
import 'binding_resolver.dart';

/// Status of a single field binding.
enum FieldBindingStatus { unbound, bound, unfilled }

/// A successfully resolved binding.
class BoundField {
  const BoundField({
    required this.fieldPath,
    required this.source,
    required this.value,
    required this.resolvedAt,
  });

  final String fieldPath;
  final FormDataSourceType source;
  final dynamic value;
  final DateTime resolvedAt;
}

/// A binding that could not be resolved.
class UnfilledField {
  const UnfilledField({
    required this.fieldPath,
    required this.source,
    required this.reason,
    required this.errorCode,
  });

  final String fieldPath;
  final FormDataSourceType source;
  final String reason;
  final String errorCode;
}

/// Result of binding resolution.
class BindingResult {
  const BindingResult({
    required this.boundDocument,
    this.boundFields = const [],
    this.unfilledFields = const [],
  });

  final FormDocument boundDocument;
  final List<BoundField> boundFields;
  final List<UnfilledField> unfilledFields;

  bool get hasUnfilled => unfilledFields.isNotEmpty;
  int get totalBindings => boundFields.length + unfilledFields.length;
  double get resolutionRate =>
      totalBindings > 0 ? boundFields.length / totalBindings : 1.0;
}

/// Orchestrates binding resolution across all data sources.
///
/// Never throws at the engine level — all failures are captured
/// as [UnfilledField] entries in the result.
class BindingEngine {
  const BindingEngine({required this.resolvers});

  final Map<FormDataSourceType, BindingResolver> resolvers;

  /// Resolve all bindings for a document.
  Future<BindingResult> resolve({
    required FormDocument document,
    required List<FormDataBinding> bindings,
  }) async {
    final boundFields = <BoundField>[];
    final unfilledFields = <UnfilledField>[];

    // Build a mutable JSON representation of the document
    final docJson = document.toJson();
    docJson.putIfAbsent('data', () => <String, dynamic>{});

    for (final binding in bindings) {
      final result = await _resolveSingleBinding(binding);
      if (result.bound != null) {
        boundFields.add(result.bound!);
        _setValueAtPath(docJson, binding.fieldPath, result.bound!.value);
      } else {
        unfilledFields.add(result.unfilled!);
      }
    }

    // Reconstruct document preserving all fields
    final boundDocument = FormDocument(
      documentId: document.documentId,
      templateId: document.templateId,
      templateVersion: document.templateVersion,
      metadata: FormDocumentMetadata(
        author: document.metadata.author,
        createdAt: document.metadata.createdAt,
        modifiedAt: DateTime.now(),
        publishedAt: document.metadata.publishedAt,
        dataSource: document.metadata.dataSource,
        engineVersion: document.metadata.engineVersion,
      ),
      status: document.status,
      version: document.version,
      sections: document.sections,
      data: docJson['data'] as Map<String, dynamic>,
      bindings: document.bindings,
      validationIssues: document.validationIssues,
    );

    return BindingResult(
      boundDocument: boundDocument,
      boundFields: boundFields,
      unfilledFields: unfilledFields,
    );
  }

  /// Resolve a single binding and return the value.
  Future<dynamic> resolveSingle({
    required FormDocument document,
    required FormDataBinding binding,
  }) async {
    final result = await _resolveSingleBinding(binding);
    return result.bound?.value;
  }

  /// Re-attempt resolution for previously unfilled bindings.
  Future<BindingResult> resolveUnfilled({
    required BindingResult previousResult,
    required List<FormDataBinding> bindings,
  }) async {
    final unfilledPaths =
        previousResult.unfilledFields.map((u) => u.fieldPath).toSet();
    final retryBindings =
        bindings.where((b) => unfilledPaths.contains(b.fieldPath)).toList();

    if (retryBindings.isEmpty) return previousResult;

    final newBound = <BoundField>[...previousResult.boundFields];
    final newUnfilled = <UnfilledField>[];

    // Build mutable JSON from previous document
    final docJson = previousResult.boundDocument.toJson();
    docJson.putIfAbsent('data', () => <String, dynamic>{});

    for (final binding in retryBindings) {
      final result = await _resolveSingleBinding(binding);
      if (result.bound != null) {
        newBound.add(result.bound!);
        _setValueAtPath(docJson, binding.fieldPath, result.bound!.value);
      } else {
        newUnfilled.add(result.unfilled!);
      }
    }

    // Keep previously unfilled that weren't retried
    for (final u in previousResult.unfilledFields) {
      if (!unfilledPaths.contains(u.fieldPath) ||
          retryBindings.every((b) => b.fieldPath != u.fieldPath)) {
        newUnfilled.add(u);
      }
    }

    final doc = previousResult.boundDocument;
    final boundDocument = FormDocument(
      documentId: doc.documentId,
      templateId: doc.templateId,
      templateVersion: doc.templateVersion,
      metadata: FormDocumentMetadata(
        author: doc.metadata.author,
        createdAt: doc.metadata.createdAt,
        modifiedAt: DateTime.now(),
        publishedAt: doc.metadata.publishedAt,
        dataSource: doc.metadata.dataSource,
        engineVersion: doc.metadata.engineVersion,
      ),
      status: doc.status,
      version: doc.version,
      sections: doc.sections,
      data: docJson['data'] as Map<String, dynamic>,
      bindings: doc.bindings,
      validationIssues: doc.validationIssues,
    );

    return BindingResult(
      boundDocument: boundDocument,
      boundFields: newBound,
      unfilledFields: newUnfilled,
    );
  }

  /// Set a value at a JSON Pointer path within the document JSON.
  ///
  /// Supports paths like:
  /// - /data/fieldName -> sets value in data map
  /// - /sections/0/blocks/1/fields/name -> navigates nested structure
  void _setValueAtPath(
    Map<String, dynamic> docJson,
    String fieldPath,
    dynamic value,
  ) {
    final segments =
        fieldPath.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return;

    dynamic current = docJson;
    for (var i = 0; i < segments.length - 1; i++) {
      final seg = segments[i];
      if (current is Map<String, dynamic>) {
        current.putIfAbsent(seg, () => <String, dynamic>{});
        current = current[seg];
      } else if (current is List) {
        final idx = int.tryParse(seg);
        if (idx != null && idx >= 0 && idx < current.length) {
          current = current[idx];
        } else {
          return;
        }
      } else {
        return;
      }
    }

    final lastKey = segments.last;
    if (current is Map<String, dynamic>) {
      current[lastKey] = value;
    } else if (current is List) {
      final idx = int.tryParse(lastKey);
      if (idx != null && idx >= 0 && idx < current.length) {
        current[idx] = value;
      }
    }
  }

  Future<_BindingAttempt> _resolveSingleBinding(
    FormDataBinding binding,
  ) async {
    final resolver = resolvers[binding.source];
    if (resolver == null) {
      // Check for default value
      if (binding.defaultValue != null) {
        return _BindingAttempt.bound(BoundField(
          fieldPath: binding.fieldPath,
          source: binding.source,
          value: binding.defaultValue,
          resolvedAt: DateTime.now(),
        ));
      }
      return _BindingAttempt.unfilled(UnfilledField(
        fieldPath: binding.fieldPath,
        source: binding.source,
        reason: 'No resolver registered for source ${binding.source}',
        errorCode: 'binding.resolver_not_found',
      ));
    }

    try {
      final available = await resolver.isAvailable();
      if (!available) {
        if (binding.defaultValue != null) {
          return _BindingAttempt.bound(BoundField(
            fieldPath: binding.fieldPath,
            source: binding.source,
            value: binding.defaultValue,
            resolvedAt: DateTime.now(),
          ));
        }
        return _BindingAttempt.unfilled(UnfilledField(
          fieldPath: binding.fieldPath,
          source: binding.source,
          reason: 'Source ${binding.source} is unavailable',
          errorCode: 'binding.source_unavailable',
        ));
      }

      var value = await resolver.resolve(binding);

      // Apply transform if defined
      if (binding.transform != null && value != null) {
        value = _applyTransform(value, binding.transform!);
      }

      return _BindingAttempt.bound(BoundField(
        fieldPath: binding.fieldPath,
        source: binding.source,
        value: value,
        resolvedAt: DateTime.now(),
      ));
    } on BindingSourceUnavailableException {
      if (binding.defaultValue != null) {
        return _BindingAttempt.bound(BoundField(
          fieldPath: binding.fieldPath,
          source: binding.source,
          value: binding.defaultValue,
          resolvedAt: DateTime.now(),
        ));
      }
      return _BindingAttempt.unfilled(UnfilledField(
        fieldPath: binding.fieldPath,
        source: binding.source,
        reason: 'Source ${binding.source} is unavailable',
        errorCode: 'binding.source_unavailable',
      ));
    } on BindingMappingException catch (e) {
      if (binding.defaultValue != null) {
        return _BindingAttempt.bound(BoundField(
          fieldPath: binding.fieldPath,
          source: binding.source,
          value: binding.defaultValue,
          resolvedAt: DateTime.now(),
        ));
      }
      return _BindingAttempt.unfilled(UnfilledField(
        fieldPath: binding.fieldPath,
        source: binding.source,
        reason: e.message,
        errorCode: 'binding.mapping_failed',
      ));
    } on Exception {
      if (binding.defaultValue != null) {
        return _BindingAttempt.bound(BoundField(
          fieldPath: binding.fieldPath,
          source: binding.source,
          value: binding.defaultValue,
          resolvedAt: DateTime.now(),
        ));
      }
      return _BindingAttempt.unfilled(UnfilledField(
        fieldPath: binding.fieldPath,
        source: binding.source,
        reason: 'Unexpected error during resolution',
        errorCode: 'binding.mapping_failed',
      ));
    }
  }

  /// Simple transform: supports toString, toUpperCase, toLowerCase.
  ///
  /// On unknown or failed transform, emits an [UnfilledField] with
  /// error code 'binding.transform_failed' if it cannot fallback.
  /// For simplicity, returns the raw value on unknown transforms.
  dynamic _applyTransform(dynamic value, String transform) {
    try {
      return switch (transform) {
        'toString' => value.toString(),
        'toUpperCase' when value is String => value.toUpperCase(),
        'toLowerCase' when value is String => value.toLowerCase(),
        _ => value, // Unknown transform: return raw value
      };
    } on Exception {
      // Transform failure: return raw value
      return value;
    }
  }
}

class _BindingAttempt {
  const _BindingAttempt._({this.bound, this.unfilled});

  factory _BindingAttempt.bound(BoundField field) =>
      _BindingAttempt._(bound: field);

  factory _BindingAttempt.unfilled(UnfilledField field) =>
      _BindingAttempt._(unfilled: field);

  final BoundField? bound;
  final UnfilledField? unfilled;
}
