import 'inline_run.dart';
import 'text_run_style.dart';

/// Parse a bounded subset of inline HTML into styled runs.
///
/// Supported tags: `<b>`/`<strong>`, `<i>`/`<em>`, `<u>`, `<s>`/`<del>`/
/// `<strike>`, `<mark>`, `<sup>`, `<sub>`, `<a href>`, `<br>`, and `<span
/// style="...">` (color, background, font-weight, font-style, text-decoration,
/// font-size, font-family). Unknown tags are skipped but their text is kept.
/// The subset is deliberately closed so output is predictable across web, app
/// and print.
FormRichText parseHtmlInline(String src) {
  final runs = <InlineRun>[];
  final stack = <TextRunStyle>[]; // active style deltas, outermost first

  TextRunStyle current() {
    var s = TextRunStyle.empty;
    for (final d in stack) {
      s = s.merge(d);
    }
    return s;
  }

  void emitText(String raw) {
    if (raw.isEmpty) return;
    runs.add(InlineRun(_decodeEntities(raw), current()));
  }

  var i = 0;
  final n = src.length;
  while (i < n) {
    final lt = src.indexOf('<', i);
    if (lt < 0) {
      emitText(src.substring(i));
      break;
    }
    if (lt > i) emitText(src.substring(i, lt));

    final gt = src.indexOf('>', lt + 1);
    if (gt < 0) {
      // Unterminated tag — treat the rest as text.
      emitText(src.substring(lt));
      break;
    }

    final tagRaw = src.substring(lt + 1, gt).trim();
    i = gt + 1;
    if (tagRaw.isEmpty) continue;

    final isClose = tagRaw.startsWith('/');
    final body = isClose ? tagRaw.substring(1).trim() : tagRaw;
    final spaceIdx = body.indexOf(RegExp(r'\s'));
    final name =
        (spaceIdx < 0 ? body : body.substring(0, spaceIdx)).toLowerCase();

    if (name == 'br') {
      runs.add(InlineRun('\n', current()));
      continue;
    }

    if (isClose) {
      if (stack.isNotEmpty) stack.removeLast();
      continue;
    }

    final delta = _styleForTag(name, body);
    // Push a delta for every (non-void) open tag so the matching close pops the
    // right depth, even for unknown tags (empty delta).
    stack.add(delta);
  }

  if (runs.isEmpty) return FormRichText.plain(_decodeEntities(src));
  return FormRichText(runs);
}

TextRunStyle _styleForTag(String name, String body) {
  switch (name) {
    case 'b':
    case 'strong':
      return const TextRunStyle(bold: true);
    case 'i':
    case 'em':
      return const TextRunStyle(italic: true);
    case 'u':
      return const TextRunStyle(underline: true);
    case 's':
    case 'del':
    case 'strike':
      return const TextRunStyle(strike: true);
    case 'mark':
      return const TextRunStyle(highlight: '#FFF59D');
    case 'sup':
      return const TextRunStyle(baseline: RunBaseline.superscript);
    case 'sub':
      return const TextRunStyle(baseline: RunBaseline.subscript);
    case 'code':
      return const TextRunStyle(fontFamily: 'monospace');
    case 'a':
      final href = _attr(body, 'href');
      return TextRunStyle(
        link: href,
        color: '#1A0DAB',
        underline: true,
      );
    case 'span':
      return _parseInlineCss(_attr(body, 'style') ?? '');
    default:
      return TextRunStyle.empty;
  }
}

/// Extract an attribute value (`name="..."` or `name='...'`).
String? _attr(String tagBody, String attr) {
  final m = RegExp('$attr\\s*=\\s*"([^"]*)"', caseSensitive: false)
          .firstMatch(tagBody) ??
      RegExp("$attr\\s*=\\s*'([^']*)'", caseSensitive: false)
          .firstMatch(tagBody);
  return m?.group(1);
}

/// Parse a small inline-CSS subset into run marks.
TextRunStyle _parseInlineCss(String css) {
  String? fontFamily;
  double? fontSize;
  bool? bold;
  bool? italic;
  bool? underline;
  bool? strike;
  String? color;
  String? highlight;

  for (final decl in css.split(';')) {
    final idx = decl.indexOf(':');
    if (idx < 0) continue;
    final prop = decl.substring(0, idx).trim().toLowerCase();
    final value = decl.substring(idx + 1).trim();
    switch (prop) {
      case 'color':
        color = value;
      case 'background':
      case 'background-color':
        highlight = value;
      case 'font-weight':
        if (value == 'bold' || (int.tryParse(value) ?? 0) >= 600) bold = true;
      case 'font-style':
        if (value == 'italic' || value == 'oblique') italic = true;
      case 'font-family':
        fontFamily = value.split(',').first.trim().replaceAll('"', '');
      case 'font-size':
        final m = RegExp(r'([\d.]+)').firstMatch(value);
        if (m != null) fontSize = double.tryParse(m.group(1)!);
      case 'text-decoration':
        if (value.contains('underline')) underline = true;
        if (value.contains('line-through')) strike = true;
    }
  }
  return TextRunStyle(
    fontFamily: fontFamily,
    fontSize: fontSize,
    bold: bold,
    italic: italic,
    underline: underline,
    strike: strike,
    color: color,
    highlight: highlight,
  );
}

String _decodeEntities(String s) {
  if (!s.contains('&')) return s;
  return s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (m) => String.fromCharCode(int.parse(m.group(1)!)),
      );
}
