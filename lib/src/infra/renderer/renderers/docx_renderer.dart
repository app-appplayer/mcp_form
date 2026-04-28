import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';

import '../../../core/template/layout_extensions.dart';
import '../render_context.dart';
import '../renderer_registry.dart';

/// DOCX output renderer using Flat OPC (Office Open XML) format.
///
/// Produces a single XML document in WordprocessingML Flat OPC format,
/// which is natively supported by Microsoft Word and LibreOffice.
/// This avoids any dependency on external ZIP/archive packages while
/// generating valid, openable DOCX-compatible output.
class DocxRenderer implements DocumentRenderer {
  const DocxRenderer();

  static const _wNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  static const _rNs = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  /// Twips per millimeter (1 inch = 1440 twips, 1 inch = 25.4 mm).
  static const double _twipsPerMm = 1440.0 / 25.4;

  /// Half-points per point (font sizes in OOXML are in half-points).
  static const int _halfPointsPerPt = 2;

  @override
  List<String> get supportedFormats => const ['docx'];

  @override
  String? get supportedTemplateRange => '>= 1.0.0 < 2.0.0';

  @override
  Future<FormRenderOutput> render(RenderContext context) async {
    final doc = context.document;
    final layout = context.layoutPolicy;
    final buf = StringBuffer();

    buf.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buf.writeln('<?mso-application progid="Word.Document"?>');
    buf.write('<w:wordDocument');
    buf.write(' xmlns:w="$_wNs"');
    buf.write(' xmlns:r="$_rNs"');
    buf.write(' xmlns:v="urn:schemas-microsoft-com:vml"');
    buf.write(' xmlns:o="urn:schemas-microsoft-com:office:office"');
    buf.writeln('>');

    // Document properties (DR-004: metadata as custom properties)
    if (context.options.includeMetadata) {
      _writeDocumentProperties(buf, doc, context);
    }

    // Font definitions
    _writeFontTable(buf, layout);

    // Style definitions
    _writeStyles(buf, layout);

    // Document body
    buf.writeln('<w:body>');

    for (final section in doc.sections) {
      if (section.title != null) {
        _writeParagraph(buf, _escapeXml(section.title!), headingLevel: 2);
      }
      for (final block in section.blocks) {
        _renderBlock(buf, block, doc.data, layout);
      }
    }

    // Watermark as a final paragraph if specified
    if (context.effectiveWatermark != null) {
      _writeWatermarkParagraph(buf, context.effectiveWatermark!);
    }

    // Section properties (page size and margins)
    _writeSectionProperties(buf, layout);

    buf.writeln('</w:body>');
    buf.writeln('</w:wordDocument>');

    final content = buf.toString();
    final bytes = utf8.encode(content);

    return FormRenderOutput(
      format: 'docx',
      content: bytes,
      pageCount: 1,
      fileSize: bytes.length,
      generatedAt: doc.metadata.modifiedAt ?? doc.metadata.createdAt,
    );
  }

  // ==========================================================================
  // Document Properties (DR-004)
  // ==========================================================================

  void _writeDocumentProperties(
    StringBuffer buf,
    FormDocument doc,
    RenderContext context,
  ) {
    // Core properties
    buf.writeln('<o:DocumentProperties>');
    buf.writeln('  <o:Author>${_escapeXml(doc.metadata.author)}</o:Author>');

    final timestamp = doc.metadata.modifiedAt ?? doc.metadata.createdAt;
    buf.writeln(
      '  <o:Created>${timestamp.toIso8601String()}</o:Created>',
    );
    buf.writeln(
      '  <o:LastSaved>${timestamp.toIso8601String()}</o:LastSaved>',
    );
    buf.writeln('</o:DocumentProperties>');

    // Custom properties for template metadata
    buf.writeln('<o:CustomDocumentProperties>');
    buf.writeln(
      '  <o:templateId>${_escapeXml(doc.templateId)}</o:templateId>',
    );
    buf.writeln(
      '  <o:templateName>${_escapeXml(context.template.name)}</o:templateName>',
    );
    if (doc.metadata.engineVersion != null) {
      buf.writeln(
        '  <o:engineVersion>${_escapeXml(doc.metadata.engineVersion!)}</o:engineVersion>',
      );
    }
    buf.writeln('</o:CustomDocumentProperties>');
  }

  // ==========================================================================
  // Font Table
  // ==========================================================================

  void _writeFontTable(StringBuffer buf, FormLayoutPolicy layout) {
    buf.writeln('<w:fonts>');
    buf.writeln('  <w:defaultFonts');
    buf.writeln('    w:ascii="${_escapeXml(layout.fontFamily)}"');
    buf.writeln('    w:hAnsi="${_escapeXml(layout.fontFamily)}"');
    buf.writeln('    w:eastAsia="${_escapeXml(layout.fontFamily)}"');
    buf.writeln('  />');
    buf.writeln('</w:fonts>');
  }

  // ==========================================================================
  // Styles
  // ==========================================================================

  void _writeStyles(StringBuffer buf, FormLayoutPolicy layout) {
    final fontPolicy = layout.fontPolicy;
    final bodySizeHp = (fontPolicy.bodySize * _halfPointsPerPt).round();

    buf.writeln('<w:styles>');

    // Default document style
    buf.writeln('  <w:style w:type="paragraph" w:default="on" w:styleId="Normal">');
    buf.writeln('    <w:name w:val="Normal"/>');
    buf.writeln('    <w:rPr>');
    buf.writeln('      <w:sz w:val="$bodySizeHp"/>');
    buf.writeln('      <w:szCs w:val="$bodySizeHp"/>');
    buf.writeln('      <w:rFonts w:ascii="${_escapeXml(layout.fontFamily)}"'
        ' w:hAnsi="${_escapeXml(layout.fontFamily)}"/>');
    buf.writeln('    </w:rPr>');
    buf.writeln('  </w:style>');

    // Heading styles (1-6)
    for (var level = 1; level <= 6; level++) {
      final levelSize =
          (fontPolicy.headingSizeForLevel(level) * _halfPointsPerPt).round();
      buf.writeln(
        '  <w:style w:type="paragraph" w:styleId="Heading$level">',
      );
      buf.writeln('    <w:name w:val="heading $level"/>');
      buf.writeln('    <w:pPr>');
      buf.writeln('      <w:outlineLvl w:val="${level - 1}"/>');
      buf.writeln('    </w:pPr>');
      buf.writeln('    <w:rPr>');
      buf.writeln('      <w:b/>');
      buf.writeln('      <w:sz w:val="$levelSize"/>');
      buf.writeln('      <w:szCs w:val="$levelSize"/>');
      buf.writeln('    </w:rPr>');
      buf.writeln('  </w:style>');
    }

    // Table style
    buf.writeln('  <w:style w:type="table" w:styleId="TableGrid">');
    buf.writeln('    <w:name w:val="Table Grid"/>');
    buf.writeln('    <w:tblPr>');
    buf.writeln('      <w:tblBorders>');
    for (final border in ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']) {
      buf.writeln(
        '        <w:$border w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>',
      );
    }
    buf.writeln('      </w:tblBorders>');
    buf.writeln('    </w:tblPr>');
    buf.writeln('  </w:style>');

    buf.writeln('</w:styles>');
  }

  // ==========================================================================
  // Section Properties (Page Layout)
  // ==========================================================================

  void _writeSectionProperties(StringBuffer buf, FormLayoutPolicy layout) {
    final pageW = (layout.effectivePageWidth * _twipsPerMm).round();
    final pageH = (layout.effectivePageHeight * _twipsPerMm).round();
    final marginTop = (layout.margins.top * _twipsPerMm).round();
    final marginRight = (layout.margins.right * _twipsPerMm).round();
    final marginBottom = (layout.margins.bottom * _twipsPerMm).round();
    final marginLeft = (layout.margins.left * _twipsPerMm).round();

    final orient = layout.isLandscape ? ' w:orient="landscape"' : '';

    buf.writeln('<w:sectPr>');
    buf.writeln('  <w:pgSz w:w="$pageW" w:h="$pageH"$orient/>');
    buf.writeln(
      '  <w:pgMar w:top="$marginTop" w:right="$marginRight"'
      ' w:bottom="$marginBottom" w:left="$marginLeft"'
      ' w:header="720" w:footer="720"/>',
    );
    buf.writeln('  <w:cols w:num="${layout.gridColumns}"/>');
    buf.writeln('</w:sectPr>');
  }

  // ==========================================================================
  // Block Rendering
  // ==========================================================================

  void _renderBlock(
    StringBuffer buf,
    FormBlock block,
    Map<String, dynamic> data,
    FormLayoutPolicy layout,
  ) {
    switch (block) {
      case FormTextBlock():
        _writeParagraph(buf, _escapeXml(block.content));

      case FormHeadingBlock():
        final level = block.level.clamp(1, 6);
        _writeParagraph(buf, _escapeXml(block.content), headingLevel: level);

      case FormTableBlock():
        _renderTable(buf, block, layout);

      case FormImageBlock():
        _renderImage(buf, block);

      case FormChartBlock():
        _renderChart(buf, block);

      case FormCanvasBlock():
        _renderCanvas(buf, block);

      case FormFieldBlock():
        _renderField(buf, block, data);

      case FormRepeatableBlock():
        for (final tplBlock in block.itemTemplate) {
          _renderBlock(buf, tplBlock, data, layout);
        }

      case FormConditionalBlock():
        // Render thenBlock by default (condition evaluation is external)
        _renderBlock(buf, block.thenBlock, data, layout);

      default:
        break;
    }
  }

  // ==========================================================================
  // Paragraph Helpers
  // ==========================================================================

  /// Write a paragraph with optional heading style.
  void _writeParagraph(
    StringBuffer buf,
    String text, {
    int? headingLevel,
    bool bold = false,
    bool italic = false,
    String? color,
  }) {
    buf.writeln('<w:p>');

    if (headingLevel != null) {
      buf.writeln('  <w:pPr>');
      buf.writeln('    <w:pStyle w:val="Heading$headingLevel"/>');
      buf.writeln('  </w:pPr>');
    }

    buf.writeln('  <w:r>');
    if (bold || italic || color != null) {
      buf.writeln('    <w:rPr>');
      if (bold) buf.writeln('      <w:b/>');
      if (italic) buf.writeln('      <w:i/>');
      if (color != null) buf.writeln('      <w:color w:val="$color"/>');
      buf.writeln('    </w:rPr>');
    }
    buf.writeln('    <w:t xml:space="preserve">$text</w:t>');
    buf.writeln('  </w:r>');
    buf.writeln('</w:p>');
  }

  /// Write a paragraph with multiple styled runs.
  void _writeMultiRunParagraph(StringBuffer buf, List<_Run> runs) {
    buf.writeln('<w:p>');
    for (final run in runs) {
      buf.writeln('  <w:r>');
      if (run.bold || run.italic || run.color != null) {
        buf.writeln('    <w:rPr>');
        if (run.bold) buf.writeln('      <w:b/>');
        if (run.italic) buf.writeln('      <w:i/>');
        if (run.color != null) {
          buf.writeln('      <w:color w:val="${run.color}"/>');
        }
        buf.writeln('    </w:rPr>');
      }
      buf.writeln(
        '    <w:t xml:space="preserve">${run.text}</w:t>',
      );
      buf.writeln('  </w:r>');
    }
    buf.writeln('</w:p>');
  }

  // ==========================================================================
  // Table Rendering
  // ==========================================================================

  void _renderTable(
    StringBuffer buf,
    FormTableBlock block,
    FormLayoutPolicy layout,
  ) {
    final contentWidthTwips = (layout.contentWidth * _twipsPerMm).round();

    buf.writeln('<w:tbl>');

    // Table properties
    buf.writeln('  <w:tblPr>');
    buf.writeln('    <w:tblStyle w:val="TableGrid"/>');
    buf.writeln('    <w:tblW w:w="$contentWidthTwips" w:type="dxa"/>');
    buf.writeln('    <w:tblBorders>');
    for (final border in ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']) {
      buf.writeln(
        '      <w:$border w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>',
      );
    }
    buf.writeln('    </w:tblBorders>');
    buf.writeln('  </w:tblPr>');

    // Column grid
    final colCount = block.columns.length;
    if (colCount > 0) {
      final colWidth = contentWidthTwips ~/ colCount;
      buf.writeln('  <w:tblGrid>');
      for (var i = 0; i < colCount; i++) {
        buf.writeln('    <w:gridCol w:w="$colWidth"/>');
      }
      buf.writeln('  </w:tblGrid>');
    }

    // Header row
    buf.writeln('  <w:tr>');
    buf.writeln('    <w:trPr><w:tblHeader/></w:trPr>');
    for (final col in block.columns) {
      buf.writeln('    <w:tc>');
      buf.writeln('      <w:tcPr>');
      buf.writeln('        <w:shd w:val="clear" w:fill="F5F5F5"/>');
      buf.writeln('      </w:tcPr>');
      _writeParagraph(buf, _escapeXml(col.title), bold: true);
      buf.writeln('    </w:tc>');
    }
    buf.writeln('  </w:tr>');

    // Data rows
    for (final row in block.rows) {
      buf.writeln('  <w:tr>');
      for (final col in block.columns) {
        final cell = row.cells[col.id];
        buf.writeln('    <w:tc>');
        _writeParagraph(buf, _escapeXml(cell?.toString() ?? ''));
        buf.writeln('    </w:tc>');
      }
      buf.writeln('  </w:tr>');
    }

    buf.writeln('</w:tbl>');
  }

  // ==========================================================================
  // Image Rendering
  // ==========================================================================

  void _renderImage(StringBuffer buf, FormImageBlock block) {
    // Images cannot be embedded inline in Flat OPC without base64 data.
    // Render as a descriptive paragraph with the source reference.
    final altText = block.alt ?? 'Image';
    final widthNote =
        block.maxWidth != null ? ' (max-width: ${block.maxWidth}px)' : '';

    _writeMultiRunParagraph(buf, [
      _Run('[Image: ${_escapeXml(altText)}$widthNote]', italic: true, color: '666666'),
    ]);
    _writeParagraph(buf, 'Source: ${_escapeXml(block.src)}', italic: true);
  }

  // ==========================================================================
  // Chart Rendering
  // ==========================================================================

  void _renderChart(StringBuffer buf, FormChartBlock block) {
    // Charts cannot be rendered natively in Flat OPC XML.
    // Provide a placeholder description.
    _writeMultiRunParagraph(buf, [
      _Run(
        '[Chart: ${_escapeXml(block.chartType)}]',
        bold: true,
        color: '333333',
      ),
    ]);
  }

  void _renderCanvas(StringBuffer buf, FormCanvasBlock block) {
    // DOCX flat-OPC mode cannot embed SVG/raster without a pre-resolved
    // image binary + proper drawing XML — emit a textual placeholder that
    // preserves the target reference + caption so downstream tools or
    // manual review can see what should appear here.
    final label = block.caption ?? block.alt ?? block.target;
    _writeMultiRunParagraph(buf, [
      _Run(
        '[Canvas: ${_escapeXml(label)}]',
        bold: true,
        color: '333333',
      ),
    ]);
    if (block.target.isNotEmpty) {
      _writeMultiRunParagraph(buf, [
        _Run(
          'Target: ${_escapeXml(block.target)}',
          italic: true,
          color: '666666',
        ),
      ]);
    }
  }

  // ==========================================================================
  // Field Rendering
  // ==========================================================================

  void _renderField(
    StringBuffer buf,
    FormFieldBlock block,
    Map<String, dynamic> data,
  ) {
    final value = data[block.fieldName];
    final filled = value != null;

    if (filled) {
      _writeMultiRunParagraph(buf, [
        _Run('${_escapeXml(block.fieldName)}: ', bold: true),
        _Run(_escapeXml(value.toString())),
      ]);
    } else {
      _writeMultiRunParagraph(buf, [
        _Run('${_escapeXml(block.fieldName)}: ', bold: true),
        const _Run('unfilled', italic: true, color: '999999'),
      ]);
    }
  }

  // ==========================================================================
  // Watermark
  // ==========================================================================

  void _writeWatermarkParagraph(StringBuffer buf, String text) {
    // Watermark as a styled paragraph (true watermark requires VML shapes
    // which are complex; a visible text marker is the pragmatic approach).
    _writeParagraph(
      buf,
      _escapeXml(text),
      italic: true,
      color: 'C0C0C0',
    );
  }

  // ==========================================================================
  // XML Escaping
  // ==========================================================================

  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

/// Internal helper for multi-run paragraph building.
class _Run {
  const _Run(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.color,
  });

  final String text;
  final bool bold;
  final bool italic;
  final String? color;
}
