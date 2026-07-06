import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

void main() {
  group('TextLine getters (lines 32, 34)', () {
    test('isEmpty returns true for an empty segment list', () {
      // Construct a TextLine with no segments and call isEmpty (line 32).
      final empty = TextLine([], 0, 12);
      expect(empty.isEmpty, isTrue); // line 32
      expect(empty.plainText, ''); // line 34
    });

    test('isEmpty returns false and plainText joins segments', () {
      final rt = FormRichText.plain('hello world');
      final lines = wrapRichText(rt, 1000, TextRunStyle.empty);
      expect(lines.first.isEmpty, isFalse); // line 32
      expect(lines.first.plainText, 'hello world'); // line 34
    });
  });

  group('_tokenize CJK flush (lines 166, 167)', () {
    test('mixed Latin-CJK word flushes the Latin buffer on first CJK char', () {
      // "abc中def": 'a','b','c' accumulate in cur, then '中' triggers cur.isNotEmpty
      // path, which calls segs.add(cur.toString()) [line 166] and cur.clear() [line 167].
      final rt = FormRichText.plain('abc中def');
      final lines = wrapRichText(rt, 1000, TextRunStyle.empty);
      // The tokenizer should keep all characters regardless of the split.
      expect(lines.first.plainText, 'abc中def');
    });

    test('multiple mixed segments in a wide box keep all characters', () {
      // Exercises the CJK path with a longer mixed string.
      final rt = FormRichText.plain('x一y二z');
      final lines = wrapRichText(rt, 1000, TextRunStyle.empty);
      expect(lines.first.plainText, 'x一y二z');
    });
  });
}
