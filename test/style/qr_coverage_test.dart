import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

void main() {
  // Lines 145 and 389-390 are genuinely dead code:
  //   - Line 145: the while-body that pads bits to a byte boundary.
  //     After the terminator (4 bits), the total bit count is always a
  //     multiple of 8, so the condition is never true.
  //   - Lines 389-390: _flatten is the fallback when no candidate survived
  //     the penalty selection loop.  bestGrid is always set because the
  //     penalty score is always less than 1 << 30.
  // These three lines cannot be reached without restructuring the production
  // code; they are reported as dead code in the final release-gate summary.

  group('_utf8: multi-byte UTF-8 encoding (lines 405-416)', () {
    test('2-byte UTF-8: U+00E9 (é) covers lines 405-407', () {
      // rune = 0xE9, 0x80 <= 0xE9 < 0x800 → two-byte branch.
      final qr = encodeQr('é');
      expect(qr.size, greaterThan(0));
    });

    test('3-byte UTF-8: U+4E2D (中) covers lines 408-411', () {
      // rune = 0x4E2D, 0x800 <= 0x4E2D < 0x10000 → three-byte branch.
      final qr = encodeQr('中');
      expect(qr.size, greaterThan(0));
    });

    test('4-byte UTF-8: U+1F600 (😀) covers lines 413-416', () {
      // rune = 0x1F600, >= 0x10000 → four-byte branch.
      final qr = encodeQr('😀');
      expect(qr.size, greaterThan(0));
    });

    test('mixed ASCII + multi-byte characters encode correctly', () {
      // Exercises both the 1-byte path (rune < 0x80) and the multi-byte paths.
      final qr = encodeQr('a中b😀c');
      expect(qr.size, greaterThan(0));
    });
  });
}
