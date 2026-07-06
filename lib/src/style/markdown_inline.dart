import 'inline_run.dart';
import 'text_run_style.dart';

/// Parse a single line/paragraph of inline Markdown into styled runs.
///
/// Supported inline syntax (bounded on purpose — block constructs like headings
/// and lists are handled at the block layer):
///   `**bold**` / `__bold__`, `*italic*` / `_italic_`, `~~strike~~`,
///   `` `code` `` (monospace), `==highlight==`, and `[text](url)` links.
FormRichText parseMarkdownInline(String src) {
  final runs = <InlineRun>[];
  final buf = StringBuffer();
  var bold = false;
  var italic = false;
  var strike = false;
  var highlight = false;

  TextRunStyle current() => TextRunStyle(
        bold: bold ? true : null,
        italic: italic ? true : null,
        strike: strike ? true : null,
        highlight: highlight ? '#FFF59D' : null,
      );

  void flush() {
    if (buf.isNotEmpty) {
      runs.add(InlineRun(buf.toString(), current()));
      buf.clear();
    }
  }

  final s = src;
  var i = 0;
  bool match(String token) => s.startsWith(token, i);

  while (i < s.length) {
    final c = s[i];

    // Escape: backslash keeps the next char literal.
    if (c == r'\' && i + 1 < s.length) {
      buf.write(s[i + 1]);
      i += 2;
      continue;
    }

    // Inline code: `...` (monospace, no nested marks).
    if (c == '`') {
      final end = s.indexOf('`', i + 1);
      if (end > i) {
        flush();
        runs.add(InlineRun(
          s.substring(i + 1, end),
          current().copyWith(fontFamily: 'monospace'),
        ));
        i = end + 1;
        continue;
      }
    }

    // Link: [text](url)
    if (c == '[') {
      final close = s.indexOf(']', i + 1);
      if (close > i && close + 1 < s.length && s[close + 1] == '(') {
        final paren = s.indexOf(')', close + 2);
        if (paren > close) {
          flush();
          final text = s.substring(i + 1, close);
          final url = s.substring(close + 2, paren);
          runs.add(InlineRun(
            text,
            current().copyWith(link: url, color: '#1A0DAB', underline: true),
          ));
          i = paren + 1;
          continue;
        }
      }
    }

    if (match('**') || match('__')) {
      flush();
      bold = !bold;
      i += 2;
      continue;
    }
    if (match('~~')) {
      flush();
      strike = !strike;
      i += 2;
      continue;
    }
    if (match('==')) {
      flush();
      highlight = !highlight;
      i += 2;
      continue;
    }
    if (c == '*' || c == '_') {
      flush();
      italic = !italic;
      i += 1;
      continue;
    }

    buf.write(c);
    i += 1;
  }
  flush();

  if (runs.isEmpty) return FormRichText.plain(src);
  return FormRichText(runs);
}
