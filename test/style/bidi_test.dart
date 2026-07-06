import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

String _visual(String logical, {bool? baseRtl}) {
  final r = resolveBidi(logical, baseRtl: baseRtl);
  final order = reorderVisual(r.levels, logical.runes.length);
  final runes = logical.runes.toList();
  return order.map((i) => String.fromCharCode(runes[i])).join();
}

void main() {
  group('resolveBidi', () {
    test('pure Latin stays level 0, identity order', () {
      final r = resolveBidi('abc');
      expect(r.paraLevel, 0);
      expect(r.levels, [0, 0, 0]);
      expect(r.isRtlParagraph, isFalse);
    });

    test('pure Hebrew is an RTL paragraph and reverses', () {
      const heb = 'אבג'; // אבג
      final r = resolveBidi(heb);
      expect(r.paraLevel, 1);
      expect(r.levels, [1, 1, 1]);
      expect(_visual(heb), 'גבא'); // גבא
    });

    test('forced base direction overrides first-strong', () {
      expect(resolveBidi('abc', baseRtl: true).paraLevel, 1);
      expect(resolveBidi('א', baseRtl: false).paraLevel, 0);
    });

    test('RTL run inside LTR is reversed in place', () {
      // "A " + אב + " B"  -> visual keeps Latin, reverses the Hebrew pair.
      const s = 'A אב B';
      expect(_visual(s), 'A בא B');
    });

    test('European digits stay left-to-right within RTL', () {
      // אב12 (RTL para): digits read 1,2 left of the Hebrew, Hebrew reversed.
      const s = 'אב12';
      expect(_visual(s), '12בא');
    });
  });

  group('reorderVisual', () {
    test('reverses a contiguous higher-level run', () {
      expect(reorderVisual([0, 0, 1, 1, 0], 5), [0, 1, 3, 2, 4]);
    });

    test('nested levels reverse from the top down', () {
      // level-2 run inside a level-1 run: L2 reverses level>=2 first ([0,1,3,2])
      // then level>=1 (whole), giving [2,3,1,0].
      expect(reorderVisual([1, 1, 2, 2], 4), [2, 3, 1, 0]);
    });
  });

  group('N0 bracket pairing', () {
    test('brackets around RTL in an LTR paragraph keep LTR direction', () {
      // a(אב)c : context before "(" is Latin (embedding dir), so the brackets
      // stay LTR and only the Hebrew pair reverses inside them.
      expect(_visual('a(אב)c'), 'a(בא)c');
    });

    test('brackets around an opposite run take the established direction', () {
      // RTL paragraph, Latin inside brackets: pair resolves to RTL (embedding),
      // so the bracketed group sits as one RTL unit.
      final r = resolveBidi('א(ab)ג');
      // The two bracket positions resolve to the same (RTL) level as the text.
      expect(r.levels[1], r.levels[0]); // "(" matches the Hebrew level
      expect(r.levels[4], r.levels[0]); // ")" matches too
    });
  });

  group('mirrorGlyph (L4)', () {
    test('mirrors brackets and angle quotes', () {
      expect(mirrorGlyph(0x28), 0x29); // ( -> )
      expect(mirrorGlyph(0x29), 0x28); // ) -> (
      expect(mirrorGlyph(0x3C), 0x3E); // < -> >
      expect(mirrorGlyph(0x41), 0x41); // A unchanged
    });
  });

  group('baseIsRtl', () {
    test('first strong char sets the base direction', () {
      expect(baseIsRtl('hello א'), isFalse);
      expect(baseIsRtl('א hello'), isTrue);
      expect(baseIsRtl('123 !?'), isNull);
    });
  });

  group('explicit formatting codes (neutralised as BN)', () {
    test('an embedded LRE/PDF pair does not become strong L', () {
      // alef + LRE + "b" + PDF — the controls are removed (BN), so the Hebrew
      // still sets an RTL paragraph rather than the controls forcing LTR.
      const s = 'א\u202Ab\u202C';
      final r = resolveBidi(s);
      expect(r.paraLevel, 1); // first strong is the Hebrew letter
      // The control characters carry the paragraph level, not an L run.
      expect(r.levels[1].isOdd, isTrue); // LRE position stays at RTL base
    });

    test('controls between Hebrew letters do not split the RTL run', () {
      const s = 'א\u2066ב'; // alef + LRI + bet
      expect(_visual(s), 'ב\u2066א'); // reverses as one RTL run
    });
  });

  group('hasRtl', () {
    test('detects Arabic / Hebrew, ignores Latin', () {
      expect(hasRtl('hello'), isFalse);
      expect(hasRtl('hello א'), isTrue);
      expect(hasRtl('مرحبا'), isTrue); // مرحبا
    });
  });
}
