/// List markers for `listStyle` / `numberFormat` block styling.
///
/// A text block whose `style.listStyle` is set renders its source lines (split
/// on `\n`) as list items. This module computes the marker string for each item
/// in a format-independent way so every renderer (PDF / HTML / DOCX / Markdown)
/// shares one definition of what an "item 3 of a lower-roman ordered list" looks
/// like. Markdown emits native `-` / `1.` syntax instead and does not use this.
library;

/// True when [listStyle] requests list rendering (`bullet` or `ordered`).
bool isListStyle(String? listStyle) =>
    listStyle == 'bullet' || listStyle == 'ordered';

/// The marker for the [index]-th item (0-based) of a list.
///
/// - `bullet` → a glyph chosen by [numberFormat] (`disc`•, `circle`◦, `square`▪;
///   default `disc`).
/// - `ordered` → a counter rendered per [numberFormat] (`decimal` 1, `lower-alpha`
///   a, `upper-alpha` A, `lower-roman` i, `upper-roman` I; default `decimal`)
///   followed by a period.
///
/// Returns an empty string when [listStyle] is not a list style.
String listMarker(int index, String? listStyle, String? numberFormat) {
  if (listStyle == 'bullet') {
    return switch (numberFormat) {
      'circle' => '◦', // ◦
      'square' => '▪', // ▪
      _ => '•', // •
    };
  }
  if (listStyle == 'ordered') {
    final n = index + 1;
    final body = switch (numberFormat) {
      'lower-alpha' => _alpha(n, lower: true),
      'upper-alpha' => _alpha(n, lower: false),
      'lower-roman' => _roman(n).toLowerCase(),
      'upper-roman' => _roman(n),
      _ => '$n',
    };
    return '$body.';
  }
  return '';
}

/// Spreadsheet-style alphabetic counter: 1→a, 26→z, 27→aa.
String _alpha(int n, {required bool lower}) {
  final base = lower ? 0x61 : 0x41;
  final buf = <int>[];
  var v = n;
  while (v > 0) {
    v -= 1;
    buf.insert(0, base + (v % 26));
    v ~/= 26;
  }
  return String.fromCharCodes(buf);
}

/// Roman numeral for 1..3999; falls back to the decimal for out-of-range values.
String _roman(int n) {
  if (n <= 0 || n >= 4000) return '$n';
  const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
  const symbols = ['M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I'];
  final buf = StringBuffer();
  var v = n;
  for (var i = 0; i < values.length; i++) {
    while (v >= values[i]) {
      buf.write(symbols[i]);
      v -= values[i];
    }
  }
  return buf.toString();
}
