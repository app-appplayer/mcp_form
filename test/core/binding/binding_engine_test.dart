import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/core/binding/binding_engine.dart';
import 'package:mcp_form/src/core/binding/binding_exceptions.dart';
import 'package:mcp_form/src/core/binding/binding_resolver.dart';
import 'package:test/test.dart';

FormDocument _makeDoc([Map<String, dynamic> data = const {}]) {
  return FormDocument(
    documentId: 'doc-1',
    templateId: 'tpl-1',
    templateVersion: '1.0.0',
    metadata: FormDocumentMetadata(
      author: 'tester',
      createdAt: DateTime(2026),
    ),
    data: data,
  );
}

/// Mock resolver that returns static values.
class MockResolver implements BindingResolver {
  MockResolver(this.sourceType, this._values, {this.available = true});

  @override
  final FormDataSourceType sourceType;
  final Map<String, dynamic> _values;
  final bool available;

  @override
  Future<dynamic> resolve(FormDataBinding binding) async {
    final val = _values[binding.dataPath];
    if (val == null) {
      throw BindingMappingException('No value for ${binding.dataPath}');
    }
    return val;
  }

  @override
  Future<bool> isAvailable() async => available;
}

/// Object whose toString() throws an Exception to test transform error path.
class _BadToString {
  @override
  String toString() => throw Exception('toString failed');
}

/// Mock resolver that throws BindingSourceUnavailableException on resolve.
class UnavailableThrowingResolver implements BindingResolver {
  const UnavailableThrowingResolver();

  @override
  FormDataSourceType get sourceType => FormDataSourceType.tool;

  @override
  Future<dynamic> resolve(FormDataBinding binding) async {
    throw const BindingSourceUnavailableException('tool');
  }

  @override
  Future<bool> isAvailable() async => true;
}

/// Mock resolver that throws a generic Exception on resolve.
class GenericExceptionResolver implements BindingResolver {
  const GenericExceptionResolver();

  @override
  FormDataSourceType get sourceType => FormDataSourceType.tool;

  @override
  Future<dynamic> resolve(FormDataBinding binding) async {
    throw Exception('something went wrong');
  }

  @override
  Future<bool> isAvailable() async => true;
}

void main() {
  group('BindingEngine - resolve', () {
    // TC-203: User input binding
    test('resolves user input binding', () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.userInput: MockResolver(
          FormDataSourceType.userInput,
          {'userName': 'Alice'},
        ),
      });

      final result = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/name',
            dataPath: 'userName',
            source: FormDataSourceType.userInput,
          ),
        ],
      );

      expect(result.boundFields.length, 1);
      expect(result.boundFields[0].value, 'Alice');
      expect(result.hasUnfilled, isFalse);
      expect(result.resolutionRate, 1.0);
    });

    // TC-207: Unavailable source
    test('marks unfilled when source unavailable', () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.factgraph: MockResolver(
          FormDataSourceType.factgraph,
          {},
          available: false,
        ),
      });

      final result = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/name',
            dataPath: 'query',
            source: FormDataSourceType.factgraph,
          ),
        ],
      );

      expect(result.unfilledFields.length, 1);
      expect(
        result.unfilledFields[0].errorCode,
        'binding.source_unavailable',
      );
      expect(result.hasUnfilled, isTrue);
    });

    // TC-209: No resolver for source
    test('marks unfilled when no resolver registered', () async {
      const engine = BindingEngine(resolvers: {});

      final result = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/name',
            dataPath: 'query',
            source: FormDataSourceType.analysis,
          ),
        ],
      );

      expect(result.unfilledFields.length, 1);
      expect(
        result.unfilledFields[0].errorCode,
        'binding.resolver_not_found',
      );
    });

    // TC-210: Default value used on failure
    test('uses default value when resolution fails', () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.userInput: MockResolver(
          FormDataSourceType.userInput,
          {},
        ),
      });

      final result = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/name',
            dataPath: 'missing',
            source: FormDataSourceType.userInput,
            defaultValue: 'fallback',
          ),
        ],
      );

      expect(result.boundFields.length, 1);
      expect(result.boundFields[0].value, 'fallback');
      expect(result.hasUnfilled, isFalse);
    });

    // TC-211: Source isolation
    test('one source failure does not affect others', () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.userInput: MockResolver(
          FormDataSourceType.userInput,
          {'x': 'ok'},
        ),
        FormDataSourceType.factgraph: MockResolver(
          FormDataSourceType.factgraph,
          {},
          available: false,
        ),
      });

      final result = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/a',
            dataPath: 'x',
            source: FormDataSourceType.userInput,
          ),
          FormDataBinding(
            bindingId: 'b2',
            fieldPath: '/data/b',
            dataPath: 'y',
            source: FormDataSourceType.factgraph,
          ),
        ],
      );

      expect(result.boundFields.length, 1);
      expect(result.unfilledFields.length, 1);
    });

    // TC-219-221: Property calculations
    test('totalBindings and resolutionRate are correct', () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.userInput: MockResolver(
          FormDataSourceType.userInput,
          {'x': 1, 'y': 2},
        ),
      });

      final result = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/a',
            dataPath: 'x',
            source: FormDataSourceType.userInput,
          ),
          FormDataBinding(
            bindingId: 'b2',
            fieldPath: '/data/b',
            dataPath: 'missing',
            source: FormDataSourceType.analysis,
          ),
        ],
      );

      expect(result.totalBindings, 2);
      expect(result.resolutionRate, 0.5);
    });
  });

  group('BindingEngine - resolveSingle', () {
    // TC-212: Single resolution
    test('returns resolved value', () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.userInput: MockResolver(
          FormDataSourceType.userInput,
          {'key': 42},
        ),
      });

      final value = await engine.resolveSingle(
        document: _makeDoc(),
        binding: FormDataBinding(
          bindingId: 'b1',
          fieldPath: '/data/x',
          dataPath: 'key',
          source: FormDataSourceType.userInput,
        ),
      );

      expect(value, 42);
    });

    // TC-213: Unresolvable returns null
    test('returns null for unresolvable binding', () async {
      const engine = BindingEngine(resolvers: {});

      final value = await engine.resolveSingle(
        document: _makeDoc(),
        binding: FormDataBinding(
          bindingId: 'b1',
          fieldPath: '/data/x',
          dataPath: 'key',
          source: FormDataSourceType.analysis,
        ),
      );

      expect(value, isNull);
    });
  });

  group('BindingEngine - resolveUnfilled', () {
    // TC-214: Retry unfilled when source becomes available
    test('resolves previously unfilled bindings', () async {
      final failResolver = MockResolver(
        FormDataSourceType.factgraph,
        {'q': 'data'},
        available: false,
      );

      final engine = BindingEngine(resolvers: {
        FormDataSourceType.factgraph: failResolver,
      });

      final firstResult = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/x',
            dataPath: 'q',
            source: FormDataSourceType.factgraph,
          ),
        ],
      );

      expect(firstResult.hasUnfilled, isTrue);

      // Now source becomes available
      final successEngine = BindingEngine(resolvers: {
        FormDataSourceType.factgraph: MockResolver(
          FormDataSourceType.factgraph,
          {'q': 'resolved-data'},
        ),
      });

      final retryResult = await successEngine.resolveUnfilled(
        previousResult: firstResult,
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/x',
            dataPath: 'q',
            source: FormDataSourceType.factgraph,
          ),
        ],
      );

      expect(retryResult.hasUnfilled, isFalse);
      expect(retryResult.boundFields.length, 1);
      expect(retryResult.boundFields[0].value, 'resolved-data');
    });

    test('keeps unfilled when retry still fails', () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.factgraph: MockResolver(
          FormDataSourceType.factgraph,
          {},
          available: false,
        ),
      });

      final firstResult = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/x',
            dataPath: 'q',
            source: FormDataSourceType.factgraph,
          ),
        ],
      );

      expect(firstResult.hasUnfilled, isTrue);

      // Retry with same unavailable resolver
      final retryResult = await engine.resolveUnfilled(
        previousResult: firstResult,
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/x',
            dataPath: 'q',
            source: FormDataSourceType.factgraph,
          ),
        ],
      );

      expect(retryResult.hasUnfilled, isTrue);
      expect(retryResult.unfilledFields.length, 1);
    });

    test('preserves unfilled fields that were not retried', () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.userInput: MockResolver(
          FormDataSourceType.userInput,
          {'key': 'val'},
        ),
      });

      // Create a result with two unfilled fields
      final firstResult = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/a',
            dataPath: 'missing1',
            source: FormDataSourceType.analysis,
          ),
          FormDataBinding(
            bindingId: 'b2',
            fieldPath: '/data/b',
            dataPath: 'missing2',
            source: FormDataSourceType.tool,
          ),
        ],
      );

      expect(firstResult.unfilledFields.length, 2);

      // Retry only one of them (b1), the other (b2) is not in bindings list
      final retryResult = await engine.resolveUnfilled(
        previousResult: firstResult,
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/a',
            dataPath: 'missing1',
            source: FormDataSourceType.analysis,
          ),
        ],
      );

      // b1 retried but still fails, b2 not retried but preserved
      expect(retryResult.unfilledFields.length, 2);
    });

    test('returns previous result when no unfilled match retry bindings',
        () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.userInput: MockResolver(
          FormDataSourceType.userInput,
          {'key': 'val'},
        ),
      });

      final firstResult = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/a',
            dataPath: 'key',
            source: FormDataSourceType.userInput,
          ),
        ],
      );

      expect(firstResult.hasUnfilled, isFalse);

      // Retry with bindings that don't match unfilled
      final retryResult = await engine.resolveUnfilled(
        previousResult: firstResult,
        bindings: [
          FormDataBinding(
            bindingId: 'b2',
            fieldPath: '/data/nomatch',
            dataPath: 'x',
            source: FormDataSourceType.userInput,
          ),
        ],
      );

      // Should return the same previous result unchanged
      expect(identical(retryResult, firstResult), isTrue);
    });
  });

  group('BindingEngine - _setValueAtPath with List navigation', () {
    test('navigates through List elements in path', () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.userInput: MockResolver(
          FormDataSourceType.userInput,
          {'val': 'hello'},
        ),
      });

      // Sections serializes as a List in toJson(); use path through it
      final doc = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
        sections: [
          FormSection(
            sectionId: 's1',
            index: 0,
            title: 'Section 1',
          ),
        ],
      );

      final result = await engine.resolve(
        document: doc,
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/sections/0/title',
            dataPath: 'val',
            source: FormDataSourceType.userInput,
          ),
        ],
      );

      // Successfully navigates List index and sets value in the Map element
      expect(result.boundFields.length, 1);
      expect(result.boundFields[0].value, 'hello');
    });

    test('handles invalid List index gracefully', () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.userInput: MockResolver(
          FormDataSourceType.userInput,
          {'val': 'hello'},
        ),
      });

      final doc = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
        sections: [
          FormSection(
            sectionId: 's1',
            index: 0,
          ),
        ],
      );

      // Path with out-of-bounds index should not crash
      final result = await engine.resolve(
        document: doc,
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/sections/99/value',
            dataPath: 'val',
            source: FormDataSourceType.userInput,
          ),
        ],
      );

      // Still bound but path write is silently skipped
      expect(result.boundFields.length, 1);
    });

    test('sets value at List index for last path segment', () async {
      // To test the case where the last segment targets a List element,
      // use data that contains a list with compatible element types.
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.userInput: MockResolver(
          FormDataSourceType.userInput,
          {'val': 'replaced'},
        ),
      });

      // Put a list directly in the data map so the path ends at a list index
      final doc = _makeDoc({
        'items': <dynamic>['original', 'second'],
      });

      // Path /data/items/0 targets a list element as the last segment
      final result = await engine.resolve(
        document: doc,
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/items/0',
            dataPath: 'val',
            source: FormDataSourceType.userInput,
          ),
        ],
      );

      expect(result.boundFields.length, 1);
      expect(result.boundFields[0].value, 'replaced');
      // Verify the value was set in the document data
      final items = result.boundDocument.data['items'] as List;
      expect(items[0], 'replaced');
    });

    test('handles non-parseable index on List gracefully', () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.userInput: MockResolver(
          FormDataSourceType.userInput,
          {'val': 'x'},
        ),
      });

      final doc = FormDocument(
        documentId: 'doc-1',
        templateId: 'tpl-1',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
        sections: [
          FormSection(
            sectionId: 's1',
            index: 0,
          ),
        ],
      );

      // Path /sections/abc targets a non-numeric index on a List
      final result = await engine.resolve(
        document: doc,
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/sections/abc/field',
            dataPath: 'val',
            source: FormDataSourceType.userInput,
          ),
        ],
      );

      // Binding resolves but write is skipped due to invalid index
      expect(result.boundFields.length, 1);
    });
  });

  group('BindingEngine - default values', () {
    test('uses default when no resolver registered', () async {
      const engine = BindingEngine(resolvers: {});

      final result = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/x',
            dataPath: 'key',
            source: FormDataSourceType.analysis,
            defaultValue: 'default-val',
          ),
        ],
      );

      expect(result.boundFields.length, 1);
      expect(result.boundFields[0].value, 'default-val');
      expect(result.hasUnfilled, isFalse);
    });

    test('uses default when source unavailable (pre-check)', () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.factgraph: MockResolver(
          FormDataSourceType.factgraph,
          {},
          available: false,
        ),
      });

      final result = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/x',
            dataPath: 'q',
            source: FormDataSourceType.factgraph,
            defaultValue: 'fallback-unavailable',
          ),
        ],
      );

      expect(result.boundFields.length, 1);
      expect(result.boundFields[0].value, 'fallback-unavailable');
    });

    test('uses default when resolver throws BindingSourceUnavailableException',
        () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.tool: const UnavailableThrowingResolver(),
      });

      final result = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/x',
            dataPath: 'key',
            source: FormDataSourceType.tool,
            defaultValue: 'default-from-exception',
          ),
        ],
      );

      expect(result.boundFields.length, 1);
      expect(result.boundFields[0].value, 'default-from-exception');
    });

    test('unfilled when BindingSourceUnavailableException and no default',
        () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.tool: const UnavailableThrowingResolver(),
      });

      final result = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/x',
            dataPath: 'key',
            source: FormDataSourceType.tool,
          ),
        ],
      );

      expect(result.unfilledFields.length, 1);
      expect(
        result.unfilledFields[0].errorCode,
        'binding.source_unavailable',
      );
    });

    test('uses default when resolver throws generic Exception', () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.tool: const GenericExceptionResolver(),
      });

      final result = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/x',
            dataPath: 'key',
            source: FormDataSourceType.tool,
            defaultValue: 'generic-fallback',
          ),
        ],
      );

      expect(result.boundFields.length, 1);
      expect(result.boundFields[0].value, 'generic-fallback');
    });

    test('unfilled when generic Exception and no default', () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.tool: const GenericExceptionResolver(),
      });

      final result = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/x',
            dataPath: 'key',
            source: FormDataSourceType.tool,
          ),
        ],
      );

      expect(result.unfilledFields.length, 1);
      expect(
        result.unfilledFields[0].errorCode,
        'binding.mapping_failed',
      );
    });

    test('uses default when BindingMappingException thrown', () async {
      // MockResolver throws BindingMappingException for missing keys
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.userInput: MockResolver(
          FormDataSourceType.userInput,
          {},
        ),
      });

      final result = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/x',
            dataPath: 'missing',
            source: FormDataSourceType.userInput,
            defaultValue: 'mapping-fallback',
          ),
        ],
      );

      // This is already tested but we need the BindingMappingException
      // catch path with default - the existing test covers it.
      // Adding explicit check that it uses the default value.
      expect(result.boundFields.length, 1);
      expect(result.boundFields[0].value, 'mapping-fallback');
    });

    test('unfilled with mapping error when no default', () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.userInput: MockResolver(
          FormDataSourceType.userInput,
          {},
        ),
      });

      final result = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/x',
            dataPath: 'missing',
            source: FormDataSourceType.userInput,
          ),
        ],
      );

      expect(result.unfilledFields.length, 1);
      expect(
        result.unfilledFields[0].errorCode,
        'binding.mapping_failed',
      );
    });
  });

  group('BindingEngine - transforms', () {
    test('applies toString transform', () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.userInput: MockResolver(
          FormDataSourceType.userInput,
          {'num': 42},
        ),
      });

      final result = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/x',
            dataPath: 'num',
            source: FormDataSourceType.userInput,
            transform: 'toString',
          ),
        ],
      );

      expect(result.boundFields.length, 1);
      expect(result.boundFields[0].value, '42');
    });

    test('applies toUpperCase transform', () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.userInput: MockResolver(
          FormDataSourceType.userInput,
          {'text': 'hello'},
        ),
      });

      final result = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/x',
            dataPath: 'text',
            source: FormDataSourceType.userInput,
            transform: 'toUpperCase',
          ),
        ],
      );

      expect(result.boundFields.length, 1);
      expect(result.boundFields[0].value, 'HELLO');
    });

    test('applies toLowerCase transform', () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.userInput: MockResolver(
          FormDataSourceType.userInput,
          {'text': 'WORLD'},
        ),
      });

      final result = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/x',
            dataPath: 'text',
            source: FormDataSourceType.userInput,
            transform: 'toLowerCase',
          ),
        ],
      );

      expect(result.boundFields.length, 1);
      expect(result.boundFields[0].value, 'world');
    });

    test('transform exception returns raw value', () async {
      final badObj = _BadToString();
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.userInput: MockResolver(
          FormDataSourceType.userInput,
          {'obj': badObj},
        ),
      });

      final result = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/x',
            dataPath: 'obj',
            source: FormDataSourceType.userInput,
            transform: 'toString',
          ),
        ],
      );

      // Transform exception caught; raw value returned
      expect(result.boundFields.length, 1);
      expect(result.boundFields[0].value, same(badObj));
    });

    test('unknown transform returns raw value', () async {
      final engine = BindingEngine(resolvers: {
        FormDataSourceType.userInput: MockResolver(
          FormDataSourceType.userInput,
          {'text': 'unchanged'},
        ),
      });

      final result = await engine.resolve(
        document: _makeDoc(),
        bindings: [
          FormDataBinding(
            bindingId: 'b1',
            fieldPath: '/data/x',
            dataPath: 'text',
            source: FormDataSourceType.userInput,
            transform: 'unknownTransform',
          ),
        ],
      );

      expect(result.boundFields.length, 1);
      expect(result.boundFields[0].value, 'unchanged');
    });
  });

  group('BindingExceptions', () {
    test('BindingSourceUnavailableException toString', () {
      const e = BindingSourceUnavailableException('testSource');
      expect(
        e.toString(),
        'BindingSourceUnavailableException: testSource unavailable',
      );
    });

    test('BindingMappingException toString', () {
      const e = BindingMappingException('test message');
      expect(e.toString(), 'BindingMappingException: test message');
    });
  });
}
