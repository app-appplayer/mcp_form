import 'font_metrics.dart';
import 'inline_run.dart';
import 'text_run_style.dart';

/// Fraction of the font size used for super- / subscript runs.
const double kScriptScale = 0.75;

/// A measured span within a line — text plus its fully-resolved (absolute)
/// style and on-page width in points.
class LineSegment {
  LineSegment(this.text, this.style, this.size, this.width);

  String text;
  final TextRunStyle style;

  /// Resolved font size in points (already scaled for script/shrink).
  final double size;

  double width;
}

/// One laid-out line of segments.
class TextLine {
  TextLine(this.segments, this.width, this.maxSize);

  final List<LineSegment> segments;
  final double width;

  /// Largest font size on the line — drives line height.
  final double maxSize;

  bool get isEmpty => segments.isEmpty;

  String get plainText => segments.map((s) => s.text).join();
}

/// Break [rich] into measured lines that fit [maxWidthPt], merging each run's
/// relative marks over the resolved [base] style. `\n` forces a break. When
/// [wrap] is false only forced breaks split lines. [scale] multiplies every
/// font size (used by copy-fit shrinking).
List<TextLine> wrapRichText(
  FormRichText rich,
  double maxWidthPt,
  TextRunStyle base, {
  double scale = 1.0,
  bool wrap = true,
  FontMetrics metrics = defaultMetrics,
}) {
  final baseSize = (base.fontSize ?? 12) * scale;
  final lines = <TextLine>[];

  var segs = <LineSegment>[];
  var lineWidth = 0.0;
  var maxSize = 0.0;

  void flush() {
    lines.add(TextLine(segs, lineWidth, maxSize == 0 ? baseSize : maxSize));
    segs = <LineSegment>[];
    lineWidth = 0.0;
    maxSize = 0.0;
  }

  void addToken(String text, TextRunStyle style, double size, double width) {
    if (segs.isNotEmpty &&
        identical(segs.last.style, style) &&
        segs.last.size == size) {
      segs.last.text += text;
      segs.last.width += width;
    } else {
      segs.add(LineSegment(text, style, size, width));
    }
    lineWidth += width;
    if (size > maxSize) maxSize = size;
  }

  for (final run in rich.runs) {
    final style = base.merge(run.style);
    final scriptScale =
        style.baseline == null || style.baseline == RunBaseline.normal
            ? 1.0
            : kScriptScale;
    final size = (style.fontSize ?? base.fontSize ?? 12) * scale * scriptScale;
    final bold = style.bold == true;
    final ls = style.letterSpacing ?? 0;

    double measure(String t) =>
        measureText(t, size, bold: bold, letterSpacing: ls, metrics: metrics);

    // Break a token that is itself wider than the line into characters, each
    // landing where it fits. Handles long Latin words / URLs and unspaced runs.
    void charBreak(String text) {
      for (final cp in text.runes) {
        final ch = String.fromCharCode(cp);
        final cw = measure(ch);
        if (wrap && segs.isNotEmpty && lineWidth + cw > maxWidthPt) flush();
        addToken(ch, style, size, cw);
      }
    }

    final pieces = run.text.split('\n');
    for (var p = 0; p < pieces.length; p++) {
      if (p > 0) flush(); // newline → forced break

      final piece = pieces[p];
      if (piece.isEmpty) continue;

      for (final token in _tokenize(piece)) {
        if (token.isEmpty) continue;
        final width = measure(token);

        // A token wider than the line itself must break by character — CJK
        // runs (no spaces) and over-long words would otherwise overflow. Only
        // a leading separator space is trimmed; interior spaces are preserved.
        if (wrap && width > maxWidthPt) {
          final t = token.trimLeft();
          if (segs.isNotEmpty) flush();
          if (t.isNotEmpty) charBreak(t);
          continue;
        }

        if (wrap && segs.isNotEmpty && lineWidth + width > maxWidthPt) {
          flush();
          final t = token.trimLeft(); // drop the separating space at the wrap
          if (t.isNotEmpty) addToken(t, style, size, measure(t));
        } else {
          addToken(token, style, size, width);
        }
      }
    }
  }
  flush();

  return lines;
}

/// True for scripts that may break between any two characters (no spaces):
/// CJK ideographs, kana, CJK symbols/punctuation and fullwidth forms. Hangul
/// is excluded — Korean uses inter-word spaces, so it wraps like Latin.
bool _cjkBreakable(int cp) =>
    (cp >= 0x3000 && cp <= 0x303F) ||
    (cp >= 0x3040 && cp <= 0x30FF) ||
    (cp >= 0x3400 && cp <= 0x4DBF) ||
    (cp >= 0x4E00 && cp <= 0x9FFF) ||
    (cp >= 0xF900 && cp <= 0xFAFF) ||
    (cp >= 0xFF00 && cp <= 0xFFEF) ||
    (cp >= 0x20000 && cp <= 0x2FA1F);

/// Split a line piece into break units: space-led words, each further split so
/// every CJK character is its own breakable unit. The leading space stays
/// attached to a word's first unit so it is dropped cleanly at a wrap.
List<String> _tokenize(String piece) {
  final words = piece.split(' ');
  final tokens = <String>[];
  for (var w = 0; w < words.length; w++) {
    final lead = w > 0 ? ' ' : '';
    final word = words[w];
    if (word.isEmpty) {
      if (lead.isNotEmpty) tokens.add(lead);
      continue;
    }
    final segs = <String>[];
    final cur = StringBuffer();
    for (final cp in word.runes) {
      if (_cjkBreakable(cp)) {
        if (cur.isNotEmpty) {
          segs.add(cur.toString());
          cur.clear();
        }
        segs.add(String.fromCharCode(cp));
      } else {
        cur.writeCharCode(cp);
      }
    }
    if (cur.isNotEmpty) segs.add(cur.toString());
    for (var s = 0; s < segs.length; s++) {
      tokens.add(s == 0 ? lead + segs[s] : segs[s]);
    }
  }
  return tokens;
}

/// Total height in points for [lines] at the given line-height multiplier.
double linesHeight(List<TextLine> lines, double lineHeightMul) {
  var h = 0.0;
  for (final l in lines) {
    h += l.maxSize * lineHeightMul;
  }
  return h;
}
