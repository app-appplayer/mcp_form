import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

void main() {
  group('parseHtmlInline: unterminated tag (line 42)', () {
    test('tag without a closing > is treated as literal text', () {
      // src.indexOf('>') returns -1 → line 40 condition is true → line 42 fires.
      final rt = parseHtmlInline('hello <b unterminated');
      expect(rt.plainText, contains('hello'));
      expect(rt.plainText, contains('<b unterminated'));
    });

    test('tag opening at the very start with no closing bracket', () {
      final rt = parseHtmlInline('<b');
      expect(rt.plainText, '<b');
    });
  });

  group('parseCssStyle: font-style property (line 146)', () {
    test('font-style:italic sets italic flag', () {
      final rt = parseHtmlInline('<span style="font-style:italic">text</span>');
      expect(rt.runs.isNotEmpty, isTrue);
      expect(rt.runs.first.style.italic, isTrue);
    });

    test('font-style:oblique also sets italic flag (line 146 alternate branch)', () {
      // The condition is value == "italic" || value == "oblique"; both hit line 146.
      final rt = parseHtmlInline('<span style="font-style: oblique">text</span>');
      expect(rt.runs.first.style.italic, isTrue);
    });
  });

  group('parseCssStyle: font-size property (lines 150-151)', () {
    test('font-size:14px parses the numeric value and sets fontSize', () {
      // switch case "font-size" → RegExp match → line 150-151.
      final rt = parseHtmlInline('<span style="font-size:14px">text</span>');
      final s = rt.runs.first.style;
      expect(s.fontSize, closeTo(14.0, 0.001));
    });

    test('font-size:10.5pt is parsed correctly', () {
      final rt = parseHtmlInline('<span style="font-size: 10.5pt">text</span>');
      expect(rt.runs.first.style.fontSize, closeTo(10.5, 0.001));
    });
  });
}
