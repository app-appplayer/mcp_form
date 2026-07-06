import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

// Devanagari code points used in the cases below.
const ka = 'क'; // क  consonant KA
const sha = 'ष'; // ष  consonant SSA
const ra = 'र'; // र  consonant RA
const ta = 'त'; // त  consonant TA
const halant = '्'; // ्  virama
const iMatra = 'ि'; // ि  pre-base vowel sign I
const aaMatra = 'ा'; // ा  post-base vowel sign AA

void main() {
  group('hasDevanagari', () {
    test('detects Devanagari, ignores Latin / Arabic', () {
      expect(hasDevanagari('hello'), isFalse);
      expect(hasDevanagari('मुझे'), isTrue);
      expect(hasDevanagari('مرحبا'), isFalse);
    });
  });

  group('reorderDevanagari — pre-base I-matra', () {
    test('moves the I-matra before its base consonant', () {
      // कि (KA + I-matra) renders visually as [I-matra][KA].
      expect(reorderDevanagari('$ka$iMatra'), '$iMatra$ka');
    });

    test('moves the I-matra before a whole conjunct cluster', () {
      // क्षि (KA halant SSA + I-matra) -> [I-matra] KA halant SSA.
      const input = '$ka$halant$sha$iMatra';
      expect(reorderDevanagari(input), '$iMatra$ka$halant$sha');
    });

    test('leaves a post-base matra (AA) in place', () {
      // का (KA + AA-matra) must NOT reorder — AA is drawn after the consonant.
      expect(reorderDevanagari('$ka$aaMatra'), '$ka$aaMatra');
    });

    test('handles a word with surrounding text', () {
      // "x" + कि + "y" : only the cluster reorders, Latin is untouched.
      expect(reorderDevanagari('x$ka${iMatra}y'), 'x$iMatra${ka}y');
    });

    test('reorders each cluster independently', () {
      // किति -> [i]क[i]त with both i-matras moved before their consonants.
      const input = '$ka$iMatra$ta$iMatra';
      expect(reorderDevanagari(input), '$iMatra$ka$iMatra$ta');
    });
  });

  group('reorderDevanagari — invariants', () {
    test('returns non-Devanagari text unchanged', () {
      expect(reorderDevanagari('plain ascii'), 'plain ascii');
    });

    test('is idempotent (already-reordered text is stable)', () {
      // Once the I-matra is at the front it is no longer after a cluster, so a
      // second pass leaves it untouched.
      final once = reorderDevanagari('$ka$iMatra');
      expect(reorderDevanagari(once), once);
    });

    test('preserves text length (reorder only, no insertion/deletion)', () {
      const input = '$ra$halant$ka$iMatra and $ta$iMatra';
      expect(reorderDevanagari(input).runes.length, input.runes.length);
    });
  });
}
