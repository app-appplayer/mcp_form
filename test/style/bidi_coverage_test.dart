import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

void main() {
  group('W5: European terminators adjacent to EN (lines 86-96)', () {
    test('dollar sign before a digit converts ET to EN', () {
      // '$' (ET) directly before '1' (EN).
      // W5 inner while loop: j increments past '$' (line 87), then reads EN.
      // before=false, after=true (lines 89-90).
      // Inner for loop sets t[0]=EN (lines 92-93), then i=j-1 (line 96).
      final r = resolveBidi(r'$1');
      // Paragraph has no strong chars → level 0.
      expect(r.paraLevel, 0);
      // After W5 ($→EN), W7 (EN→L since lastStrong=L), I1: both become level 0.
      expect(r.levels, everyElement(0));
    });

    test('percent sign after a digit also converts ET to EN', () {
      // '5' (EN) followed by '%' (ET).
      // W5: ET at position 1, before = (t[0] == EN) = true → converts ET to EN.
      final r = resolveBidi('5%');
      expect(r.paraLevel, 0);
      expect(r.levels, everyElement(0));
    });
  });

  group('I1/I2 level assignment for AN/EN in even paragraph (line 148)', () {
    test('EN that stays EN in LTR para gets level paraLevel+2', () {
      // Force LTR base, then use an Arabic letter (AL→R) before a digit.
      // W2: digit (EN) with lastStrong=AL → converted to AN.
      // W3: AL → R. N-rules: space becomes R.
      // I1 (paraLevel=0, even): AN → levels[i] = paraLevel + 2 = 2 (line 148).
      final r = resolveBidi('أ 1', baseRtl: false);
      expect(r.paraLevel, 0);
      final digitLevel = r.levels.last;
      expect(digitLevel, 2); // AN/EN gets paraLevel + 2
    });

    test('Arabic-Indic digit in LTR para gets level 2', () {
      // U+0660 is an Arabic-Indic digit (AN type), never converts via W-rules.
      // In LTR para, I1: AN → level 2.
      final r = resolveBidi('٠', baseRtl: false);
      expect(r.paraLevel, 0);
      expect(r.levels.first, 2);
    });
  });
}
