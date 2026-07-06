/// Render a math AST to a compact Unicode text approximation, for inline `$…$`
/// math in renderers that do not typeset (PDF / DOCX text runs). Superscripts
/// and subscripts use Unicode where a glyph exists, falling back to `^`/`_`;
/// fractions become `a/b`, roots `√(x)`. HTML uses real MathML instead.
library;

import 'math_parser.dart';

const Map<String, String> _superscripts = {
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶',
  '7': '⁷', '8': '⁸', '9': '⁹', '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽',
  ')': '⁾', 'n': 'ⁿ', 'i': 'ⁱ',
};

const Map<String, String> _subscripts = {
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', '5': '₅', '6': '₆',
  '7': '₇', '8': '₈', '9': '₉', '+': '₊', '-': '₋', '=': '₌', '(': '₍',
  ')': '₎', 'a': 'ₐ', 'e': 'ₑ', 'i': 'ᵢ', 'j': 'ⱼ', 'n': 'ₙ', 'x': 'ₓ',
};

/// A Unicode-text approximation of [node].
String mathToInlineText(MathNode node) => _emit(node);

/// Inline math token: `$expr$` (no nested `$`). A literal dollar is written
/// `\$`.
final RegExp inlineMathToken = RegExp(r'(?<!\\)\$([^$]+)\$');

/// Replace every `$expr$` in [text] with a Unicode-text rendering of the
/// expression; also unescapes `\$` to `$`. Text with no math is unchanged.
String substituteInlineMath(String text) {
  if (!text.contains(r'$')) return text;
  final out = text.replaceAllMapped(
      inlineMathToken, (m) => mathToInlineText(parseMath(m.group(1)!)));
  return out.replaceAll(r'\$', r'$');
}

String _emit(MathNode node) {
  switch (node) {
    case MathAtom():
      return node.text;
    case MathRow():
      return node.children.map(_emit).join();
    case MathFrac():
      return '${_wrap(node.numerator)}/${_wrap(node.denominator)}';
    case MathSqrt():
      return '√(${_emit(node.radicand)})';
    case MathScripts():
      final buf = StringBuffer(_emit(node.base));
      if (node.sup != null) buf.write(_script(node.sup!, _superscripts));
      if (node.sub != null) buf.write(_script(node.sub!, _subscripts));
      return buf.toString();
  }
}

/// Wrap a compound numerator/denominator in parentheses; leave a single atom
/// bare (`a/b`, not `(a)/(b)`).
String _wrap(MathNode node) {
  final text = _emit(node);
  final simple = node is MathAtom ||
      (node is MathRow && node.children.length <= 1);
  return simple ? text : '($text)';
}

/// Map a script's text to Unicode super/subscripts; fall back to `^{…}`/`_{…}`
/// when any character has no glyph.
String _script(MathNode node, Map<String, String> table) {
  final text = _emit(node);
  final mapped = StringBuffer();
  for (final ch in text.split('')) {
    final g = table[ch];
    if (g == null) {
      final marker = identical(table, _superscripts) ? '^' : '_';
      return text.length == 1 ? '$marker$text' : '$marker{$text}';
    }
    mapped.write(g);
  }
  return mapped.toString();
}
