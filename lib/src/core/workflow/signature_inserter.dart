import 'package:mcp_bundle/mcp_bundle.dart';

/// Type of artifact to insert into an approved document.
enum ArtifactType {
  /// Handwritten or digital signature image.
  signature,

  /// Official stamp/seal image.
  stamp,

  /// Watermark overlaid on pages (e.g., "APPROVED").
  watermark,
}

/// Position where the artifact is inserted relative to the target.
enum ArtifactPosition {
  /// Insert at the top of the target section/block.
  top,

  /// Insert at the bottom of the target section/block.
  bottom,

  /// Center within the target area.
  center,

  /// Overlay on top of existing content.
  overlay,
}

/// Configuration for inserting a signature, stamp, or watermark.
class SignatureArtifact {
  const SignatureArtifact({
    required this.type,
    required this.content,
    required this.targetPath,
    this.position = ArtifactPosition.bottom,
    this.maxWidth,
    this.opacity = 1.0,
  });

  /// Artifact type.
  final ArtifactType type;

  /// Image data for signature/stamp, or text for watermark.
  final dynamic content;

  /// Target block path (e.g., "/sections/2/blocks/5") or "all" for watermark.
  final String targetPath;

  /// Position within the target block.
  final ArtifactPosition position;

  /// Optional width constraint (pixels or percentage).
  final double? maxWidth;

  /// Opacity for watermarks (0.0 to 1.0).
  final double opacity;
}

/// Inserts signatures, stamps, and watermarks into approved documents.
///
/// Precondition: The document must be in `approved` state.
/// Postcondition: The document retains `approved` state with artifact blocks
/// inserted at specified positions. Version is NOT incremented (artifact
/// insertion is metadata enrichment, not content modification).
class SignatureInserter {
  /// Insert a signature, stamp, or watermark into the document.
  ///
  /// Throws [FormError] with code `workflow.invalid_state` if the document
  /// is not in the approved state.
  ///
  /// Returns the updated document with the artifact inserted.
  FormDocument insertArtifact({
    required FormDocument document,
    required SignatureArtifact artifact,
  }) {
    if (document.status != FormDocumentStatus.approved) {
      throw FormError(
        code: 'workflow.invalid_state',
        message: 'Signatures can only be inserted into approved documents',
        path: '/status',
        context: {'currentStatus': document.status.name},
      );
    }

    switch (artifact.type) {
      case ArtifactType.signature:
      case ArtifactType.stamp:
        return _insertImageArtifact(document, artifact);
      case ArtifactType.watermark:
        return _insertWatermark(document, artifact);
    }
  }

  FormDocument _insertImageArtifact(
    FormDocument document,
    SignatureArtifact artifact,
  ) {
    final pathParts =
        artifact.targetPath.split('/').where((p) => p.isNotEmpty).toList();

    if (pathParts.length < 2 || pathParts[0] != 'sections') {
      throw FormError(
        code: 'workflow.invalid_path',
        message: 'Invalid target path: ${artifact.targetPath}',
        path: artifact.targetPath,
      );
    }

    final sectionIdx = int.parse(pathParts[1]);
    if (sectionIdx >= document.sections.length) {
      throw FormError(
        code: 'workflow.invalid_path',
        message: 'Section index out of range: $sectionIdx',
        path: artifact.targetPath,
      );
    }

    final section = document.sections[sectionIdx];
    final blocks = List<FormBlock>.from(section.blocks);

    final imageBlock = FormImageBlock(
      blockId:
          'artifact_${artifact.type.name}_${DateTime.now().millisecondsSinceEpoch}',
      index: blocks.length,
      src: artifact.content as String,
      alt: artifact.type.name,
      maxWidth: artifact.maxWidth,
      style: {
        'artifactType': artifact.type.name,
        'opacity': artifact.opacity,
      },
    );

    if (artifact.position == ArtifactPosition.bottom) {
      blocks.add(imageBlock);
    } else if (artifact.position == ArtifactPosition.center) {
      final mid = blocks.length ~/ 2;
      blocks.insert(mid, imageBlock);
    } else {
      // top and overlay both insert at the beginning
      blocks.insert(0, imageBlock);
    }

    final updatedSection = FormSection(
      sectionId: section.sectionId,
      index: section.index,
      title: section.title,
      description: section.description,
      blocks: blocks,
    );

    final sections = List<FormSection>.from(document.sections);
    sections[sectionIdx] = updatedSection;

    return FormDocument(
      documentId: document.documentId,
      templateId: document.templateId,
      templateVersion: document.templateVersion,
      metadata: document.metadata,
      status: document.status,
      version: document.version,
      sections: sections,
      data: document.data,
      bindings: document.bindings,
      validationIssues: document.validationIssues,
    );
  }

  FormDocument _insertWatermark(
    FormDocument document,
    SignatureArtifact artifact,
  ) {
    final data = Map<String, dynamic>.from(document.data);
    data['watermark'] = {
      'text': artifact.content,
      'opacity': artifact.opacity,
      'position': artifact.position.name,
    };

    return FormDocument(
      documentId: document.documentId,
      templateId: document.templateId,
      templateVersion: document.templateVersion,
      metadata: document.metadata,
      status: document.status,
      version: document.version,
      sections: document.sections,
      data: data,
      bindings: document.bindings,
      validationIssues: document.validationIssues,
    );
  }
}
