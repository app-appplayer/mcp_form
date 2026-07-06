/// Document-wide automatic numbering: hierarchical heading numbers, figure /
/// table caption numbers, a cross-reference registry and a table-of-contents
/// entry list — all produced by a single ordered walk over a document's blocks.
///
/// This is a render-time concern owned by mcp_form; the core (mcp_bundle) is
/// unchanged. Headings opt in to numbering via the existing
/// [FormHeadingBlock.numbering] flag; captions and labels ride on the block
/// `style` map (`caption`, `captionKind`, `captionPrefix`, `label`) the same way
/// `colSpan` / `listStyle` / `keepTogether` already do. Every renderer shares
/// one definition of "what is heading 1.2" and "which figure number is this".
library;

import 'package:mcp_bundle/mcp_bundle.dart';

/// One heading in document order, for table-of-contents generation.
class TocEntry {
  const TocEntry({
    required this.blockId,
    required this.level,
    required this.number,
    required this.text,
  });

  /// The heading block's id (anchor target).
  final String blockId;

  /// Heading level, 1..6.
  final int level;

  /// Resolved hierarchical number ("1.2"), or empty when the heading opts out
  /// of numbering.
  final String number;

  /// Heading text.
  final String text;
}

/// The result of numbering a document once: lookups for heading numbers, caption
/// labels and cross-references, plus the ordered TOC entry list.
///
/// Walk scope: top-level blocks of each section in order. Headings nested inside
/// repeatable / conditional blocks are intentionally not numbered (a repeated
/// template heading would otherwise collide), matching how authors structure
/// document outlines at the top level.
class DocumentNumbering {
  DocumentNumbering._(
    this._headingNumbers,
    this._captionLabels,
    this._refs,
    this.tocEntries,
  );

  /// Walk [sections] and compute all numbering.
  factory DocumentNumbering.compute(List<FormSection> sections) {
    final headingNumbers = <String, String>{};
    final captionLabels = <String, String>{};
    final refs = <String, String>{};
    final toc = <TocEntry>[];

    // Hierarchical heading counters, one per level (1..6 -> index 0..5).
    final counters = List<int>.filled(6, 0);
    // Caption counters keyed by caption kind ("figure" / "table" / custom).
    final captionCounters = <String, int>{};

    for (final section in sections) {
      for (final block in section.blocks) {
        if (block is FormHeadingBlock) {
          final level = block.level.clamp(1, 6);
          String number = '';
          if (block.numbering == true) {
            counters[level - 1]++;
            for (var d = level; d < 6; d++) {
              counters[d] = 0;
            }
            number = counters.sublist(0, level).join('.');
            headingNumbers[block.blockId] = number;
          }
          final label = block.style?['label'];
          if (label is String && label.isNotEmpty && number.isNotEmpty) {
            refs[label] = number;
          }
          toc.add(TocEntry(
            blockId: block.blockId,
            level: level,
            number: number,
            text: block.content,
          ));
          continue;
        }

        // Caption numbering for figures / tables. Opt in by carrying a `caption`
        // in the block style. Kind is taken from `captionKind`, else inferred
        // from the block type (image / chart -> figure, table -> table).
        final caption = block.style?['caption'];
        if (caption is String && caption.isNotEmpty) {
          final kind = (block.style?['captionKind'] as String?) ??
              _defaultCaptionKind(block);
          if (kind != null) {
            final prefix = (block.style?['captionPrefix'] as String?) ??
                _capitalise(kind);
            final n = (captionCounters[kind] ?? 0) + 1;
            captionCounters[kind] = n;
            final marker = '$prefix $n';
            captionLabels[block.blockId] = marker;
            final label = block.style?['label'];
            if (label is String && label.isNotEmpty) {
              refs[label] = marker;
            }
          }
        }
      }
    }

    return DocumentNumbering._(headingNumbers, captionLabels, refs, toc);
  }

  final Map<String, String> _headingNumbers;
  final Map<String, String> _captionLabels;
  final Map<String, String> _refs;

  /// All headings in document order (numbered and unnumbered).
  final List<TocEntry> tocEntries;

  /// The hierarchical number ("1.2") for a numbered heading, else null.
  String? headingNumber(String blockId) => _headingNumbers[blockId];

  /// The caption label ("Figure 1") for a captioned block, else null.
  String? captionLabel(String blockId) => _captionLabels[blockId];

  /// The number a `label` points at ("1.2" for a heading, "Figure 1" for a
  /// caption), for cross-reference resolution; null when the label is unknown.
  String? resolveRef(String label) => _refs[label];

  /// True when the document carries any numbered headings or captions — lets a
  /// renderer skip the numbering machinery entirely (no-regression fast path).
  bool get isEmpty => _headingNumbers.isEmpty && _captionLabels.isEmpty;

  static String? _defaultCaptionKind(FormBlock block) {
    if (block is FormImageBlock || block is FormChartBlock) return 'figure';
    if (block is FormTableBlock) return 'table';
    return null;
  }
}

String _capitalise(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Inline cross-reference token: `[ref:label]` resolves to the referenced
/// number ("1.2" / "Figure 1"). Unknown labels render as `[ref:label]?` so the
/// author sees the dangling reference instead of silent loss.
final RegExp _refToken = RegExp(r'\[ref:([A-Za-z0-9_\-.]+)\]');

/// Replace every `[ref:label]` token in [text] with its resolved number from
/// [numbering]. Text with no tokens is returned unchanged.
String applyCrossRefs(String text, DocumentNumbering numbering) {
  if (!text.contains('[ref:')) return text;
  return text.replaceAllMapped(_refToken, (m) {
    final label = m.group(1)!;
    final resolved = numbering.resolveRef(label);
    return resolved ?? '${m.group(0)}?';
  });
}

/// Inline footnote token: `[fn:note text]` drops a sequential reference marker
/// `[N]` at the call site and collects the note text. The notes are emitted as
/// endnotes in a "Notes" section at the end of the document (true page-bottom
/// footnotes need page-reserved layout the renderers do not model).
final RegExp _fnToken = RegExp(r'\[fn:([^\]]+)\]');

/// Collects footnote bodies in document order as text is rendered. A renderer
/// makes one collector per render, calls [consume] on each block's text in
/// order, then renders [notes] at the document end.
class FootnoteCollector {
  final List<String> _notes = [];

  /// The collected note bodies, in reference order (note N is at index N-1).
  List<String> get notes => List.unmodifiable(_notes);

  /// True when no footnotes were collected.
  bool get isEmpty => _notes.isEmpty;

  /// Replace each `[fn:...]` token in [text] with a `[N]` reference marker and
  /// collect its body. Text with no tokens is returned unchanged.
  String consume(String text) {
    if (!text.contains('[fn:')) return text;
    return text.replaceAllMapped(_fnToken, (m) {
      _notes.add(m.group(1)!.trim());
      return '[${_notes.length}]';
    });
  }
}
