/// Unicode Bidirectional Algorithm (UAX #9), implicit-level implementation.
///
/// Resolves embedding levels for a single paragraph (P2/P3, W1–W7, N0 bracket
/// pairing, N1/N2, I1/I2) and reorders a line from logical to visual order (L2),
/// with mirroring (L4) exposed via [mirrorGlyph]. Covers mixed Latin / Arabic /
/// Hebrew / digits and parenthesised mixed content — the cases that matter for
/// rendering.
///
/// Out of scope: explicit embedding semantics (the X-rules / isolating run
/// sequences for LRE/RLE/LRO/RLO/PDF and LRI/RLI/FSI/PDI). Those controls are
/// neutralised as BN — removed from the computation rather than mistaken for
/// strong letters — since realistic form / document text does not embed them.
library;

/// Bidi character types used by the implicit algorithm.
enum _Bc { l, r, al, en, es, et, an, cs, nsm, bn, b, s, ws, on }

/// Resolved paragraph: per-character embedding [levels] and the [paraLevel].
class BidiResult {
  BidiResult(this.levels, this.paraLevel);
  final List<int> levels;
  final int paraLevel;

  bool get isRtlParagraph => paraLevel.isOdd;
}

/// Resolve embedding levels for [text]. When [baseRtl] is null the paragraph
/// level follows the first strong character (UAX #9 P2/P3); otherwise it is
/// forced.
BidiResult resolveBidi(String text, {bool? baseRtl}) {
  final cps = text.runes.toList();
  final n = cps.length;
  final types = List<_Bc>.generate(n, (i) => _classify(cps[i]));

  // P2 / P3: paragraph embedding level.
  int paraLevel;
  if (baseRtl != null) {
    paraLevel = baseRtl ? 1 : 0;
  } else {
    paraLevel = 0;
    for (final t in types) {
      if (t == _Bc.l) break;
      if (t == _Bc.r || t == _Bc.al) {
        paraLevel = 1;
        break;
      }
    }
  }

  final levels = List<int>.filled(n, paraLevel);
  if (n == 0) return BidiResult(levels, paraLevel);

  // Work on a copy of the resolved types.
  final t = List<_Bc>.of(types);
  final sos = paraLevel.isOdd ? _Bc.r : _Bc.l;
  final eos = sos;

  // W1: NSM takes the type of the previous char (sos at the start). BN counts
  // as its neighbour's type for this purpose is out of scope here.
  for (var i = 0; i < n; i++) {
    if (t[i] == _Bc.nsm) t[i] = i == 0 ? sos : t[i - 1];
  }
  // W2: EN -> AN when the last strong type was AL.
  var lastStrong = sos;
  for (var i = 0; i < n; i++) {
    final c = t[i];
    if (c == _Bc.l || c == _Bc.r || c == _Bc.al) lastStrong = c;
    if (c == _Bc.en && lastStrong == _Bc.al) t[i] = _Bc.an;
  }
  // W3: AL -> R.
  for (var i = 0; i < n; i++) {
    if (t[i] == _Bc.al) t[i] = _Bc.r;
  }
  // W4: a single ES between two EN -> EN; a single CS between two EN or two AN
  // -> that number type.
  for (var i = 1; i < n - 1; i++) {
    final p = t[i - 1], c = t[i], q = t[i + 1];
    if (c == _Bc.es && p == _Bc.en && q == _Bc.en) t[i] = _Bc.en;
    if (c == _Bc.cs && p == _Bc.en && q == _Bc.en) t[i] = _Bc.en;
    if (c == _Bc.cs && p == _Bc.an && q == _Bc.an) t[i] = _Bc.an;
  }
  // W5: a sequence of ET adjacent to EN -> EN.
  for (var i = 0; i < n; i++) {
    if (t[i] == _Bc.et) {
      var j = i;
      while (j < n && t[j] == _Bc.et) {
        j++;
      }
      final before = i > 0 && t[i - 1] == _Bc.en;
      final after = j < n && t[j] == _Bc.en;
      if (before || after) {
        for (var k = i; k < j; k++) {
          t[k] = _Bc.en;
        }
      }
      i = j - 1;
    }
  }
  // W6: remaining ES / ET / CS -> ON.
  for (var i = 0; i < n; i++) {
    if (t[i] == _Bc.es || t[i] == _Bc.et || t[i] == _Bc.cs) t[i] = _Bc.on;
  }
  // W7: EN -> L when the last strong type was L.
  lastStrong = sos;
  for (var i = 0; i < n; i++) {
    final c = t[i];
    if (c == _Bc.l || c == _Bc.r) lastStrong = c;
    if (c == _Bc.en && lastStrong == _Bc.l) t[i] = _Bc.l;
  }

  // N0 / BD16: resolve bracket pairs to a consistent direction before the
  // generic neutral rules, so parentheses/brackets around mixed content take
  // the right side (e.g. Arabic price "(100 USD)").
  _resolveBrackets(cps, t, paraLevel, sos);

  // N1 / N2: resolve neutrals (ON / B / S / WS / BN). EN and AN count as R.
  bool isNeutral(_Bc c) =>
      c == _Bc.on ||
      c == _Bc.b ||
      c == _Bc.s ||
      c == _Bc.ws ||
      c == _Bc.bn;
  _Bc dirOf(_Bc c) => (c == _Bc.en || c == _Bc.an) ? _Bc.r : c;
  for (var i = 0; i < n; i++) {
    if (!isNeutral(t[i])) continue;
    var j = i;
    while (j < n && isNeutral(t[j])) {
      j++;
    }
    final before = i > 0 ? dirOf(t[i - 1]) : sos;
    final after = j < n ? dirOf(t[j]) : eos;
    final resolved = (before == after && (before == _Bc.l || before == _Bc.r))
        ? before
        : (paraLevel.isOdd ? _Bc.r : _Bc.l); // N2: embedding direction
    for (var k = i; k < j; k++) {
      t[k] = resolved;
    }
    i = j - 1;
  }

  // I1 / I2: implicit levels.
  for (var i = 0; i < n; i++) {
    final c = t[i];
    if (paraLevel.isEven) {
      if (c == _Bc.r) {
        levels[i] = paraLevel + 1;
      } else if (c == _Bc.an || c == _Bc.en) {
        levels[i] = paraLevel + 2;
      } else {
        levels[i] = paraLevel;
      }
    } else {
      if (c == _Bc.l || c == _Bc.en || c == _Bc.an) {
        levels[i] = paraLevel + 1;
      } else {
        levels[i] = paraLevel;
      }
    }
  }

  return BidiResult(levels, paraLevel);
}

/// Canonical opening bracket -> closing bracket (Bidi_Paired_Bracket, common
/// subset). Canonical-equivalent CJK angle brackets map to the ASCII-ish forms.
const Map<int, int> _openToClose = {
  0x0028: 0x0029, // ( )
  0x005B: 0x005D, // [ ]
  0x007B: 0x007D, // { }
  0x0F3A: 0x0F3B,
  0x0F3C: 0x0F3D,
  0x2018: 0x2019,
  0x201C: 0x201D,
  0x2308: 0x2309,
  0x230A: 0x230B,
  0x2329: 0x232A,
  0x3008: 0x3009,
  0x300A: 0x300B,
  0x300C: 0x300D,
  0x300E: 0x300F,
  0x3010: 0x3011,
  0x3014: 0x3015,
  0x3016: 0x3017,
  0xFF08: 0xFF09,
  0xFF3B: 0xFF3D,
  0xFF5B: 0xFF5D,
};

/// Mirrored character pairs (Bidi_Mirrored subset) for L4: a character drawn at
/// an odd (right-to-left) level is replaced by its mirror so brackets, angle
/// quotes and comparison signs point the correct way.
const Map<int, int> _mirror = {
  0x0028: 0x0029, 0x0029: 0x0028, // ( )
  0x005B: 0x005D, 0x005D: 0x005B, // [ ]
  0x007B: 0x007D, 0x007D: 0x007B, // { }
  0x003C: 0x003E, 0x003E: 0x003C, // < >
  0x00AB: 0x00BB, 0x00BB: 0x00AB, // « »
  0x2039: 0x203A, 0x203A: 0x2039, // ‹ ›
  0x2308: 0x2309, 0x2309: 0x2308,
  0x230A: 0x230B, 0x230B: 0x230A,
  0x2329: 0x232A, 0x232A: 0x2329,
  0x3008: 0x3009, 0x3009: 0x3008,
  0x300A: 0x300B, 0x300B: 0x300A,
  0xFF08: 0xFF09, 0xFF09: 0xFF08,
};

/// L4: the glyph to draw for [cp] when it sits at a right-to-left level. Returns
/// [cp] unchanged when it has no mirror.
int mirrorGlyph(int cp) => _mirror[cp] ?? cp;

/// N0 (BD16): pair brackets and resolve each pair's direction in place on [t].
void _resolveBrackets(List<int> cps, List<_Bc> t, int paraLevel, _Bc sos) {
  final n = cps.length;
  final e = paraLevel.isOdd ? _Bc.r : _Bc.l; // embedding direction
  final o = e == _Bc.l ? _Bc.r : _Bc.l;

  // BD16: match opening/closing brackets with a bounded stack.
  final pairs = <List<int>>[];
  final stack = <List<int>>[]; // [expectedClose, openIndex]
  for (var i = 0; i < n; i++) {
    if (t[i] != _Bc.on) continue;
    final c = cps[i];
    final close = _openToClose[c];
    if (close != null) {
      if (stack.length >= 63) break;
      stack.add([close, i]);
    } else {
      for (var s = stack.length - 1; s >= 0; s--) {
        if (stack[s][0] == c) {
          pairs.add([stack[s][1], i]);
          stack.removeRange(s, stack.length);
          break;
        }
      }
    }
  }
  pairs.sort((a, b) => a[0] - b[0]);

  _Bc strong(_Bc c) =>
      (c == _Bc.en || c == _Bc.an) ? _Bc.r : (c == _Bc.l || c == _Bc.r) ? c : _Bc.on;

  for (final pair in pairs) {
    final open = pair[0], close = pair[1];
    var foundE = false, foundO = false;
    for (var k = open + 1; k < close; k++) {
      final d = strong(t[k]);
      if (d == e) foundE = true;
      if (d == o) foundO = true;
    }
    _Bc? dir;
    if (foundE) {
      dir = e;
    } else if (foundO) {
      // Established direction before the opening bracket.
      var ctx = sos;
      for (var k = open - 1; k >= 0; k--) {
        final d = strong(t[k]);
        if (d != _Bc.on) {
          ctx = d;
          break;
        }
      }
      dir = ctx == o ? o : e;
    }
    if (dir != null) {
      t[open] = dir;
      t[close] = dir;
    }
  }
}

/// L2: return the visual order of [length] logical positions given their
/// [levels] — the indices to read in left-to-right display order. Reverses each
/// contiguous run from the highest level down to the lowest odd level.
List<int> reorderVisual(List<int> levels, int length) {
  final order = List<int>.generate(length, (i) => i);
  if (length == 0) return order;
  var highest = 0;
  var lowestOdd = 1 << 30;
  for (final l in levels) {
    if (l > highest) highest = l;
    if (l.isOdd && l < lowestOdd) lowestOdd = l;
  }
  for (var level = highest; level >= lowestOdd; level--) {
    var i = 0;
    while (i < length) {
      if (levels[order[i]] >= level) {
        var j = i;
        while (j < length && levels[order[j]] >= level) {
          j++;
        }
        // Reverse order[i..j).
        var lo = i, hi = j - 1;
        while (lo < hi) {
          final tmp = order[lo];
          order[lo] = order[hi];
          order[hi] = tmp;
          lo++;
          hi--;
        }
        i = j;
      } else {
        i++;
      }
    }
  }
  return order;
}

/// The base paragraph direction of [text] by the first strong character
/// (UAX #9 P2/P3): true for RTL, false for LTR, null when there is no strong
/// character. Used to set one base level for a whole paragraph rather than
/// guessing per wrapped line.
bool? baseIsRtl(String text) {
  for (final cp in text.runes) {
    final c = _classify(cp);
    if (c == _Bc.l) return false;
    if (c == _Bc.r || c == _Bc.al) return true;
  }
  return null;
}

/// True if [text] contains any right-to-left strong character (Hebrew, Arabic,
/// and related blocks) — a cheap gate so left-to-right text skips bidi entirely.
bool hasRtl(String text) {
  for (final cp in text.runes) {
    final c = _classify(cp);
    if (c == _Bc.r || c == _Bc.al || c == _Bc.an) return true;
  }
  return false;
}

_Bc _classify(int cp) {
  // Arabic-Indic and extended Arabic-Indic digits.
  if (cp >= 0x0660 && cp <= 0x0669) return _Bc.an;
  if (cp >= 0x06F0 && cp <= 0x06F9) return _Bc.an;
  // European digits.
  if (cp >= 0x0030 && cp <= 0x0039) return _Bc.en;
  // European number separators / terminators.
  if (cp == 0x002B || cp == 0x002D) return _Bc.es; // + -
  if (cp == 0x0024 || cp == 0x0023 || cp == 0x0025 || cp == 0x00A3 ||
      cp == 0x00A5 || cp == 0x00A2 || cp == 0x20AC) {
    return _Bc.et; // currency / # / %
  }
  if (cp == 0x002C || cp == 0x002E || cp == 0x003A || cp == 0x002F) {
    return _Bc.cs; // , . : /
  }
  // Hebrew + Hebrew presentation forms.
  if (cp >= 0x0590 && cp <= 0x05FF) return _Bc.r;
  if (cp >= 0xFB1D && cp <= 0xFB4F) return _Bc.r;
  // Arabic letters (and Arabic Presentation Forms) -> AL.
  if (cp >= 0x0600 && cp <= 0x06FF) {
    // Arabic combining marks -> NSM.
    if ((cp >= 0x064B && cp <= 0x065F) ||
        cp == 0x0670 ||
        (cp >= 0x06D6 && cp <= 0x06DC) ||
        (cp >= 0x06DF && cp <= 0x06E4) ||
        (cp >= 0x06E7 && cp <= 0x06E8) ||
        (cp >= 0x06EA && cp <= 0x06ED)) {
      return _Bc.nsm;
    }
    return _Bc.al;
  }
  if (cp >= 0x0750 && cp <= 0x077F) return _Bc.al; // Arabic Supplement
  if (cp >= 0xFB50 && cp <= 0xFDFF) return _Bc.al; // Arabic Presentation Forms-A
  if (cp >= 0xFE70 && cp <= 0xFEFF) return _Bc.al; // Arabic Presentation Forms-B
  // Explicit bidi formatting / isolate codes (LRE RLE PDF LRO RLO; LRI RLI FSI
  // PDI). We do not implement explicit embedding semantics (the X-rules and
  // isolating run sequences); instead these invisible controls are neutralised
  // as BN so they are removed from the implicit computation rather than being
  // mistaken for strong letters. The implicit algorithm with first-strong base
  // detection, bracket pairing (N0) and Arabic shaping covers realistic
  // form / document text, which does not embed these controls.
  if ((cp >= 0x202A && cp <= 0x202E) || (cp >= 0x2066 && cp <= 0x2069)) {
    return _Bc.bn;
  }
  // Combining marks (general) -> NSM.
  if (cp >= 0x0300 && cp <= 0x036F) return _Bc.nsm;
  // Whitespace / separators.
  if (cp == 0x0020) return _Bc.ws;
  if (cp == 0x0009) return _Bc.s;
  if (cp == 0x000A || cp == 0x000D || cp == 0x2029) return _Bc.b;
  // Latin and most other letters are strong L; everything else neutral (ON).
  if ((cp >= 0x0041 && cp <= 0x005A) ||
      (cp >= 0x0061 && cp <= 0x007A) ||
      (cp >= 0x00C0 && cp <= 0x024F) ||
      (cp >= 0x0400 && cp <= 0x052F) || // Cyrillic
      (cp >= 0x0370 && cp <= 0x03FF) || // Greek
      cp >= 0x1100) {
    return _Bc.l;
  }
  return _Bc.on;
}
