/// Arabic contextual shaping: maps logical Arabic letters to their positional
/// presentation forms (isolated / initial / medial / final) and forms the
/// mandatory lam-alef ligatures, so a font without an OpenType shaper still
/// renders connected Arabic. Combining marks are kept attached to their base.
///
/// This is the substitution stage only; visual reordering is handled by the
/// bidi algorithm. Together they let the PDF renderer draw Arabic correctly via
/// the Presentation Forms-B glyphs an embedded font provides.
library;

/// Join type: right-joining, dual-joining, or non-joining.
enum _Jt { r, d, u }

class _Letter {
  const _Letter(this.jt, this.iso, this.fin, this.init, this.med);
  final _Jt jt;
  final int iso, fin, init, med;
}

/// Base Arabic letter -> join type + Presentation Forms-B code points.
/// `init`/`med` are 0 for right-joining letters (only isolated / final exist).
const Map<int, _Letter> _letters = {
  0x0621: _Letter(_Jt.u, 0xFE80, 0, 0, 0), // HAMZA
  0x0622: _Letter(_Jt.r, 0xFE81, 0xFE82, 0, 0), // ALEF MADDA
  0x0623: _Letter(_Jt.r, 0xFE83, 0xFE84, 0, 0), // ALEF HAMZA ABOVE
  0x0624: _Letter(_Jt.r, 0xFE85, 0xFE86, 0, 0), // WAW HAMZA
  0x0625: _Letter(_Jt.r, 0xFE87, 0xFE88, 0, 0), // ALEF HAMZA BELOW
  0x0626: _Letter(_Jt.d, 0xFE89, 0xFE8A, 0xFE8B, 0xFE8C), // YEH HAMZA
  0x0627: _Letter(_Jt.r, 0xFE8D, 0xFE8E, 0, 0), // ALEF
  0x0628: _Letter(_Jt.d, 0xFE8F, 0xFE90, 0xFE91, 0xFE92), // BEH
  0x0629: _Letter(_Jt.r, 0xFE93, 0xFE94, 0, 0), // TEH MARBUTA
  0x062A: _Letter(_Jt.d, 0xFE95, 0xFE96, 0xFE97, 0xFE98), // TEH
  0x062B: _Letter(_Jt.d, 0xFE99, 0xFE9A, 0xFE9B, 0xFE9C), // THEH
  0x062C: _Letter(_Jt.d, 0xFE9D, 0xFE9E, 0xFE9F, 0xFEA0), // JEEM
  0x062D: _Letter(_Jt.d, 0xFEA1, 0xFEA2, 0xFEA3, 0xFEA4), // HAH
  0x062E: _Letter(_Jt.d, 0xFEA5, 0xFEA6, 0xFEA7, 0xFEA8), // KHAH
  0x062F: _Letter(_Jt.r, 0xFEA9, 0xFEAA, 0, 0), // DAL
  0x0630: _Letter(_Jt.r, 0xFEAB, 0xFEAC, 0, 0), // THAL
  0x0631: _Letter(_Jt.r, 0xFEAD, 0xFEAE, 0, 0), // REH
  0x0632: _Letter(_Jt.r, 0xFEAF, 0xFEB0, 0, 0), // ZAIN
  0x0633: _Letter(_Jt.d, 0xFEB1, 0xFEB2, 0xFEB3, 0xFEB4), // SEEN
  0x0634: _Letter(_Jt.d, 0xFEB5, 0xFEB6, 0xFEB7, 0xFEB8), // SHEEN
  0x0635: _Letter(_Jt.d, 0xFEB9, 0xFEBA, 0xFEBB, 0xFEBC), // SAD
  0x0636: _Letter(_Jt.d, 0xFEBD, 0xFEBE, 0xFEBF, 0xFEC0), // DAD
  0x0637: _Letter(_Jt.d, 0xFEC1, 0xFEC2, 0xFEC3, 0xFEC4), // TAH
  0x0638: _Letter(_Jt.d, 0xFEC5, 0xFEC6, 0xFEC7, 0xFEC8), // ZAH
  0x0639: _Letter(_Jt.d, 0xFEC9, 0xFECA, 0xFECB, 0xFECC), // AIN
  0x063A: _Letter(_Jt.d, 0xFECD, 0xFECE, 0xFECF, 0xFED0), // GHAIN
  0x0641: _Letter(_Jt.d, 0xFED1, 0xFED2, 0xFED3, 0xFED4), // FEH
  0x0642: _Letter(_Jt.d, 0xFED5, 0xFED6, 0xFED7, 0xFED8), // QAF
  0x0643: _Letter(_Jt.d, 0xFED9, 0xFEDA, 0xFEDB, 0xFEDC), // KAF
  0x0644: _Letter(_Jt.d, 0xFEDD, 0xFEDE, 0xFEDF, 0xFEE0), // LAM
  0x0645: _Letter(_Jt.d, 0xFEE1, 0xFEE2, 0xFEE3, 0xFEE4), // MEEM
  0x0646: _Letter(_Jt.d, 0xFEE5, 0xFEE6, 0xFEE7, 0xFEE8), // NOON
  0x0647: _Letter(_Jt.d, 0xFEE9, 0xFEEA, 0xFEEB, 0xFEEC), // HEH
  0x0648: _Letter(_Jt.r, 0xFEED, 0xFEEE, 0, 0), // WAW
  0x0649: _Letter(_Jt.r, 0xFEEF, 0xFEF0, 0, 0), // ALEF MAKSURA
  0x064A: _Letter(_Jt.d, 0xFEF1, 0xFEF2, 0xFEF3, 0xFEF4), // YEH
};

/// LAM + ALEF-variant -> ligature (isolated, final). The ligature joins to the
/// right like an alef, so it behaves as a right-joining letter.
const Map<int, List<int>> _lamAlef = {
  0x0622: [0xFEF5, 0xFEF6], // LAM + ALEF MADDA
  0x0623: [0xFEF7, 0xFEF8], // LAM + ALEF HAMZA ABOVE
  0x0625: [0xFEF9, 0xFEFA], // LAM + ALEF HAMZA BELOW
  0x0627: [0xFEFB, 0xFEFC], // LAM + ALEF
};

/// True if [cp] is a transparent combining mark (skipped for join context).
bool _isMark(int cp) =>
    (cp >= 0x064B && cp <= 0x065F) ||
    cp == 0x0670 ||
    (cp >= 0x06D6 && cp <= 0x06ED) ||
    (cp >= 0x0300 && cp <= 0x036F);

/// True if [text] contains any character this shaper handles.
bool hasArabic(String text) {
  for (final cp in text.runes) {
    if (_letters.containsKey(cp)) return true;
  }
  return false;
}

// A shaping token: a joining letter, a transparent mark, or a passthrough char.
class _Tok {
  _Tok(this.cp, this.letter, this.isMark);
  int cp;
  final _Letter? letter; // non-null for joining letters (incl. lam-alef)
  final bool isMark;
}

/// Replace Arabic letters in [text] with their contextual presentation forms.
/// Non-Arabic characters pass through unchanged.
String shapeArabic(String text) {
  if (!hasArabic(text)) return text;
  final runes = text.runes.toList();
  final toks = <_Tok>[];

  for (var i = 0; i < runes.length; i++) {
    final cp = runes[i];
    // Lam-alef: LAM immediately followed by an alef variant becomes a ligature
    // token behaving as a right-joining letter.
    if (cp == 0x0644 && i + 1 < runes.length && _lamAlef.containsKey(runes[i + 1])) {
      final lig = _lamAlef[runes[i + 1]]!;
      toks.add(_Tok(cp, _Letter(_Jt.r, lig[0], lig[1], 0, 0), false));
      i++; // consume the alef
      continue;
    }
    final letter = _letters[cp];
    if (letter != null) {
      toks.add(_Tok(cp, letter, false));
    } else {
      toks.add(_Tok(cp, null, _isMark(cp)));
    }
  }

  // Index of the nearest joining letter before / after position k (skip marks).
  int prevLetter(int k) {
    for (var i = k - 1; i >= 0; i--) {
      if (toks[i].isMark) continue;
      return toks[i].letter != null ? i : -1;
    }
    return -1;
  }

  int nextLetter(int k) {
    for (var i = k + 1; i < toks.length; i++) {
      if (toks[i].isMark) continue;
      return toks[i].letter != null ? i : -1;
    }
    return -1;
  }

  final out = StringBuffer();
  for (var i = 0; i < toks.length; i++) {
    final t = toks[i];
    final L = t.letter;
    if (L == null) {
      out.writeCharCode(t.cp);
      continue;
    }
    final pi = prevLetter(i);
    final ni = nextLetter(i);
    // Current joins to a previous letter only if that letter is dual-joining
    // (has a left connection); current must itself be R or D to receive it.
    final joinsPrev = pi >= 0 && toks[pi].letter!.jt == _Jt.d;
    // Current joins to the next letter only if current is dual-joining and the
    // next letter can connect on its right (any joining letter does).
    final joinsNext = L.jt == _Jt.d && ni >= 0;

    final int form;
    if (L.jt == _Jt.u) {
      form = L.iso;
    } else if (L.jt == _Jt.r) {
      form = joinsPrev ? L.fin : L.iso;
    } else {
      if (joinsPrev && joinsNext) {
        form = L.med;
      } else if (joinsNext) {
        form = L.init;
      } else if (joinsPrev) {
        form = L.fin;
      } else {
        form = L.iso;
      }
    }
    out.writeCharCode(form == 0 ? t.cp : form);
  }
  return out.toString();
}
