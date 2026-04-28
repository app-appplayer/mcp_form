import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';

import '../../../core/template/layout_extensions.dart';
import '../render_context.dart';
import '../renderer_registry.dart';

/// PDF output renderer using raw PDF syntax.
///
/// Produces a valid PDF 1.4 document without external dependencies.
/// Text content is rendered using built-in Type1 fonts (Helvetica family).
/// Page dimensions are derived from the document's [FormLayoutPolicy].
class PdfRenderer implements DocumentRenderer {
  const PdfRenderer();

  /// Millimeters to PDF points conversion factor.
  static const double _mmToPt = 2.8346;

  @override
  List<String> get supportedFormats => const ['pdf'];

  @override
  String? get supportedTemplateRange => '>= 1.0.0 < 2.0.0';

  @override
  Future<FormRenderOutput> render(RenderContext context) async {
    final doc = context.document;
    final layout = context.layoutPolicy;
    final fontPolicy = layout.fontPolicy;

    // Page dimensions in points
    final pageWidthPt = layout.effectivePageWidth * _mmToPt;
    final pageHeightPt = layout.effectivePageHeight * _mmToPt;
    final marginTop = layout.margins.top * _mmToPt;
    final marginLeft = layout.margins.left * _mmToPt;
    final contentWidthPt = layout.contentWidth * _mmToPt;
    final contentHeightPt = layout.contentHeight * _mmToPt;

    final bodySize = fontPolicy.bodySize.toDouble();
    final lineHeight = bodySize * 1.4;
    // Collect content lines per page
    // Each line: (text, fontSize, isBold)
    final pages = <List<_PdfLine>>[];
    var currentPage = <_PdfLine>[];
    var cursorY = 0.0;

    void ensureSpace(double needed) {
      if (cursorY + needed > contentHeightPt && currentPage.isNotEmpty) {
        pages.add(currentPage);
        currentPage = <_PdfLine>[];
        cursorY = 0.0;
      }
    }

    void addLine(String text, double fontSize, {bool bold = false}) {
      final lh = fontSize * 1.4;
      ensureSpace(lh);
      currentPage.add(_PdfLine(text, fontSize, bold: bold));
      cursorY += lh;
    }

    void addBlankLine() {
      cursorY += lineHeight * 0.5;
    }

    // Estimate characters per line for text wrapping
    int charsPerLine(double fontSize) {
      // Approximate average character width for Helvetica
      final avgCharWidth = fontSize * 0.5;
      return (contentWidthPt / avgCharWidth).floor().clamp(1, 10000);
    }

    // Wrap long text into multiple lines
    void addWrappedText(
      String text,
      double fontSize, {
      bool bold = false,
    }) {
      final maxChars = charsPerLine(fontSize);
      final words = text.split(' ');
      var line = StringBuffer();

      for (final word in words) {
        if (line.isEmpty) {
          line.write(word);
        } else if (line.length + 1 + word.length <= maxChars) {
          line.write(' $word');
        } else {
          addLine(line.toString(), fontSize, bold: bold);
          line = StringBuffer(word);
        }
      }
      if (line.isNotEmpty) {
        addLine(line.toString(), fontSize, bold: bold);
      }
    }

    // Render blocks recursively
    void renderBlock(FormBlock block, Map<String, dynamic> data) {
      switch (block) {
        case FormTextBlock():
          addWrappedText(block.content, bodySize);
          addBlankLine();

        case FormHeadingBlock():
          final level = block.level.clamp(1, 6);
          final size = fontPolicy.headingSizeForLevel(level);
          addWrappedText(block.content, size, bold: true);
          addBlankLine();

        case FormTableBlock():
          // Build header text and separator for reuse (FR-REND-008)
          final headerText =
              block.columns.map((c) => c.title).join('  |  ');
          final separator = '-' * charsPerLine(bodySize).clamp(1, 80);

          // Render initial table header
          addLine(headerText, bodySize, bold: true);
          addLine(separator, bodySize);

          // Render rows with header repetition on page break
          for (final row in block.rows) {
            final cells = block.columns.map((col) {
              final cell = row.cells[col.id];
              return cell?.toString() ?? '';
            }).join('  |  ');

            // Check if the next row would overflow the current page
            final neededHeight = bodySize * 1.4;
            if (cursorY + neededHeight > contentHeightPt &&
                currentPage.isNotEmpty) {
              // Force page break and repeat header on new page
              pages.add(currentPage);
              currentPage = <_PdfLine>[];
              cursorY = 0.0;
              addLine(headerText, bodySize, bold: true);
              addLine(separator, bodySize);
            }

            addWrappedText(cells, bodySize);
          }
          addBlankLine();

        case FormImageBlock():
          // Images cannot be embedded in raw PDF text stream;
          // render a placeholder with alt text
          final altText = block.alt ?? 'Image';
          addLine('[Image: $altText]', bodySize);
          if (block.src.isNotEmpty) {
            addLine('  Source: ${block.src}', bodySize * 0.8);
          }
          addBlankLine();

        case FormChartBlock():
          // Charts cannot be rendered in raw PDF text;
          // render a placeholder
          addLine('[Chart: ${block.chartType}]', bodySize);
          addBlankLine();

        case FormCanvasBlock():
          // Live canvas scenes require a CanvasBindingResolver to be
          // pre-resolved into bytes before reaching the renderer. In raw
          // PDF text mode we always fall back to a placeholder labelled
          // with the caption/target so downstream reviewers see what
          // should be embedded.
          final label = block.caption ?? block.alt ?? block.target;
          addLine('[Canvas: $label]', bodySize);
          if (block.target.isNotEmpty) {
            addLine('  Target: ${block.target}', bodySize * 0.8);
          }
          addBlankLine();

        case FormFieldBlock():
          final value = data[block.fieldName];
          final display = value != null ? value.toString() : '(unfilled)';
          addWrappedText('${block.fieldName}: $display', bodySize);
          addBlankLine();

        case FormRepeatableBlock():
          for (final tplBlock in block.itemTemplate) {
            renderBlock(tplBlock, data);
          }

        case FormConditionalBlock():
          // Render thenBlock by default (condition evaluation is external)
          renderBlock(block.thenBlock, data);

        default:
          break;
      }
    }

    // Iterate sections and blocks
    for (final section in doc.sections) {
      if (section.title != null) {
        final sectionHeadingSize = fontPolicy.headingSizeForLevel(2);
        addWrappedText(section.title!, sectionHeadingSize, bold: true);
        addBlankLine();
      }
      for (final block in section.blocks) {
        renderBlock(block, doc.data);
      }
    }

    // Flush last page
    if (currentPage.isNotEmpty) {
      pages.add(currentPage);
    }

    // Ensure at least one page
    if (pages.isEmpty) {
      pages.add(<_PdfLine>[]);
    }

    final pageCount = pages.length;

    // Build PDF objects
    final objects = <int, String>{};
    var nextObjId = 1;

    int allocObj() => nextObjId++;

    final catalogId = allocObj(); // 1
    final pagesObjId = allocObj(); // 2
    final fontRegularId = allocObj(); // 3
    final fontBoldId = allocObj(); // 4

    // Allocate page + content stream objects
    final pageObjIds = <int>[];
    final contentObjIds = <int>[];
    for (var i = 0; i < pageCount; i++) {
      pageObjIds.add(allocObj());
      contentObjIds.add(allocObj());
    }

    // Info dictionary for metadata (DR-004)
    final infoId = allocObj();

    // Catalog
    objects[catalogId] = '<</Type /Catalog /Pages $pagesObjId 0 R>>';

    // Pages
    final kidsStr = pageObjIds.map((id) => '$id 0 R').join(' ');
    objects[pagesObjId] =
        '<</Type /Pages /Kids [$kidsStr] /Count $pageCount>>';

    // Fonts
    objects[fontRegularId] =
        '<</Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding>>';
    objects[fontBoldId] =
        '<</Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding>>';

    // Build each page
    for (var i = 0; i < pageCount; i++) {
      final lines = pages[i];
      final streamBuf = StringBuffer();

      // Watermark (rendered first so it appears behind text)
      if (context.effectiveWatermark != null) {
        final wmText = _escapePdfString(context.effectiveWatermark!);
        streamBuf.writeln('q');
        // Translucent grey, rotated 45 degrees
        streamBuf.writeln('0.85 0.85 0.85 rg');
        final cx = pageWidthPt / 2;
        final cy = pageHeightPt / 2;
        // Rotation matrix: cos(45) sin(45) -sin(45) cos(45) tx ty
        const cos45 = 0.7071;
        const sin45 = 0.7071;
        streamBuf.writeln(
          '$cos45 $sin45 ${-sin45} $cos45 '
          '${cx.toStringAsFixed(2)} ${cy.toStringAsFixed(2)} cm',
        );
        streamBuf.writeln('BT');
        streamBuf.writeln('/F1 48 Tf');
        // Center the watermark approximately
        final wmWidth = wmText.length * 48 * 0.5;
        streamBuf.writeln('${(-wmWidth / 2).toStringAsFixed(2)} 0 Td');
        streamBuf.writeln('($wmText) Tj');
        streamBuf.writeln('ET');
        streamBuf.writeln('Q');
      }

      // Text content
      streamBuf.writeln('BT');

      // Starting position: top-left of content area
      final startX = marginLeft;
      final startY = pageHeightPt - marginTop - bodySize;
      streamBuf.writeln(
        '${startX.toStringAsFixed(2)} ${startY.toStringAsFixed(2)} Td',
      );

      var prevFontKey = '';
      var prevFontSize = 0.0;

      for (var j = 0; j < lines.length; j++) {
        final line = lines[j];
        final fontKey = line.bold ? '/F2' : '/F1';
        final fontSize = line.fontSize;

        if (fontKey != prevFontKey || fontSize != prevFontSize) {
          streamBuf.writeln('$fontKey ${fontSize.toStringAsFixed(1)} Tf');
          prevFontKey = fontKey;
          prevFontSize = fontSize;
        }

        if (j > 0) {
          // Move down by line height (negative Y in PDF)
          final lh = line.fontSize * 1.4;
          streamBuf.writeln('0 ${(-lh).toStringAsFixed(2)} Td');
        }

        final escaped = _escapePdfString(line.text);
        streamBuf.writeln('($escaped) Tj');
      }

      streamBuf.writeln('ET');

      final streamContent = streamBuf.toString();
      final streamLength = utf8.encode(streamContent).length;

      objects[contentObjIds[i]] =
          '<</Length $streamLength>>\nstream\n${streamContent}endstream';

      objects[pageObjIds[i]] =
          '<</Type /Page /Parent $pagesObjId 0 R '
          '/MediaBox [0 0 ${pageWidthPt.toStringAsFixed(2)} ${pageHeightPt.toStringAsFixed(2)}] '
          '/Contents ${contentObjIds[i]} 0 R '
          '/Resources <</Font <</F1 $fontRegularId 0 R /F2 $fontBoldId 0 R>>>>>>';
    }

    // Info dictionary (DR-004: deterministic timestamp)
    final timestamp = doc.metadata.modifiedAt ?? doc.metadata.createdAt;
    final pdfDate = _formatPdfDate(timestamp);
    final infoParts = <String>[
      '/CreationDate ($pdfDate)',
      '/ModDate ($pdfDate)',
    ];
    if (context.options.includeMetadata) {
      infoParts.add('/Author (${_escapePdfString(doc.metadata.author)})');
      infoParts.add(
        '/Subject (${_escapePdfString(doc.templateId)})',
      );
      infoParts.add(
        '/Title (${_escapePdfString(context.template.name)})',
      );
    }
    objects[infoId] = '<<${infoParts.join(' ')}>>';

    // Serialize PDF
    final output = StringBuffer();
    output.writeln('%PDF-1.4');

    // Object offsets for xref
    final offsets = <int, int>{};
    final totalObjects = nextObjId - 1;

    for (var id = 1; id <= totalObjects; id++) {
      final body = objects[id]!;
      offsets[id] = utf8.encode(output.toString()).length;
      output.writeln('$id 0 obj');
      output.writeln(body);
      output.writeln('endobj');
    }

    // Cross-reference table
    final xrefOffset = utf8.encode(output.toString()).length;
    output.writeln('xref');
    output.writeln('0 ${totalObjects + 1}');
    output.writeln('0000000000 65535 f ');
    for (var id = 1; id <= totalObjects; id++) {
      final offset = offsets[id]!.toString().padLeft(10, '0');
      output.writeln('$offset 00000 n ');
    }

    // Trailer
    output.writeln('trailer');
    output.writeln(
      '<</Size ${totalObjects + 1} /Root $catalogId 0 R /Info $infoId 0 R>>',
    );
    output.writeln('startxref');
    output.writeln(xrefOffset);
    output.writeln('%%EOF');

    final bytes = utf8.encode(output.toString());

    return FormRenderOutput(
      format: 'pdf',
      content: bytes,
      pageCount: pageCount,
      fileSize: bytes.length,
      generatedAt: timestamp,
    );
  }

  /// Escape special PDF string characters.
  static String _escapePdfString(String text) {
    return text
        .replaceAll(r'\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
  }

  /// Format a DateTime as a PDF date string (D:YYYYMMDDHHmmSS).
  static String _formatPdfDate(DateTime dt) {
    final utc = dt.toUtc();
    return 'D:${utc.year.toString().padLeft(4, '0')}'
        '${utc.month.toString().padLeft(2, '0')}'
        '${utc.day.toString().padLeft(2, '0')}'
        '${utc.hour.toString().padLeft(2, '0')}'
        '${utc.minute.toString().padLeft(2, '0')}'
        '${utc.second.toString().padLeft(2, '0')}Z';
  }
}

/// Internal representation of a single line of PDF text content.
class _PdfLine {
  const _PdfLine(this.text, this.fontSize, {this.bold = false});

  final String text;
  final double fontSize;
  final bool bold;
}
