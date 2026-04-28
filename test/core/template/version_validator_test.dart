import 'package:mcp_form/mcp_form.dart';
import 'package:test/test.dart';

void main() {
  group('isValidVersion', () {
    // TC-006: Valid semver format accepted
    test('accepts valid semver formats', () {
      expect(isValidVersion('1.0.0'), isTrue);
      expect(isValidVersion('2.10.3'), isTrue);
      expect(isValidVersion('10.20.30'), isTrue);
    });

    // TC-008: Semver with zero components
    test('accepts 0.0.0', () {
      expect(isValidVersion('0.0.0'), isTrue);
    });

    // TC-007: Invalid semver formats rejected
    test('rejects invalid semver formats', () {
      expect(isValidVersion('1.0'), isFalse);
      expect(isValidVersion('v1.0.0'), isFalse);
      expect(isValidVersion('abc'), isFalse);
      expect(isValidVersion(''), isFalse);
      expect(isValidVersion('1.0.0.0'), isFalse);
      expect(isValidVersion('1.0.0-beta'), isFalse);
    });
  });
}
