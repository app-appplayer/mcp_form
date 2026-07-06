import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

List<int> _cps(String s) => s.runes.toList();

void main() {
  group('shapeArabic', () {
    test('isolated single letter uses the isolated form', () {
      // ALEF (U+0627) alone -> isolated FE8D.
      expect(_cps(shapeArabic('ا')), [0xFE8D]);
    });

    test('dual-joining + right-joining: initial then final', () {
      // BEH (D) + ALEF (R): BEH initial FE91, ALEF final FE8E.
      expect(_cps(shapeArabic('با')), [0xFE91, 0xFE8E]);
    });

    test('two dual-joining letters: initial then final', () {
      // BEH + BEH: initial FE91, final FE90.
      expect(_cps(shapeArabic('بب')), [0xFE91, 0xFE90]);
    });

    test('three dual-joining letters: initial, medial, final', () {
      // BEH BEH BEH -> FE91 (init), FE92 (med), FE90 (fin).
      expect(_cps(shapeArabic('ببب')), [0xFE91, 0xFE92, 0xFE90]);
    });

    test('lam-alef forms the mandatory ligature', () {
      // LAM (U+0644) + ALEF (U+0627) -> isolated ligature FEFB.
      expect(_cps(shapeArabic('لا')), [0xFEFB]);
      // With a connecting letter before LAM, the ligature is final FEFC.
      // BEH + LAM + ALEF -> BEH initial FE91, lam-alef final FEFC.
      expect(_cps(shapeArabic('بلا')), [0xFE91, 0xFEFC]);
    });

    test('combining marks stay attached and do not break joining', () {
      // BEH + FATHA (mark) + BEH: BEH still initial, mark passes through, final.
      final out = _cps(shapeArabic('بَب'));
      expect(out, [0xFE91, 0x064E, 0xFE90]);
    });

    test('non-Arabic text passes through unchanged', () {
      expect(shapeArabic('Hello 123'), 'Hello 123');
    });
  });

  group('hasArabic', () {
    test('detects Arabic letters only', () {
      expect(hasArabic('hello'), isFalse);
      expect(hasArabic('ب'), isTrue);
    });
  });
}
