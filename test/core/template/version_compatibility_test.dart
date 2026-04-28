import 'package:mcp_form/mcp_form.dart';
import 'package:test/test.dart';

void main() {
  group('isCompatibleWithRange', () {
    // Null range is always compatible
    test('returns true when compatRange is null', () {
      expect(isCompatibleWithRange(null, '1.0.0'), isTrue);
    });

    // Standard range: >= 1.0.0 < 2.0.0
    group('range ">= 1.0.0 < 2.0.0"', () {
      const range = '>= 1.0.0 < 2.0.0';

      test('returns true for version within range', () {
        expect(isCompatibleWithRange(range, '1.5.0'), isTrue);
      });

      test('returns false for version at exclusive upper bound', () {
        expect(isCompatibleWithRange(range, '2.0.0'), isFalse);
      });

      test('returns false for version below lower bound', () {
        expect(isCompatibleWithRange(range, '0.9.0'), isFalse);
      });

      test('returns true for version at inclusive lower bound', () {
        expect(isCompatibleWithRange(range, '1.0.0'), isTrue);
      });
    });

    // Exclusive lower, inclusive upper: > 1.0.0 <= 2.0.0
    group('range "> 1.0.0 <= 2.0.0"', () {
      const range = '> 1.0.0 <= 2.0.0';

      test('returns false for version at exclusive lower bound', () {
        expect(isCompatibleWithRange(range, '1.0.0'), isFalse);
      });

      test('returns true for version at inclusive upper bound', () {
        expect(isCompatibleWithRange(range, '2.0.0'), isTrue);
      });
    });

    // Invalid version strings
    group('invalid versions', () {
      test('returns false for non-numeric version string', () {
        expect(isCompatibleWithRange('>= 1.0.0 < 2.0.0', 'abc'), isFalse);
      });

      test('returns false for incomplete version format', () {
        expect(isCompatibleWithRange('>= 1.0.0 < 2.0.0', '1.0'), isFalse);
      });
    });
  });
}
