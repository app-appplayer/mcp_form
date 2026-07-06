/// Emit MathML from the math AST, for the HTML renderer. Browsers lay out
/// MathML natively, so HTML needs no geometry engine — just a faithful tree.
library;

import 'math_parser.dart';

/// Render [node] as a `<math>` element. [display] selects block vs inline.
String mathToMathml(MathNode node, {required bool display}) {
  final body = _emit(node);
  final mode = display ? 'block' : 'inline';
  return '<math xmlns="http://www.w3.org/1998/Math/MathML" display="$mode">'
      '$body</math>';
}

String _emit(MathNode node) {
  switch (node) {
    case MathAtom():
      final t = _escape(node.text);
      if (node.isOperator) return '<mo>$t</mo>';
      if (RegExp(r'^[0-9.]+$').hasMatch(node.text)) return '<mn>$t</mn>';
      if (node.italic) return '<mi>$t</mi>';
      return '<mi mathvariant="normal">$t</mi>';
    case MathRow():
      if (node.children.isEmpty) return '<mrow></mrow>';
      return '<mrow>${node.children.map(_emit).join()}</mrow>';
    case MathFrac():
      return '<mfrac>${_emit(node.numerator)}${_emit(node.denominator)}</mfrac>';
    case MathSqrt():
      return '<msqrt>${_emit(node.radicand)}</msqrt>';
    case MathScripts():
      final base = _emit(node.base);
      if (node.sup != null && node.sub != null) {
        return '<msubsup>$base${_emit(node.sub!)}${_emit(node.sup!)}</msubsup>';
      }
      if (node.sup != null) return '<msup>$base${_emit(node.sup!)}</msup>';
      return '<msub>$base${_emit(node.sub!)}</msub>';
  }
}

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
