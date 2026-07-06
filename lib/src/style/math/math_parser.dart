/// A small LaTeX-subset math parser producing an AST that the layout engine
/// (PDF) and the MathML emitter (HTML) consume. Self-contained, no dependencies.
///
/// Supported: variables / numbers / operators, `^` superscript and `_`
/// subscript (single token or `{...}` group), `\frac{a}{b}`, `\sqrt{a}`,
/// `{...}` grouping, and a table of named symbols (Greek letters, `\sum`,
/// `\int`, `\infty`, relations and binary operators). Unknown commands fall back
/// to their literal name so nothing is silently dropped. This covers the bulk of
/// inline academic notation; full LaTeX (matrices, `\left\right`, accents,
/// stretchy delimiters) is out of scope.
library;

/// Base class for math AST nodes.
sealed class MathNode {
  const MathNode();
}

/// A leaf token: a variable, number, operator or named symbol. [italic] marks
/// single-letter identifiers (rendered slanted, like LaTeX math variables).
class MathAtom extends MathNode {
  const MathAtom(this.text, {this.italic = false, this.isOperator = false});
  final String text;
  final bool italic;
  final bool isOperator;
}

/// A horizontal sequence of nodes.
class MathRow extends MathNode {
  const MathRow(this.children);
  final List<MathNode> children;
}

/// A base with an optional superscript and/or subscript.
class MathScripts extends MathNode {
  const MathScripts(this.base, {this.sup, this.sub});
  final MathNode base;
  final MathNode? sup;
  final MathNode? sub;
}

/// A fraction (numerator over denominator).
class MathFrac extends MathNode {
  const MathFrac(this.numerator, this.denominator);
  final MathNode numerator;
  final MathNode denominator;
}

/// A square root.
class MathSqrt extends MathNode {
  const MathSqrt(this.radicand);
  final MathNode radicand;
}

/// Named symbols → their Unicode form. Operators/relations are spaced by the
/// layout; large operators (`\sum`, `\int`) take limits as scripts.
const Map<String, String> mathSymbols = {
  // Greek lowercase
  'alpha': 'α', 'beta': 'β', 'gamma': 'γ', 'delta': 'δ', 'epsilon': 'ε',
  'zeta': 'ζ', 'eta': 'η', 'theta': 'θ', 'iota': 'ι', 'kappa': 'κ',
  'lambda': 'λ', 'mu': 'μ', 'nu': 'ν', 'xi': 'ξ', 'pi': 'π', 'rho': 'ρ',
  'sigma': 'σ', 'tau': 'τ', 'phi': 'φ', 'chi': 'χ', 'psi': 'ψ', 'omega': 'ω',
  // Greek uppercase
  'Gamma': 'Γ', 'Delta': 'Δ', 'Theta': 'Θ', 'Lambda': 'Λ', 'Xi': 'Ξ',
  'Pi': 'Π', 'Sigma': 'Σ', 'Phi': 'Φ', 'Psi': 'Ψ', 'Omega': 'Ω',
  // Operators / relations
  'times': '×', 'div': '÷', 'pm': '±', 'mp': '∓', 'cdot': '·', 'ast': '∗',
  'leq': '≤', 'geq': '≥', 'neq': '≠', 'approx': '≈', 'equiv': '≡',
  'sim': '∼', 'propto': '∝', 'll': '≪', 'gg': '≫',
  'rightarrow': '→', 'leftarrow': '←', 'Rightarrow': '⇒', 'Leftarrow': '⇐',
  'leftrightarrow': '↔', 'mapsto': '↦',
  'infty': '∞', 'partial': '∂', 'nabla': '∇', 'forall': '∀', 'exists': '∃',
  'in': '∈', 'notin': '∉', 'subset': '⊂', 'subseteq': '⊆', 'cup': '∪',
  'cap': '∩', 'emptyset': '∅', 'angle': '∠', 'perp': '⊥', 'parallel': '∥',
  'cdots': '⋯', 'ldots': '…', 'prime': '′', 'circ': '∘', 'bullet': '•',
  // Large operators
  'sum': '∑', 'prod': '∏', 'int': '∫', 'oint': '∮', 'bigcup': '⋃',
  'bigcap': '⋂', 'sqrt_sign': '√',
};

/// Symbols that act as operators/relations for spacing purposes.
const Set<String> _operatorSymbols = {
  '×', '÷', '±', '∓', '·', '∗', '≤', '≥', '≠', '≈', '≡', '∼', '∝', '≪', '≫',
  '→', '←', '⇒', '⇐', '↔', '↦', '∈', '∉', '⊂', '⊆', '∪', '∩', '∘',
  '+', '-', '=', '<', '>', '∑', '∏', '∫', '∮',
};

/// Parse a LaTeX-subset [src] into a [MathRow].
MathNode parseMath(String src) => _MathParser(src).parseRow();

class _MathParser {
  _MathParser(this.src);
  final String src;
  int _pos = 0;

  bool get _atEnd => _pos >= src.length;
  String get _peek => src[_pos];

  /// Parse a sequence until end of input or an unmatched `}`.
  MathRow parseRow() {
    final nodes = <MathNode>[];
    while (!_atEnd && _peek != '}') {
      final atom = _parseScripts();
      if (atom != null) nodes.add(atom);
    }
    return MathRow(nodes);
  }

  /// Parse one base optionally followed by `^`/`_` scripts.
  MathNode? _parseScripts() {
    var base = _parseAtom();
    if (base == null) return null;
    MathNode? sup;
    MathNode? sub;
    while (!_atEnd && (_peek == '^' || _peek == '_')) {
      final isSup = _peek == '^';
      _pos++;
      final arg = _parseGroupOrToken();
      if (isSup) {
        sup = arg;
      } else {
        sub = arg;
      }
    }
    if (sup != null || sub != null) {
      base = MathScripts(base, sup: sup, sub: sub);
    }
    return base;
  }

  /// Parse a single atom: a group, a command, or one character.
  MathNode? _parseAtom() {
    _skipSpaces();
    if (_atEnd || _peek == '}') return null;
    final ch = _peek;
    if (ch == '{') return _parseGroup();
    if (ch == '\\') return _parseCommand();
    if (ch == '^' || ch == '_') return null; // handled by caller
    _pos++;
    final isLetter = RegExp(r'[A-Za-z]').hasMatch(ch);
    return MathAtom(
      ch,
      italic: isLetter,
      isOperator: _operatorSymbols.contains(ch),
    );
  }

  MathNode _parseGroup() {
    _pos++; // consume '{'
    final row = parseRow();
    if (!_atEnd && _peek == '}') _pos++; // consume '}'
    return row;
  }

  /// Parse a `{...}` group, or a single following token (for script arguments).
  MathNode _parseGroupOrToken() {
    _skipSpaces();
    if (!_atEnd && _peek == '{') return _parseGroup();
    final atom = _parseAtom();
    return atom ?? const MathRow([]);
  }

  MathNode _parseCommand() {
    _pos++; // consume '\'
    final name = _readCommandName();
    switch (name) {
      case 'frac':
        final num = _parseGroupOrToken();
        final den = _parseGroupOrToken();
        return MathFrac(num, den);
      case 'sqrt':
        return MathSqrt(_parseGroupOrToken());
      default:
        final sym = mathSymbols[name];
        if (sym != null) {
          return MathAtom(sym, isOperator: _operatorSymbols.contains(sym));
        }
        // Unknown command: keep the literal name so nothing is lost.
        return MathAtom(name, italic: true);
    }
  }

  String _readCommandName() {
    if (_atEnd) return '';
    // A command is a run of letters, or a single non-letter symbol.
    if (!RegExp(r'[A-Za-z]').hasMatch(_peek)) {
      final c = _peek;
      _pos++;
      return c;
    }
    final start = _pos;
    while (!_atEnd && RegExp(r'[A-Za-z]').hasMatch(_peek)) {
      _pos++;
    }
    return src.substring(start, _pos);
  }

  void _skipSpaces() {
    while (!_atEnd && _peek == ' ') {
      _pos++;
    }
  }
}
