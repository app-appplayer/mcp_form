import 'truetype_font.dart';

/// Source of glyph advance widths for text measurement. Implementations cover
/// the built-in Helvetica family (Latin only) and an embedded TrueType font
/// (any script the font covers).
abstract class FontMetrics {
  /// Advance width of a code point as a fraction of the em (so a renderer
  /// multiplies by the point size). Bold / italic hints are advisory.
  double advanceEm(int codePoint, {bool bold = false, bool italic = false});
}

/// Helvetica (regular / oblique) advance widths for codes 32..126.
const List<int> _helvetica = <int>[
  278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
  556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
  1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
  667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
  333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
  556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
];

/// Helvetica-Bold (bold / bold-oblique) advance widths for codes 32..126.
const List<int> _helveticaBold = <int>[
  278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278,
  556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611,
  975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778,
  667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556,
  333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611,
  611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584,
];

const int _latinFallback = 556;

/// Built-in Helvetica metrics (WinAnsi / Latin only). CJK and other wide
/// scripts fall back to a full em so measurement over-estimates.
class HelveticaMetrics implements FontMetrics {
  const HelveticaMetrics();

  @override
  double advanceEm(int code, {bool bold = false, bool italic = false}) {
    if (code >= 32 && code <= 126) {
      return (bold ? _helveticaBold : _helvetica)[code - 32] / 1000.0;
    }
    if (code >= 0x1100) return 1.0;
    return _latinFallback / 1000.0;
  }
}

/// Metrics backed by an embedded [TrueTypeFont]. Bold / italic share the face
/// (faux-styled at render time), so the hints are ignored.
class TrueTypeMetrics implements FontMetrics {
  const TrueTypeMetrics(this.font);

  final TrueTypeFont font;

  @override
  double advanceEm(int code, {bool bold = false, bool italic = false}) {
    final gid = font.gidFor(code);
    if (gid == null || gid == 0) return _latinFallback / 1000.0;
    return font.advanceWidth1000(gid) / 1000.0;
  }
}

/// Metrics over a primary font plus ordered fallbacks: each code point is
/// measured with the first font that has a glyph for it, matching how the PDF
/// renderer routes glyphs. Falls back to a nominal Latin width when no font
/// covers the code point.
class FallbackMetrics implements FontMetrics {
  const FallbackMetrics(this.fonts);

  /// Primary first, then fallbacks in order.
  final List<TrueTypeFont> fonts;

  @override
  double advanceEm(int code, {bool bold = false, bool italic = false}) {
    for (final f in fonts) {
      final gid = f.gidFor(code);
      if (gid != null && gid != 0) return f.advanceWidth1000(gid) / 1000.0;
    }
    return _latinFallback / 1000.0;
  }
}

/// Default metrics — the built-in Helvetica family.
const FontMetrics defaultMetrics = HelveticaMetrics();

/// Width in points of [text] at [fontSize] pt using [metrics], including
/// optional [letterSpacing] (pt) between characters.
double measureText(
  String text,
  double fontSize, {
  bool bold = false,
  double letterSpacing = 0,
  FontMetrics metrics = defaultMetrics,
}) {
  if (text.isEmpty) return 0;
  var em = 0.0;
  var count = 0;
  for (final code in text.runes) {
    em += metrics.advanceEm(code, bold: bold);
    count++;
  }
  final spacing = letterSpacing * (count - 1).clamp(0, 1 << 30);
  return em * fontSize + spacing;
}
