/// Evaluator for `FormConditionalBlock.condition` expressions.
///
/// A conditional block renders its `thenBlock` when the condition is true and
/// its `elseBlock` (if any) otherwise. The condition is a small, safe expression
/// — no arbitrary code execution — over the document's bound data:
///
/// - comparisons: `path op value` with op ∈ `== != < <= > >=`
/// - boolean combinations: `a && b`, `a || b` (left-to-right, no parentheses)
/// - bare truthiness: `path` (true when non-null, non-false, non-zero,
///   non-empty)
///
/// Operands are either a literal (`"text"`, `'text'`, number, `true`/`false`/
/// `null`) or a dotted path into the data (`status`, `score`, `user.age`). A
/// leading `data.` is treated as a reference to the data root and stripped.
///
/// On any parse failure the result is `true`, so an unparseable condition falls
/// back to rendering the `thenBlock` (the historical, non-destructive default).
library;

/// Evaluate [expression] against [data]. Returns true when the condition holds
/// (or cannot be parsed — see the library doc).
bool evaluateCondition(String expression, Map<String, dynamic> data) {
  final expr = expression.trim();
  if (expr.isEmpty) return true;
  try {
    return _evalOr(expr, data);
  } catch (_) {
    return true; // non-destructive fallback: render thenBlock
  }
}

bool _evalOr(String expr, Map<String, dynamic> data) {
  for (final part in _splitTop(expr, '||')) {
    if (_evalAnd(part, data)) return true;
  }
  return false;
}

bool _evalAnd(String expr, Map<String, dynamic> data) {
  for (final part in _splitTop(expr, '&&')) {
    if (!_evalComparison(part.trim(), data)) return false;
  }
  return true;
}

const _ops = ['==', '!=', '<=', '>=', '<', '>'];

bool _evalComparison(String expr, Map<String, dynamic> data) {
  for (final op in _ops) {
    final i = expr.indexOf(op);
    if (i > 0) {
      final left = _operand(expr.substring(0, i).trim(), data);
      final right = _operand(expr.substring(i + op.length).trim(), data);
      return _compare(left, right, op);
    }
  }
  // No operator: bare truthiness.
  return _truthy(_operand(expr.trim(), data));
}

/// Resolve an operand to a value: a literal, or a dotted path into [data].
Object? _operand(String token, Map<String, dynamic> data) {
  if (token.isEmpty) return null;
  // Quoted string literal.
  if ((token.startsWith('"') && token.endsWith('"')) ||
      (token.startsWith("'") && token.endsWith("'"))) {
    return token.substring(1, token.length - 1);
  }
  if (token == 'true') return true;
  if (token == 'false') return false;
  if (token == 'null') return null;
  final n = num.tryParse(token);
  if (n != null) return n;
  return _lookup(token, data);
}

/// Walk a dotted path through nested maps / lists. A leading `data.` segment
/// refers to the data root and is stripped.
Object? _lookup(String path, Map<String, dynamic> data) {
  var segments = path.split('.').where((s) => s.isNotEmpty).toList();
  if (segments.isNotEmpty && segments.first == 'data') {
    segments = segments.sublist(1);
  }
  Object? current = data;
  for (final seg in segments) {
    if (current is Map && current.containsKey(seg)) {
      current = current[seg];
    } else if (current is List) {
      final idx = int.tryParse(seg);
      if (idx != null && idx >= 0 && idx < current.length) {
        current = current[idx];
      } else {
        return null;
      }
    } else {
      return null;
    }
  }
  return current;
}

bool _compare(Object? left, Object? right, String op) {
  if (op == '==') return _equals(left, right);
  if (op == '!=') return !_equals(left, right);
  // Ordering comparisons need numbers (or comparable strings).
  if (left is num && right is num) {
    return switch (op) {
      '<' => left < right,
      '<=' => left <= right,
      '>' => left > right,
      '>=' => left >= right,
      _ => false,
    };
  }
  if (left is String && right is String) {
    final c = left.compareTo(right);
    return switch (op) {
      '<' => c < 0,
      '<=' => c <= 0,
      '>' => c > 0,
      '>=' => c >= 0,
      _ => false,
    };
  }
  return false;
}

bool _equals(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  // Compare by string form so `"3"` and `3` match a numeric field.
  return a?.toString() == b?.toString();
}

bool _truthy(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v.isNotEmpty;
  if (v is Iterable) return v.isNotEmpty;
  if (v is Map) return v.isNotEmpty;
  return true;
}

/// Split [expr] on top-level occurrences of [sep], ignoring [sep] inside quotes.
List<String> _splitTop(String expr, String sep) {
  final parts = <String>[];
  var depth = 0; // not used for parens (unsupported) but guards future use
  String? quote;
  var start = 0;
  for (var i = 0; i + sep.length <= expr.length; i++) {
    final ch = expr[i];
    if (quote != null) {
      if (ch == quote) quote = null;
      continue;
    }
    if (ch == '"' || ch == "'") {
      quote = ch;
      continue;
    }
    if (ch == '(') depth++;
    if (ch == ')') depth--;
    if (depth == 0 && expr.substring(i, i + sep.length) == sep) {
      parts.add(expr.substring(start, i));
      start = i + sep.length;
      i += sep.length - 1;
    }
  }
  parts.add(expr.substring(start));
  return parts;
}
