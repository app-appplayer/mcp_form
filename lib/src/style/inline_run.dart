import 'dart:convert';

import 'html_inline.dart';
import 'markdown_inline.dart';
import 'text_run_style.dart';

/// A contiguous span of text sharing one [TextRunStyle]. The style is
/// *relative* — it carries only the marks the span sets; the renderer merges it
/// over the block's resolved base style. Text may contain `\n`, which line
/// breakers treat as a forced break.
class InlineRun {
  const InlineRun(this.text, [this.style = TextRunStyle.empty]);

  final String text;
  final TextRunStyle style;

  InlineRun withStyle(TextRunStyle style) => InlineRun(text, style);
}

/// A styled inline fragment — an ordered list of [InlineRun]s. Produced by
/// parsing a block's `content` according to its `format`.
class FormRichText {
  const FormRichText(this.runs);

  /// A single unstyled run.
  factory FormRichText.plain(String text) => FormRichText([InlineRun(text)]);

  /// Parse [content] into runs per [format]:
  /// `plain` (one run), `markdown`, `html`, or `runs` (a JSON array of
  /// `{text, ...marks}` objects). Unknown formats fall back to plain.
  factory FormRichText.parse(String content, {String format = 'plain'}) {
    switch (format) {
      case 'markdown':
      case 'md':
        return parseMarkdownInline(content);
      case 'html':
        return parseHtmlInline(content);
      case 'runs':
        return _fromRunsJson(content);
      default:
        return FormRichText.plain(content);
    }
  }

  final List<InlineRun> runs;

  /// The concatenated text with all marks dropped.
  String get plainText => runs.map((r) => r.text).join();

  /// True when there is no visible text.
  bool get isEmpty => runs.every((r) => r.text.isEmpty);

  static FormRichText _fromRunsJson(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is List) {
        final runs = <InlineRun>[];
        for (final e in decoded) {
          if (e is Map) {
            final m = e.cast<String, dynamic>();
            runs.add(InlineRun(
              m['text'] as String? ?? '',
              TextRunStyle.fromMap(m),
            ));
          } else if (e is String) {
            runs.add(InlineRun(e));
          }
        }
        return FormRichText(runs);
      }
    } catch (_) {
      // Fall through to plain on malformed JSON.
    }
    return FormRichText.plain(content);
  }
}
