import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

double _measure(String t, double s) => t.length * s * 0.5;

void main() {
  group('math_layout: empty MathRow (lines 125-126)', () {
    test('empty superscript group uses glyph ascent/descent defaults', () {
      // parseMath(r'x^{}') creates MathScripts(sup=MathRow([])).
      // _layout on that empty MathRow hits node.children.isEmpty → lines 125-126.
      final laid = layoutMath(parseMath(r'x^{}'), 12, _measure);
      expect(laid.height, greaterThan(0));
    });
  });

  group('math_layout: subscript branch (lines 146-152)', () {
    test('subscript glyph sits below the base baseline', () {
      // x_2 → node.sub != null → the else-if block (lines 146-152) executes.
      final laid = layoutMath(parseMath('x_2'), 12, _measure);
      final base = laid.glyphs.firstWhere((g) => g.text == 'x');
      final sub = laid.glyphs.firstWhere((g) => g.text == '2');
      // Larger baselineTop = lower on the page (top-down coords).
      expect(sub.baselineTop, greaterThan(base.baselineTop));
    });

    test('combined super + sub layout covers both branches', () {
      // x_i^2 triggers sup branch AND sub branch.
      final laid = layoutMath(parseMath('x_i^2'), 12, _measure);
      expect(laid.glyphs.length, 3); // x, i, 2
    });
  });

  group('math_parser: unknown command and non-letter escape (lines 178, 186-187)', () {
    test(r'backslash before non-letter reads the char and falls back (lines 186-187)', () {
      // '\+': '+' is not [A-Za-z] → _readCommandName returns '+' (line 186-187).
      // '+' is not in mathSymbols → returns MathAtom('+', italic:true) (line 178).
      final node = parseMath(r'\+');
      expect(mathToMathml(node, display: false), isA<String>());
    });

    test(r'unknown multi-letter command falls back to italic atom (line 178)', () {
      // '\xyz' is not in mathSymbols → MathAtom('xyz', italic:true).
      final node = parseMath(r'\xyz');
      expect(mathToMathml(node, display: false), contains('xyz'));
    });
  });

  group('math_text: emit paths (lines 46, 61, 73)', () {
    test('sqrt renders as unicode root (line 46)', () {
      // MathSqrt node → _emit hits line 46: return "√(...)".
      final r = substituteInlineMath(r'$\sqrt{x}$');
      expect(r, contains('√'));
      expect(r, contains('('));
    });

    test('compound numerator in frac wrapped in parens (line 61)', () {
      // \frac{ab}{c}: numerator is MathRow([a, b]) → simple=false → line 61 returns "($text)".
      final r = substituteInlineMath(r'$\frac{ab}{c}$');
      expect(r, contains('(ab)'));
      expect(r, contains('/c'));
    });

    test('superscript char not in table uses fallback marker (line 73)', () {
      // 'q' is not in _superscripts map → g==null → line 73: return "^q".
      final r = substituteInlineMath(r'$x^q$');
      expect(r, contains('^'));
      expect(r, contains('q'));
    });

    test('subscript char not in table uses underscore marker (line 73)', () {
      // 'q' is not in _subscripts map either.
      final r = substituteInlineMath(r'$x_q$');
      expect(r, contains('_'));
      expect(r, contains('q'));
    });
  });
}
