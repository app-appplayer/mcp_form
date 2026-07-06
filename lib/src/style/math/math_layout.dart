/// A compact math box-layout engine: turns the math AST into positioned glyphs
/// and rules (fraction bars, square-root overlines) the PDF renderer draws.
/// HTML uses MathML instead (the browser lays out), so this engine is PDF-only.
///
/// Internally it lays out in baseline-relative, up-positive coordinates (the
/// natural frame for ascent / descent), then converts to top-down output the
/// renderer places against its cursor. Metrics are approximated from the font
/// size (exact glyph bounding boxes are not available); the result is readable
/// and structurally correct rather than TeX-perfect.
library;

import 'math_parser.dart';

/// A positioned glyph in top-down output coordinates: [x] from the box left,
/// [baselineTop] the drop from the box top to this glyph's baseline.
class MathRenderGlyph {
  const MathRenderGlyph(
      this.x, this.baselineTop, this.size, this.text, this.italic);
  final double x;
  final double baselineTop;
  final double size;
  final String text;
  final bool italic;
}

/// A filled rule (fraction bar / root overline) in top-down coordinates.
class MathRenderRule {
  const MathRenderRule(this.x, this.top, this.width, this.thickness);
  final double x;
  final double top;
  final double width;
  final double thickness;
}

/// A laid-out formula ready to place at a cursor: [width] × [height] with
/// glyphs and rules positioned from the top-left.
class MathRendered {
  const MathRendered(this.width, this.height, this.glyphs, this.rules);
  final double width;
  final double height;
  final List<MathRenderGlyph> glyphs;
  final List<MathRenderRule> rules;
}

/// Lay out [node] at [size] points using [measure] for glyph widths.
MathRendered layoutMath(
    MathNode node, double size, double Function(String, double) measure) {
  final box = _layout(node, size, measure);
  final glyphs = [
    for (final g in box.glyphs)
      MathRenderGlyph(g.x, box.ascent - g.y, g.size, g.text, g.italic),
  ];
  final rules = [
    for (final r in box.rules)
      MathRenderRule(r.x, box.ascent - r.yTop, r.width, r.thickness),
  ];
  return MathRendered(box.width, box.ascent + box.descent, glyphs, rules);
}

// ---- internal up-positive, baseline-relative model ----

class _Glyph {
  _Glyph(this.x, this.y, this.size, this.text, this.italic);
  double x;
  double y; // baseline position, up-positive
  final double size;
  final String text;
  final bool italic;
}

class _Rule {
  _Rule(this.x, this.yTop, this.width, this.thickness);
  double x;
  double yTop; // top edge, up-positive
  final double width;
  final double thickness;
}

class _Box {
  _Box(this.width, this.ascent, this.descent, this.glyphs, this.rules);
  double width;
  double ascent;
  double descent;
  final List<_Glyph> glyphs;
  final List<_Rule> rules;

  void shift(double dx, double dy) {
    for (final g in glyphs) {
      g.x += dx;
      g.y += dy;
    }
    for (final r in rules) {
      r.x += dx;
      r.yTop += dy;
    }
  }
}

double _glyphAscent(double size) => size * 0.70;
double _glyphDescent(double size) => size * 0.22;

_Box _layout(MathNode node, double size, double Function(String, double) m) {
  switch (node) {
    case MathAtom():
      final w = m(node.text, size);
      final pad = node.isOperator ? size * 0.18 : 0.0;
      final box = _Box(w + 2 * pad, _glyphAscent(size), _glyphDescent(size),
          [_Glyph(pad, 0, size, node.text, node.italic)], []);
      return box;

    case MathRow():
      final box = _Box(0, 0, 0, [], []);
      var x = 0.0;
      for (final child in node.children) {
        final c = _layout(child, size, m);
        c.shift(x, 0);
        box.glyphs.addAll(c.glyphs);
        box.rules.addAll(c.rules);
        x += c.width;
        if (c.ascent > box.ascent) box.ascent = c.ascent;
        if (c.descent > box.descent) box.descent = c.descent;
      }
      box.width = x;
      if (node.children.isEmpty) {
        box.ascent = _glyphAscent(size);
        box.descent = _glyphDescent(size);
      }
      return box;

    case MathScripts():
      final base = _layout(node.base, size, m);
      final scriptSize = size * 0.7;
      final box = _Box(base.width, base.ascent, base.descent,
          [...base.glyphs], [...base.rules]);
      var scriptW = 0.0;
      if (node.sup != null) {
        final sup = _layout(node.sup!, scriptSize, m);
        final raise = size * 0.5;
        sup.shift(base.width, raise);
        box.glyphs.addAll(sup.glyphs);
        box.rules.addAll(sup.rules);
        if (raise + sup.ascent > box.ascent) box.ascent = raise + sup.ascent;
        if (sup.width > scriptW) scriptW = sup.width;
      }
      if (node.sub != null) {
        final sub = _layout(node.sub!, scriptSize, m);
        final drop = size * 0.28;
        sub.shift(base.width, -drop);
        box.glyphs.addAll(sub.glyphs);
        box.rules.addAll(sub.rules);
        if (drop + sub.descent > box.descent) box.descent = drop + sub.descent;
        if (sub.width > scriptW) scriptW = sub.width;
      }
      box.width = base.width + scriptW;
      return box;

    case MathFrac():
      final num = _layout(node.numerator, size, m);
      final den = _layout(node.denominator, size, m);
      final axis = size * 0.26;
      final gap = size * 0.18;
      final thickness = (size * 0.05).clamp(0.5, 2.0);
      final width = (num.width > den.width ? num.width : den.width) + size * 0.2;
      // Numerator baseline so its bottom sits a gap above the bar.
      final numBaseline = axis + gap + num.descent;
      num.shift((width - num.width) / 2, numBaseline);
      // Denominator baseline so its top sits a gap below the bar.
      final denBaseline = axis - gap - den.ascent;
      den.shift((width - den.width) / 2, denBaseline);
      final rule = _Rule(0, axis + thickness, width, thickness);
      final box = _Box(width, 0, 0, [...num.glyphs, ...den.glyphs],
          [...num.rules, ...den.rules, rule]);
      box.ascent = numBaseline + num.ascent;
      box.descent = -denBaseline + den.descent;
      return box;

    case MathSqrt():
      final rad = _layout(node.radicand, size, m);
      final signW = m('√', size);
      final gap = size * 0.12;
      final thickness = (size * 0.05).clamp(0.5, 2.0);
      final sign = _Glyph(0, 0, size, '√', false);
      rad.shift(signW, 0);
      final overTop = rad.ascent + gap + thickness;
      final rule = _Rule(signW, overTop, rad.width, thickness);
      final box = _Box(signW + rad.width, 0, 0, [sign, ...rad.glyphs],
          [...rad.rules, rule]);
      box.ascent = overTop > _glyphAscent(size) ? overTop : _glyphAscent(size);
      box.descent =
          rad.descent > _glyphDescent(size) ? rad.descent : _glyphDescent(size);
      return box;
  }
}
