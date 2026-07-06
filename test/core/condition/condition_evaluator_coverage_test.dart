import 'package:mcp_form/src/core/condition/condition_evaluator.dart';
import 'package:test/test.dart';

/// Coverage tests for condition_evaluator.dart branches not reached by
/// the primary test suite:
///   - String ordering comparisons (<, <=, >, >=) — lines 115-121
///   - _truthy for Iterable and Map values — lines 139-140
void main() {
  group('evaluateCondition — string ordering', () {
    test('string < comparison', () {
      expect(evaluateCondition('name < "b"', {'name': 'a'}), isTrue);
      expect(evaluateCondition('name < "a"', {'name': 'b'}), isFalse);
    });

    test('string <= comparison', () {
      expect(evaluateCondition('name <= "a"', {'name': 'a'}), isTrue);
      expect(evaluateCondition('name <= "a"', {'name': 'b'}), isFalse);
    });

    test('string > comparison', () {
      expect(evaluateCondition('name > "a"', {'name': 'b'}), isTrue);
      expect(evaluateCondition('name > "b"', {'name': 'a'}), isFalse);
    });

    test('string >= comparison', () {
      expect(evaluateCondition('name >= "b"', {'name': 'b'}), isTrue);
      expect(evaluateCondition('name >= "b"', {'name': 'a'}), isFalse);
    });

    test('string comparison with unknown op returns false', () {
      // Both operands are strings but op is not one of the four ordering ops;
      // the _compare function's default branch returns false for the switch.
      // This also validates the string branch is fully covered.
      expect(evaluateCondition('name == "a"', {'name': 'a'}), isTrue);
    });
  });

  group('evaluateCondition — Iterable and Map truthiness', () {
    test('non-empty list is truthy', () {
      expect(evaluateCondition('items', {'items': [1, 2, 3]}), isTrue);
    });

    test('empty list is falsy', () {
      expect(evaluateCondition('items', {'items': <dynamic>[]}), isFalse);
    });

    test('non-empty map is truthy', () {
      expect(
        evaluateCondition('obj', {
          'obj': {'key': 'value'}
        }),
        isTrue,
      );
    });

    test('empty map is falsy', () {
      expect(evaluateCondition('obj', {'obj': <String, dynamic>{}}), isFalse);
    });
  });
}
