import 'package:mcp_bundle/mcp_bundle.dart';

/// Lightweight document projection for list/search queries.
///
/// Does not include full section/block data.
/// This is a mcp_form projection pattern, not a mcp_bundle type.
class DocumentSummary {
  const DocumentSummary({
    required this.documentId,
    required this.templateId,
    required this.templateVersion,
    this.title,
    required this.author,
    required this.status,
    required this.version,
    required this.sectionCount,
    required this.blockCount,
    required this.createdAt,
    this.modifiedAt,
  });

  /// Create a summary from a full FormDocument.
  factory DocumentSummary.fromDocument(FormDocument document) {
    final totalBlocks = document.sections.fold<int>(
      0,
      (sum, section) => sum + section.blocks.length,
    );

    return DocumentSummary(
      documentId: document.documentId,
      templateId: document.templateId,
      templateVersion: document.templateVersion,
      title: _extractTitle(document),
      author: document.metadata.author,
      status: document.status,
      version: document.version,
      sectionCount: document.sections.length,
      blockCount: totalBlocks,
      createdAt: document.metadata.createdAt,
      modifiedAt: document.metadata.modifiedAt,
    );
  }

  /// Document identifier.
  final String documentId;

  /// Source template identifier.
  final String templateId;

  /// Template version used.
  final String templateVersion;

  /// Document title (derived from first heading or metadata).
  final String? title;

  /// Author identifier.
  final String author;

  /// Current lifecycle status.
  final FormDocumentStatus status;

  /// Document version number.
  final int version;

  /// Total number of sections.
  final int sectionCount;

  /// Total number of blocks across all sections.
  final int blockCount;

  /// Creation timestamp.
  final DateTime createdAt;

  /// Last modification timestamp.
  final DateTime? modifiedAt;

  /// Extract document title from the first FormHeadingBlock (level 1)
  /// if present, otherwise return null.
  static String? _extractTitle(FormDocument document) {
    for (final section in document.sections) {
      for (final block in section.blocks) {
        if (block is FormHeadingBlock && block.level == 1) {
          return block.content;
        }
      }
    }
    return null;
  }
}
