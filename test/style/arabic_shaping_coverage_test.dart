import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

void main() {
  group('shapeArabic: isolated non-joining (HAMZA, line 154)', () {
    test('HAMZA (U+0621) is non-joining and gets isolated form', () {
      // HAMZA has jt == _Jt.u → hits line 154: form = L.iso.
      final shaped = shapeArabic('ء');
      // FE80 is the isolated form for HAMZA.
      expect(shaped.runes.first, 0xFE80);
    });
  });

  group('shapeArabic: isolated dual-joining letter (line 165)', () {
    test('BEH (U+0628) between digits has no adjacent letters → isolated (line 165)', () {
      // Dual-joining letter (jt == _Jt.d) with pi=-1 and ni=-1.
      // joinsPrev=false, joinsNext=false → hits line 165: form = L.iso.
      final shaped = shapeArabic('1ب2');
      // FE8F is the isolated form for BEH.
      expect(shaped.runes.contains(0xFE8F), isTrue);
    });

    test('isolated dual-joining at start of string also yields isolated form', () {
      // A single Arabic dual-joining letter with no neighbours.
      final shaped = shapeArabic('ب');
      expect(shaped.runes.first, 0xFE8F);
    });
  });
}
