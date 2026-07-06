/// Devanagari pre-base matra reordering.
///
/// In Devanagari the vowel sign I (मात्रा "i", U+093F ि) is *stored* after its
/// base consonant but *rendered* before the whole consonant cluster. A shaper
/// that draws glyphs in logical order would place it on the wrong side. This
/// module performs the deterministic, font-independent reorder that fixes the
/// common case: it moves a trailing pre-base I-matra to the front of its cluster
/// (including halant-joined conjuncts).
///
/// Scope: this is a pure Unicode-level reorder. Conjunct ligature formation and
/// the reph (र् → superscript) require the font's GSUB tables and are therefore
/// out of scope for a table-free renderer; they degrade gracefully to the
/// component glyphs in visual cluster order.
library;

/// Devanagari halant / virama — joins consonants into conjuncts.
const int _halant = 0x094D;

/// Pre-base vowel sign I — the one matra that reorders to before its cluster.
const int _iMatra = 0x093F;

/// True if [cp] is a Devanagari base consonant (main block + nukta variants).
bool _isConsonant(int cp) =>
    (cp >= 0x0915 && cp <= 0x0939) || (cp >= 0x0958 && cp <= 0x095F);

/// True if [text] contains any Devanagari code point (cheap gate).
bool hasDevanagari(String text) {
  for (final cp in text.runes) {
    if (cp >= 0x0900 && cp <= 0x097F) return true;
  }
  return false;
}

/// Reorder Devanagari pre-base I-matras to before their consonant cluster.
///
/// Non-Devanagari text is returned unchanged. The transform is idempotent for
/// text that has no pre-base matra to move.
String reorderDevanagari(String text) {
  if (!hasDevanagari(text)) return text;
  final cps = text.runes.toList();
  final n = cps.length;
  final out = <int>[];
  var i = 0;
  while (i < n) {
    if (_isConsonant(cps[i])) {
      // Collect the consonant cluster: (consonant + halant)* then a base.
      final start = i;
      var j = i;
      while (j + 1 < n && _isConsonant(cps[j]) && cps[j + 1] == _halant) {
        j += 2;
      }
      // The base consonant of the cluster, if present.
      if (j < n && _isConsonant(cps[j])) j++;
      // A pre-base I-matra immediately after the cluster moves to its front.
      if (j < n && cps[j] == _iMatra) {
        out.add(_iMatra);
        out.addAll(cps.getRange(start, j));
        i = j + 1;
      } else {
        out.addAll(cps.getRange(start, j));
        i = j;
      }
    } else {
      out.add(cps[i]);
      i++;
    }
  }
  return String.fromCharCodes(out);
}
