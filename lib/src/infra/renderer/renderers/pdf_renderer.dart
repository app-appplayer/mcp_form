import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:mcp_bundle/mcp_bundle.dart';

import '../../../core/binding/repeatable_binding.dart';
import '../../../core/condition/condition_evaluator.dart';
import '../../../core/document/document_numbering.dart';
import '../../../core/template/layout_extensions.dart';
import '../../../style/deflate.dart';
import '../../../style/style.dart';
import '../render_context.dart';
import '../renderer_registry.dart';

/// Apply per-script shaping to each run's text so an embedded font renders it
/// correctly: Arabic contextual joining (Presentation Forms-B) and Devanagari
/// pre-base matra reordering. Visual (right-to-left) ordering is applied later,
/// per line, by the bidi pass. Text needing no shaping is returned unchanged.
FormRichText _shapeRich(FormRichText rich) {
  final needsArabic = rich.runs.any((r) => hasArabic(r.text));
  final needsIndic = rich.runs.any((r) => hasDevanagari(r.text));
  if (!needsArabic && !needsIndic) return rich;
  return FormRichText([
    for (final run in rich.runs)
      InlineRun(_shapeText(run.text, needsArabic, needsIndic), run.style),
  ]);
}

String _shapeText(String text, bool arabic, bool indic) {
  var s = text;
  if (arabic) s = shapeArabic(s);
  if (indic) s = reorderDevanagari(s);
  return s;
}

/// PDF output renderer using raw PDF syntax.
///
/// Produces a valid PDF 1.4 document without external dependencies. Text is
/// rendered with the built-in Type1 Helvetica family (regular / bold / oblique
/// / bold-oblique). Rich inline runs (colour, underline, strike, highlight,
/// super- & subscript), per-block boxes (background / border, splittable across
/// pages) and copy-fit are driven by the `style` layer. Page dimensions come
/// from the document's [FormLayoutPolicy].
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
    // Document-wide numbering (headings / captions / cross-references). Computed
    // once; the heading case prefixes its number and text blocks resolve refs.
    final numbering = DocumentNumbering.compute(doc.sections);
    // Footnotes collected in render order; emitted as endnotes at the end.
    final footnotes = FootnoteCollector();
    final layout = context.layoutPolicy;
    final fontPolicy = layout.fontPolicy;
    final sheet = context.styleSheet;
    final embedded = context.embeddedFont;
    final FontMetrics metrics = embedded == null
        ? const HelveticaMetrics()
        : context.fallbackFonts.isEmpty
            ? TrueTypeMetrics(embedded)
            : FallbackMetrics([embedded, ...context.fallbackFonts]);
    final continuous = context.options.pageFlow == PageFlow.continuous;

    final pageWidthPt = layout.effectivePageWidth * _mmToPt;
    final pageHeightPt = layout.effectivePageHeight * _mmToPt;
    final marginTop = layout.margins.top * _mmToPt;
    final marginBottom = layout.margins.bottom * _mmToPt;
    final baseMarginLeft = layout.margins.left * _mmToPt;
    final fullContentWidthPt = layout.contentWidth * _mmToPt;
    final contentHeightPt = layout.contentHeight * _mmToPt;
    // In continuous mode nothing breaks — the single page grows to fit.
    final flowHeight = continuous ? double.infinity : contentHeightPt;

    // Multi-column newspaper flow (paged mode only). Content flows down a column
    // then into the next column on the same page; only the last column triggers
    // a real page break. columnCount == 1 (default) keeps the single-column path
    // byte-for-byte. This is a render-time option (mcp_form), not a core field.
    final columnCount = continuous ? 1 : context.options.columnCount.clamp(1, 8);
    final columnGap = context.options.columnGap;
    final colWidth =
        (fullContentWidthPt - (columnCount - 1) * columnGap) / columnCount;
    var currentColumn = 0;
    // The current column's left edge and usable width — every build-phase helper
    // positions against these, so a column reads exactly like a narrow page.
    var marginLeft = baseMarginLeft;
    var contentWidthPt = columnCount == 1 ? fullContentWidthPt : colWidth;

    // A theme may override the base body size (other sizes stay relative).
    final bodySize =
        (sheet?.theme.baseFontSize ?? fontPolicy.bodySize).toDouble();
    final minSize = fontPolicy.minSize.toDouble();
    final defaultLineHeight = bodySize * 1.4;

    // Page model. Each page is a list of draw items (boxes / images / lines).
    final pages = <List<Object>>[];
    var currentPage = <Object>[];
    var cursorY = 0.0;

    // Tagged-PDF (PDF/UA) structure. Each taggable draw item is stamped with the
    // active structure-element index; unstamped items are artifacts. Inert when
    // options.taggedPdf is off (activeStruct stays null → no BDC/EMC emitted).
    final tagged = context.options.taggedPdf;
    final structTags = <String>[]; // struct index -> structure type (P / H1 …)
    final structParents = <int>[]; // struct index -> parent index (-1 = Document)
    final structAlt = <int, String>{}; // struct index -> alt text (Figures)
    int? activeStruct;
    int newStruct(String type, {int parent = -1}) {
      structTags.add(type);
      structParents.add(parent);
      return structTags.length - 1;
    }

    // Add a draw item to the current page, stamping it with the active
    // structure element for tagging.
    void emit(Object item) {
      if (item is _PdfTextLine) {
        item.structId = activeStruct;
      } else if (item is _PdfBox) {
        item.structId = activeStruct;
      } else if (item is _PdfImage) {
        item.structId = activeStruct;
      } else if (item is _PdfChart) {
        item.structId = activeStruct;
      }
      currentPage.add(item);
    }

    // Table-of-contents page numbering. As each heading is placed we record the
    // page list it landed on; the TOC reserves a right-aligned slot per entry
    // and we draw the resolved page number after the full layout is known.
    final headingPageRef = <String, List<Object>>{};
    final tocPageSlots =
        <({List<Object> page, double yTop, String blockId, double rightX, double size})>[];
    // Interactive AcroForm text-field widgets (options.fillableFields), resolved
    // to page indices during assembly.
    final formFieldWidgets = <
        ({
          List<Object> page,
          double xLeft,
          double yTop,
          double width,
          double height,
          String name,
          String value
        })>[];

    // Active splittable box (background / border) being laid out, if any.
    _ActiveBox? activeBox;

    void emitBoxFragment(_ActiveBox box, double bottomY, bool bottomOpen) {
      box.list.add(_PdfBox(
        xLeft: marginLeft + box.indent,
        width: contentWidthPt - box.indent,
        yTop: box.topY,
        height: (bottomY - box.topY).clamp(0.0, flowHeight),
        fill: hexToRgb(box.backgroundHex),
        stroke: box.borderColor == null ? null : hexToRgb(box.borderColor),
        strokeWidth: box.borderWidth,
        topOpen: box.topOpen,
        bottomOpen: bottomOpen,
      ));
    }

    void breakPage() {
      if (activeBox != null) {
        // Close this fragment open at the bottom; the frame continues overleaf.
        emitBoxFragment(activeBox!, contentHeightPt, true);
      }
      if (currentColumn < columnCount - 1) {
        // Move to the next column on the same page.
        currentColumn++;
        marginLeft = baseMarginLeft + currentColumn * (colWidth + columnGap);
        cursorY = 0.0;
      } else {
        // Last column full — start a new page back at the first column.
        pages.add(currentPage);
        currentPage = <Object>[];
        currentColumn = 0;
        marginLeft = baseMarginLeft;
        cursorY = 0.0;
      }
      if (activeBox != null) {
        activeBox!
          ..list = currentPage
          ..topY = 0.0
          ..topOpen = true;
      }
    }

    // Force the very next content onto a fresh page (an explicit page break,
    // regardless of column). No-op on an empty first page.
    void forcePageBreak() {
      if (currentPage.isEmpty && currentColumn == 0 && cursorY == 0.0) return;
      if (activeBox != null) {
        emitBoxFragment(activeBox!, contentHeightPt, true);
      }
      pages.add(currentPage);
      currentPage = <Object>[];
      currentColumn = 0;
      marginLeft = baseMarginLeft;
      cursorY = 0.0;
      if (activeBox != null) {
        activeBox!
          ..list = currentPage
          ..topY = 0.0
          ..topOpen = true;
      }
    }

    void ensureSpace(double needed) {
      if (cursorY + needed > flowHeight && currentPage.isNotEmpty) {
        breakPage();
      }
    }

    // ---- Low-level plain helpers (used by tables / section titles) ----

    void addPlainLine(String text, double fontSize, {bool bold = false}) {
      final lh = fontSize * 1.4;
      ensureSpace(lh);
      emit(_PdfTextLine(
        segments: [
          _PdfSeg(text: text, x: marginLeft, size: fontSize, bold: bold),
        ],
        yTop: cursorY,
        maxSize: fontSize,
      ));
      cursorY += lh;
    }

    void addBlankLine() => cursorY += defaultLineHeight * 0.5;

    void addWrappedPlain(String text, double fontSize, {bool bold = false}) {
      final lines = wrapRichText(
        _shapeRich(FormRichText.plain(text)),
        contentWidthPt,
        TextRunStyle(fontSize: fontSize, bold: bold ? true : null),
        metrics: metrics,
      );
      for (final line in lines) {
        final lh = line.maxSize * 1.4;
        ensureSpace(lh);
        final pl = _pdfLineFrom(
            line, marginLeft, contentWidthPt, FormTextAlign.left, null,
            metrics: metrics, isLast: true, baseRtl: baseIsRtl(text));
        pl.yTop = cursorY;
        emit(pl);
        cursorY += lh;
      }
    }

    // ---- Rich textual block path (text / heading / field) ----

    void renderTextual(
      FormRichText rich,
      Map<String, dynamic>? blockStyle, {
      bool heading = false,
      int headingLevel = 1,
      double? defaultSizePt,
    }) {
      final rs = resolveStyle(
        blockStyle: blockStyle,
        layout: layout,
        sheet: sheet,
        defaultSizePt: defaultSizePt,
        heading: heading,
        headingLevel: headingLevel,
      );
      rich = _shapeRich(rich);
      // Headings default to bold unless the author overrides it.
      final base = heading && rs.base.bold == null
          ? rs.base.merge(const TextRunStyle(bold: true))
          : rs.base;

      final hasBox = rs.border != null || rs.backgroundHex != null;
      final pad = hasBox ? rs.paddingPt : 0.0;
      final availWidth = contentWidthPt - rs.indentPt - 2 * pad;

      final fit = fitText(
        rich,
        availWidth,
        base,
        maxHeightPt: rs.boxHeightPt,
        lineHeightMul: rs.lineHeightMul,
        minSize: minSize,
        overflow: rs.overflow,
        metrics: metrics,
      );

      if (rs.spaceBefore != null) cursorY += rs.spaceBefore!;

      if (hasBox) {
        // A box should not start at the very bottom of a page.
        ensureSpace((fit.lines.isEmpty ? defaultLineHeight : 0) + pad * 2);
        activeBox = _ActiveBox(
          list: currentPage,
          topY: cursorY,
          indent: rs.indentPt,
          backgroundHex: rs.backgroundHex,
          borderColor: rs.border?.color,
          borderWidth: rs.border?.width ?? 1.0,
          topOpen: false,
        );
        cursorY += pad;
      }

      // One base direction for the whole paragraph (UAX #9 P2/P3), not guessed
      // per wrapped line. An RTL paragraph right-aligns by default unless the
      // author set an explicit alignment.
      final paraRtl = baseIsRtl(rich.runs.map((r) => r.text).join());
      final effAlign = (paraRtl == true && blockStyle?['align'] == null)
          ? FormTextAlign.right
          : rs.align;

      final textLeft = marginLeft + rs.indentPt + pad;
      final n = fit.lines.length;

      void placeLine(int li) {
        final line = fit.lines[li];
        final pl = _pdfLineFrom(line, textLeft, availWidth, effAlign, rs,
            metrics: metrics, isLast: li == n - 1, baseRtl: paraRtl);
        pl.yTop = cursorY;
        emit(pl);
        cursorY += line.maxSize * rs.lineHeightMul;
      }

      if (hasBox) {
        // Boxed blocks split with their border (activeBox); keep the simple flow.
        for (var li = 0; li < n; li++) {
          ensureSpace(fit.lines[li].maxSize * rs.lineHeightMul);
          placeLine(li);
        }
      } else {
        // B1 pagination quality (paged, non-boxed): keep-together + widow/orphan.
        // Defaults of 1 keep the historical break-anywhere behaviour; authors
        // raise `orphans`/`widows` (min lines kept at the bottom / top of a page)
        // or set `keepTogether` for professional break control.
        final heights = [for (final l in fit.lines) l.maxSize * rs.lineHeightMul];
        final keepTogether = blockStyle?['keepTogether'] == true;
        final orphans = ((blockStyle?['orphans'] as num?)?.toInt() ?? 1);
        final widows = ((blockStyle?['widows'] as num?)?.toInt() ?? 1);
        final blockTotal = heights.fold<double>(0, (a, b) => a + b);

        // keep-together: move the whole block to a fresh column/page if it does
        // not fit here but would fit in a full one.
        if (keepTogether &&
            cursorY + blockTotal > flowHeight &&
            blockTotal <= flowHeight &&
            currentPage.isNotEmpty) {
          breakPage();
        }

        var i = 0;
        while (i < n) {
          // Lines from i that fit in the space left in the current column.
          var fitCount = 0;
          var y = cursorY;
          while (i + fitCount < n && y + heights[i + fitCount] <= flowHeight) {
            y += heights[i + fitCount];
            fitCount++;
          }
          if (i + fitCount >= n) {
            for (var k = i; k < n; k++) {
              placeLine(k);
            }
            break;
          }
          // A break is required. Decide how many lines to keep on this page.
          var take = fitCount;
          // widows: don't strand fewer than `widows` lines on the next page.
          if (n - (i + take) < widows) take = (n - i) - widows;
          // orphans: don't leave fewer than `orphans` lines at the bottom here.
          final atColumnTop = currentPage.isEmpty || cursorY == 0.0;
          if (take < orphans && !atColumnTop) {
            // Push the whole remainder to the next column/page.
            breakPage();
            continue;
          }
          if (take < 1) take = fitCount < 1 ? 1 : fitCount; // guarantee progress
          for (var k = i; k < take + i; k++) {
            placeLine(k);
          }
          i += take;
          if (i < n) breakPage();
        }
      }

      if (hasBox && activeBox != null) {
        cursorY += pad;
        emitBoxFragment(activeBox!, cursorY, false);
        activeBox = null;
      }

      cursorY += rs.spaceAfter ?? defaultLineHeight * 0.5;
    }

    // ---- List path (bullet / ordered) — each source line is an item ----

    void renderList(FormTextBlock block) {
      final rs = resolveStyle(
        blockStyle: block.style,
        layout: layout,
        sheet: sheet,
      );
      final base = rs.base;
      final itemSize = base.fontSize ?? bodySize;
      final itemBold = base.bold ?? false;

      if (rs.spaceBefore != null) cursorY += rs.spaceBefore!;

      final listStruct = activeStruct; // the L element
      var ordinal = 0;
      for (final raw in block.content.split('\n')) {
        if (raw.trim().isEmpty) continue; // blank lines separate, not items
        // Each item is an LI element nested under the list.
        if (tagged && listStruct != null) {
          activeStruct = newStruct('LI', parent: listStruct);
        }
        final marker = listMarker(ordinal, rs.listStyle, rs.numberFormat);
        ordinal++;
        // Hanging indent: the marker sits at the indent edge, wrapped text aligns
        // to a column one marker-width in.
        final hang = measureText('$marker ', itemSize,
            bold: itemBold, metrics: metrics);
        final itemLeft = marginLeft + rs.indentPt;
        final avail = contentWidthPt - rs.indentPt - hang;
        final itemRich = _shapeRich(FormRichText.parse(
            footnotes.consume(applyCrossRefs(raw, numbering)),
            format: block.format));
        final lines = wrapRichText(itemRich, avail, base, metrics: metrics);
        for (var li = 0; li < lines.length; li++) {
          final line = lines[li];
          final lh = line.maxSize * rs.lineHeightMul;
          ensureSpace(lh);
          if (li == 0) {
            emit(_PdfTextLine(
              segments: [
                _PdfSeg(text: marker, x: itemLeft, size: itemSize, bold: itemBold),
              ],
              yTop: cursorY,
              maxSize: line.maxSize,
            ));
          }
          final pl = _pdfLineFrom(
              line, itemLeft + hang, avail, FormTextAlign.left, rs,
              metrics: metrics,
              isLast: li == lines.length - 1,
              baseRtl: baseIsRtl(raw));
          pl.yTop = cursorY;
          emit(pl);
          cursorY += lh;
        }
        activeStruct = listStruct;
      }

      cursorY += rs.spaceAfter ?? defaultLineHeight * 0.5;
    }

    // ---- Table of contents (a text block whose style.toc is true) ----

    // Render the document outline from the numbering pass. The optional block
    // content is the TOC title. Each entry is one line, indented by its heading
    // level, showing "<number>  <title>" on the left and reserving a
    // right-aligned slot; the page number is drawn once the layout is final.
    void renderToc(FormTextBlock block) {
      final title = block.content.trim();
      if (title.isNotEmpty) {
        addWrappedPlain(title, fontPolicy.headingSizeForLevel(2), bold: true);
        addBlankLine();
      }
      for (final e in numbering.tocEntries) {
        final lh = bodySize * 1.4;
        // Break first so the whole entry — and its page-number slot — sits on
        // one page.
        ensureSpace(lh);
        final indent = (e.level - 1) * 14.0;
        final prefix = e.number.isEmpty ? '' : '${e.number}  ';
        emit(_PdfTextLine(
          segments: [
            _PdfSeg(
                text: '$prefix${e.text}',
                x: marginLeft + indent,
                size: bodySize),
          ],
          yTop: cursorY,
          maxSize: bodySize,
        ));
        tocPageSlots.add((
          page: currentPage,
          yTop: cursorY,
          blockId: e.blockId,
          rightX: marginLeft + contentWidthPt,
          size: bodySize,
        ));
        cursorY += lh;
      }
      addBlankLine();
    }

    // Lay out and draw a display equation (a text block with style.math). The
    // box layout centres the formula; glyphs become text lines and fraction /
    // root rules become filled boxes. Non-Latin math symbols (∑, √, Greek…)
    // require an embedded font that carries them.
    void renderMath(String expr) {
      final ast = parseMath(expr);
      final size = bodySize * 1.1;
      final laid = layoutMath(
          ast, size, (t, s) => measureText(t, s, metrics: metrics));
      ensureSpace(laid.height);
      final left = marginLeft + (contentWidthPt - laid.width) / 2;
      for (final r in laid.rules) {
        emit(_PdfBox(
          xLeft: left + r.x,
          width: r.width,
          yTop: cursorY + r.top,
          height: r.thickness,
          fill: (r: 0.0, g: 0.0, b: 0.0),
          stroke: null,
          strokeWidth: 0,
          topOpen: false,
          bottomOpen: false,
        ));
      }
      for (final g in laid.glyphs) {
        emit(_PdfTextLine(
          segments: [
            _PdfSeg(
                text: g.text,
                x: left + g.x,
                size: g.size,
                italic: g.italic),
          ],
          yTop: cursorY + g.baselineTop - g.size,
          maxSize: g.size,
        ));
      }
      cursorY += laid.height + defaultLineHeight * 0.6;
    }

    // Draw an auto-numbered caption ("Figure 1: ...") under a figure / table,
    // when the block carries a caption in its style. No-op otherwise.
    void renderCaption(FormBlock block) {
      final label = numbering.captionLabel(block.blockId);
      if (label == null) return;
      final caption = block.style?['caption'] as String?;
      final text =
          caption == null || caption.isEmpty ? label : '$label: $caption';
      addWrappedPlain(text, bodySize * 0.9, bold: true);
      addBlankLine();
    }

    // ---- Image decode + placement (unchanged behaviour) ----

    void renderBarcode(FormImageBlock block) {
      final code = encodeCode128B(barcodeData(block.src));
      final barH = block.style?['height'] is num
          ? (block.style!['height'] as num).toDouble()
          : 40.0;
      // Fit the symbol (plus a 10-module quiet zone each side) to the content
      // width; each module is at least 1pt so scanners can resolve the bars.
      final totalModules = code.width + 20;
      final unit = math.max(contentWidthPt / totalModules, 1.0);
      final quiet = 10 * unit;
      ensureSpace(barH);
      // Coalesce consecutive dark modules into one filled bar rectangle.
      var x = marginLeft + quiet;
      var i = 0;
      while (i < code.modules.length) {
        if (!code.modules[i]) {
          x += unit;
          i++;
          continue;
        }
        var run = 0;
        while (i < code.modules.length && code.modules[i]) {
          run++;
          i++;
        }
        emit(_PdfBox(
          xLeft: x,
          width: run * unit,
          yTop: cursorY,
          height: barH,
          fill: (r: 0.0, g: 0.0, b: 0.0),
          stroke: null,
          strokeWidth: 0,
          topOpen: false,
          bottomOpen: false,
        ));
        x += run * unit;
      }
      cursorY += barH + defaultLineHeight * 0.5;
    }

    void renderQr(FormImageBlock block) {
      final qr = encodeQr(qrData(block.src));
      const quiet = 4;
      final styleSize = (block.style?['height'] as num?)?.toDouble();
      final target = styleSize ?? math.min(contentWidthPt * 0.4, 130.0);
      final unit = target / (qr.size + 2 * quiet);
      final side = (qr.size + 2 * quiet) * unit;
      ensureSpace(side);
      final originX = marginLeft;
      final originY = cursorY;
      for (var row = 0; row < qr.size; row++) {
        var col = 0;
        while (col < qr.size) {
          if (!qr.modules[row][col]) {
            col++;
            continue;
          }
          var run = 0;
          while (col + run < qr.size && qr.modules[row][col + run]) {
            run++;
          }
          emit(_PdfBox(
            xLeft: originX + (quiet + col) * unit,
            width: run * unit,
            yTop: originY + (quiet + row) * unit,
            height: unit,
            fill: (r: 0.0, g: 0.0, b: 0.0),
            stroke: null,
            strokeWidth: 0,
            topOpen: false,
            bottomOpen: false,
          ));
          col += run;
        }
      }
      cursorY += side + defaultLineHeight * 0.5;
    }

    void renderImage(FormImageBlock block) {
      if (isQrSrc(block.src)) {
        renderQr(block);
        return;
      }
      if (isBarcodeSrc(block.src)) {
        renderBarcode(block);
        return;
      }
      final im = _decodeImage(block.src);
      if (im != null) {
        var drawW = contentWidthPt;
        // Cap to the block's maxWidth (declared in px, as in the HTML
        // renderer's `max-width: Npx`) so a small image — e.g. an 80px stamp —
        // is not blown up to the full content width. px → pt at 96→72 dpi.
        final maxW = block.maxWidth;
        if (maxW != null) {
          final maxPt = maxW.toDouble() * 0.75;
          if (maxPt < drawW) drawW = maxPt;
        }
        final ratio = block.aspectRatio ?? (im.h / im.w);
        var drawH = drawW * ratio;
        if (drawH > contentHeightPt) {
          drawW *= contentHeightPt / drawH;
          drawH = contentHeightPt;
        }
        ensureSpace(drawH);
        emit(_PdfImage(
          bytes: im.bytes,
          dctDecode: im.dct,
          pxW: im.w,
          pxH: im.h,
          drawW: drawW,
          drawH: drawH,
          yTop: cursorY,
        ));
        cursorY += drawH + defaultLineHeight * 0.5;
      } else {
        final altText = block.alt ?? 'Image';
        addPlainLine('[Image: $altText]', bodySize);
        if (block.src.isNotEmpty && !block.src.startsWith('data:')) {
          addPlainLine('  Source: ${block.src}', bodySize * 0.8);
        }
        addBlankLine();
      }
    }

    // ---- Grid table path: real cell borders, fills, wrapping, header repeat ----

    void renderTable(FormTableBlock block) {
      final cols = block.columns;
      if (cols.isEmpty) {
        addBlankLine();
        return;
      }
      final tableStruct = activeStruct; // the Table element
      // The table's own style may override grid colour (border) and header
      // fill (background).
      final rs = resolveStyle(
        blockStyle: block.style,
        layout: layout,
        sheet: sheet,
        defaultSizePt: bodySize,
      );
      final grid = hexToRgb(rs.border?.color ?? '#888888') ??
          (r: 0.53, g: 0.53, b: 0.53);
      final gridW = rs.border?.width ?? 0.5;
      final headerFill = hexToRgb(rs.backgroundHex ?? '#EEEEEE');
      const cellPad = 3.0;

      // Optional fixed body-row height (opt-in). Without it rows grow to fit
      // (the default). With it, [rs.overflow] decides cell behaviour:
      //   grow/split → rowHeight is a MINIMUM (short rows pad, long rows still
      //                grow — never clips); shrinkToFit → hard height, font
      //                shrinks to fit; clip → hard height, overflow dropped.
      final rowHeightPt = (block.style?['rowHeight'] as num?)?.toDouble();
      // Opt-in rich cell content (default plain so `*`/`<` stay literal).
      final cellFormat = block.style?['cellFormat'] as String? ?? 'plain';
      final cellOverflow = rs.overflow;
      final fixedRow = rowHeightPt != null &&
          cellOverflow != BlockOverflow.grow &&
          cellOverflow != BlockOverflow.split;
      final innerFixedH = fixedRow ? rowHeightPt - 2 * cellPad : null;

      // Column widths: explicit weights or equal share of the content width.
      final weights = [for (final c in cols) (c.width ?? 1.0)];
      final wsum = weights.fold<double>(0, (a, b) => a + b);
      final colW = [for (final w in weights) contentWidthPt * w / wsum];
      final colX = <double>[];
      var ax = marginLeft;
      for (final w in colW) {
        colX.add(ax);
        ax += w;
      }

      // Lines for a cell. A fixed-height body cell is copy-fit (shrink / clip)
      // into [innerFixedH]; otherwise it wraps naturally.
      List<TextLine> cellLines(
          String text, double size, bool bold, int i, bool fit) {
        final base = TextRunStyle(fontSize: size, bold: bold ? true : null);
        // Header cells stay plain; body cells honour the table's cellFormat.
        final rich = _shapeRich(bold
            ? FormRichText.plain(text)
            : FormRichText.parse(text, format: cellFormat));
        if (fit && innerFixedH != null) {
          return fitText(
            rich,
            colW[i] - 2 * cellPad,
            base,
            maxHeightPt: innerFixedH,
            minSize: minSize,
            overflow: cellOverflow,
            metrics: metrics,
          ).lines;
        }
        return wrapRichText(rich, colW[i] - 2 * cellPad, base, metrics: metrics);
      }

      double naturalRowH(List<String> cells, double size, bool bold) {
        var maxLines = 1;
        for (var i = 0; i < cols.length; i++) {
          final n = cellLines(cells[i], size, bold, i, false).length;
          if (n > maxLines) maxLines = n;
        }
        return maxLines * size * 1.4 + 2 * cellPad;
      }

      // Row height for a body row given the overflow policy.
      double bodyRowH(List<String> cells) {
        if (rowHeightPt == null) return naturalRowH(cells, bodySize, false);
        if (fixedRow) return rowHeightPt;
        final natural = naturalRowH(cells, bodySize, false);
        return natural > rowHeightPt ? natural : rowHeightPt; // minimum height
      }

      void placeRow(
          List<String> cells, double size, bool bold, bool header, double h) {
        final rowTop = cursorY;
        final fit = !header && fixedRow;
        final trStruct = (tagged && tableStruct != null)
            ? newStruct('TR', parent: tableStruct)
            : null;
        for (var i = 0; i < cols.length; i++) {
          if (trStruct != null) {
            activeStruct = newStruct(header ? 'TH' : 'TD', parent: trStruct);
          }
          emit(_PdfBox(
            xLeft: colX[i],
            width: colW[i],
            yTop: rowTop,
            height: h,
            fill: header ? headerFill : null,
            stroke: grid,
            strokeWidth: gridW,
            topOpen: false,
            bottomOpen: false,
          ));
          final align =
              FormTextAlign.fromString(cols[i].alignment) ?? FormTextAlign.left;
          var ly = rowTop + cellPad;
          final cellRtl = baseIsRtl(cells[i]);
          for (final line in cellLines(cells[i], size, bold, i, fit)) {
            final pl = _pdfLineFrom(
                line, colX[i] + cellPad, colW[i] - 2 * cellPad, align, null,
                metrics: metrics, isLast: true, baseRtl: cellRtl);
            pl.yTop = ly;
            emit(pl);
            ly += line.maxSize * 1.4;
          }
        }
        if (trStruct != null) activeStruct = tableStruct;
        cursorY += h;
      }

      final headers = [for (final c in cols) c.title];
      final headerH = naturalRowH(headers, bodySize, true);
      ensureSpace(headerH);
      placeRow(headers, bodySize, true, true, headerH);
      for (final row in block.rows) {
        final cells = [
          for (final col in cols) (row.cells[col.id]?.toString() ?? '')
        ];
        final h = bodyRowH(cells);
        // Break before a row that won't fit, repeating the header overleaf.
        if (cursorY + h > flowHeight && currentPage.isNotEmpty) {
          breakPage();
          placeRow(headers, bodySize, true, true, headerH);
        }
        placeRow(cells, bodySize, false, false, h);
      }
      addBlankLine();
    }

    // ---- Block dispatch ----

    // Map a block to its tagged-PDF structure type (null = no own element;
    // repeatable / conditional pass through to their children).
    String? tagForBlock(FormBlock b) {
      return switch (b) {
        FormHeadingBlock() => 'H${b.level.clamp(1, 6)}',
        FormTextBlock() =>
          isListStyle(b.style?['listStyle'] as String?) ? 'L' : 'P',
        FormTableBlock() => 'Table',
        FormImageBlock() => 'Figure',
        FormChartBlock() => 'Figure',
        FormCanvasBlock() => 'Figure',
        FormFieldBlock() => 'P',
        _ => null,
      };
    }

    void renderBlock(FormBlock block, Map<String, dynamic> data) {
      final savedStruct = activeStruct;
      if (tagged) {
        final t = tagForBlock(block);
        if (t != null) activeStruct = newStruct(t);
      }
      switch (block) {
        case FormTextBlock():
          if (block.style?['math'] == true) {
            renderMath(block.content);
          } else if (block.style?['toc'] == true) {
            renderToc(block);
          } else if (isListStyle(block.style?['listStyle'] as String?)) {
            renderList(block);
          } else {
            renderTextual(
              FormRichText.parse(
                substituteInlineMath(
                    footnotes.consume(applyCrossRefs(block.content, numbering))),
                format: block.format,
              ),
              applyRedlineStyle(block.style),
            );
          }

        case FormHeadingBlock():
          final level = block.level.clamp(1, 6);
          final number = numbering.headingNumber(block.blockId);
          final text = footnotes.consume(applyCrossRefs(block.content, numbering));
          // A non-breaking double space keeps the number with its title.
          final headingText = number != null ? '$number  $text' : text;
          // Pin the heading to the page its first line lands on so a TOC entry
          // can resolve the page number.
          ensureSpace(fontPolicy.headingSizeForLevel(level) * 1.4);
          headingPageRef[block.blockId] = currentPage;
          renderTextual(
            FormRichText.parse(headingText, format: 'plain'),
            applyRedlineStyle(block.style),
            heading: true,
            headingLevel: level,
          );

        case FormTableBlock():
          renderTable(block);
          renderCaption(block);

        case FormImageBlock():
          if (tagged && activeStruct != null) {
            structAlt[activeStruct!] = block.alt ??
                block.style?['caption'] as String? ??
                block.src;
          }
          renderImage(block);
          renderCaption(block);

        case FormChartBlock():
          if (tagged && activeStruct != null) {
            structAlt[activeStruct!] = block.title ??
                block.style?['caption'] as String? ??
                '${block.chartType} chart';
          }
          final chartW = contentWidthPt;
          final styleH = (block.style?['height'] as num?)?.toDouble();
          final chartH = styleH ?? math.min(chartW * 0.55, 220.0);
          ensureSpace(chartH + bodySize);
          final geo = buildChartGeometry(block,
              width: chartW, height: chartH, metrics: metrics);
          emit(_PdfChart(geometry: geo, yTop: cursorY));
          cursorY += chartH + bodySize * 0.6;
          renderCaption(block);

        case FormCanvasBlock():
          final label = block.caption ?? block.alt ?? block.target;
          addPlainLine('[Canvas: $label]', bodySize);
          if (block.target.isNotEmpty) {
            addPlainLine('  Target: ${block.target}', bodySize * 0.8);
          }
          addBlankLine();

        case FormFieldBlock():
          final value = data[block.fieldName];
          if (context.options.fillableFields) {
            // Interactive field: a label line then a bordered input box the
            // AcroForm widget sits over.
            addPlainLine('${block.fieldName}:', bodySize);
            final boxH = bodySize * 1.6;
            ensureSpace(boxH);
            emit(_PdfBox(
              xLeft: marginLeft,
              width: contentWidthPt,
              yTop: cursorY,
              height: boxH,
              fill: null,
              stroke: (r: 0.6, g: 0.6, b: 0.6),
              strokeWidth: 0.5,
              topOpen: false,
              bottomOpen: false,
            ));
            formFieldWidgets.add((
              page: currentPage,
              xLeft: marginLeft,
              yTop: cursorY,
              width: contentWidthPt,
              height: boxH,
              name: block.fieldName,
              value: value?.toString() ?? '',
            ));
            cursorY += boxH + defaultLineHeight * 0.5;
          } else {
            final display = value != null ? value.toString() : '(unfilled)';
            renderTextual(
              FormRichText.plain('${block.fieldName}: $display'),
              block.style,
            );
          }

        case FormRepeatableBlock():
          for (final item in resolveRepeatableItems(block, data)) {
            for (final tplBlock in block.itemTemplate) {
              renderBlock(tplBlock, item);
            }
          }

        case FormConditionalBlock():
          if (evaluateCondition(block.condition, data)) {
            renderBlock(block.thenBlock, data);
          } else if (block.elseBlock != null) {
            renderBlock(block.elseBlock!, data);
          }

        default:
          break;
      }
      activeStruct = savedStruct;
    }

    // Per-block grid placement (mcp_form render-time, no core field). A block's
    // style may carry `colSpan` (1..12) over a 12-column grid. Consecutive blocks
    // whose spans fit within 12 are laid side by side on one row; a span of 12
    // (or unset) is a full-width block on its own row. Empty trailing columns are
    // left as whitespace, matching the conventional CSS/DOCX grid.
    int colSpanOf(FormBlock b) {
      final v = b.style?['colSpan'];
      return v is num ? v.toInt().clamp(1, 12) : 12;
    }

    // Lay a row of side-by-side cells. Each cell is rendered into its own band
    // (left edge + width derived from its span), all starting at the same y; the
    // cursor then advances to the tallest cell. A cell that page-breaks flows
    // naturally — multi-cell rows are intended for content that fits a page.
    void renderRow(List<FormBlock> cells) {
      if (cells.length == 1) {
        renderBlock(cells.first, doc.data);
        return;
      }
      final savedMarginLeft = marginLeft;
      final savedContentWidth = contentWidthPt;
      final gap = columnGap;
      final rowTotal = savedContentWidth;
      final usable = rowTotal - (cells.length - 1) * gap;
      final rowStartY = cursorY;
      var maxY = cursorY;
      var x = savedMarginLeft;
      for (final cell in cells) {
        final w = usable * colSpanOf(cell) / 12;
        marginLeft = x;
        contentWidthPt = w;
        cursorY = rowStartY;
        renderBlock(cell, doc.data);
        if (cursorY > maxY) maxY = cursorY;
        x += w + gap;
      }
      marginLeft = savedMarginLeft;
      contentWidthPt = savedContentWidth;
      cursorY = maxY;
    }

    // Letterhead logo from the theme, drawn at the very top of the document.
    final logoSrc = sheet?.theme.logo;
    if (logoSrc != null && logoSrc.isNotEmpty) {
      final im = _decodeImage(logoSrc);
      if (im != null) {
        final w = math.min(sheet!.theme.logoWidth ?? 120.0, fullContentWidthPt);
        final h = w * (im.h / im.w);
        ensureSpace(h);
        emit(_PdfImage(
          bytes: im.bytes,
          dctDecode: im.dct,
          pxW: im.w,
          pxH: im.h,
          drawW: w,
          drawH: h,
          yTop: cursorY,
        ));
        cursorY += h + defaultLineHeight * 0.5;
      }
    }

    // `style.placement` blocks (a seal image, a footer company name, …) are
    // pulled out of the flow and drawn at absolute page coordinates after all
    // pages are laid out (see below). Image + text are placed; other block
    // types with placement fall through and render in flow.
    final placedBlocks = <FormBlock>[];
    for (final section in doc.sections) {
      if (section.title != null) {
        if (tagged) activeStruct = newStruct('H2');
        addWrappedPlain(
          section.title!,
          fontPolicy.headingSizeForLevel(2),
          bold: true,
        );
        activeStruct = null;
        addBlankLine();
      }
      final blocks = section.blocks.where((b) {
        if ((b is FormImageBlock || b is FormTextBlock) &&
            b.style?['placement'] != null) {
          placedBlocks.add(b);
          return false; // excluded from flow, drawn absolutely later
        }
        return true;
      }).toList();
      var i = 0;
      while (i < blocks.length) {
        // `style.pageBreak: before` starts a fresh page before this block
        // (paged mode only) — the primitive for report structure: a cover
        // page, then a TOC page, then the body, then a back page.
        if (!continuous && blocks[i].style?['pageBreak'] == 'before') {
          forcePageBreak();
        }
        final span = colSpanOf(blocks[i]);
        if (span >= 12) {
          renderBlock(blocks[i], doc.data);
          if (!continuous && blocks[i].style?['pageBreak'] == 'after') {
            forcePageBreak();
          }
          i++;
          continue;
        }
        final row = <FormBlock>[blocks[i]];
        var acc = span;
        var j = i + 1;
        while (j < blocks.length) {
          final s = colSpanOf(blocks[j]);
          if (s >= 12 || acc + s > 12) break;
          row.add(blocks[j]);
          acc += s;
          j++;
        }
        renderRow(row);
        if (!continuous && row.last.style?['pageBreak'] == 'after') {
          forcePageBreak();
        }
        i = j;
      }
    }

    // Endnotes: the collected footnotes as a numbered "Notes" section.
    if (!footnotes.isEmpty) {
      addBlankLine();
      addWrappedPlain('Notes', fontPolicy.headingSizeForLevel(2), bold: true);
      addBlankLine();
      final notes = footnotes.notes;
      for (var i = 0; i < notes.length; i++) {
        addWrappedPlain('${i + 1}. ${notes[i]}', bodySize * 0.9);
      }
    }

    // Close any box still open at document end.
    if (activeBox != null) {
      emitBoxFragment(activeBox!, cursorY, false);
      activeBox = null;
    }
    if (currentPage.isNotEmpty) pages.add(currentPage);
    if (pages.isEmpty) pages.add(<Object>[]);

    // Now that every page is final, fill each reserved TOC slot with the
    // resolved page number, right-aligned on its entry line.
    for (final slot in tocPageSlots) {
      final ref = headingPageRef[slot.blockId];
      if (ref == null) continue;
      final pageNum = pages.indexOf(ref) + 1;
      if (pageNum <= 0) continue;
      final label = '$pageNum';
      final w = measureText(label, slot.size, metrics: metrics);
      slot.page.add(_PdfTextLine(
        segments: [
          _PdfSeg(text: label, x: slot.rightX - w, size: slot.size),
        ],
        yTop: slot.yTop,
        maxSize: slot.size,
      ));
    }

    // In continuous mode the single page grows to fit all content.
    final outPageHeightPt =
        continuous ? (cursorY + marginTop + marginBottom) : pageHeightPt;

    // Absolute-placement blocks: draw at page coordinates measured from the
    // paper corner (margins ignored), overlaid on top of the flow. Default is
    // the last page; `placement.repeat: true` repeats on every page. Emitted
    // as artifacts (structId left null) — page furniture, not document content.
    // Compute the (left x, bottom y) page anchor for a box of [w]×[h] given a
    // placement spec. Coordinates are from the paper edges, margins ignored.
    ({double x, double yBottom}) placeBox(
        Map<String, dynamic> pl, double w, double h) {
      final anchor = pl['anchor'] as String? ?? 'bottom-right';
      final xPt = ((pl['x'] as num?)?.toDouble() ?? 0) * _mmToPt;
      final yPt = ((pl['y'] as num?)?.toDouble() ?? 0) * _mmToPt;
      return switch (anchor) {
        'top-left' => (x: xPt, yBottom: outPageHeightPt - yPt - h),
        'top-right' =>
          (x: pageWidthPt - xPt - w, yBottom: outPageHeightPt - yPt - h),
        'top-center' =>
          (x: (pageWidthPt - w) / 2 + xPt, yBottom: outPageHeightPt - yPt - h),
        'bottom-left' => (x: xPt, yBottom: yPt),
        'bottom-center' => (x: (pageWidthPt - w) / 2 + xPt, yBottom: yPt),
        'center' => (
            x: (pageWidthPt - w) / 2 + xPt,
            yBottom: (outPageHeightPt - h) / 2 - yPt
          ),
        _ => (x: pageWidthPt - xPt - w, yBottom: yPt), // bottom-right
      };
    }

    for (final block in placedBlocks) {
      final pl = (block.style!['placement'] as Map).cast<String, dynamic>();
      final repeat = pl['repeat'] == true;
      // z: 'back' draws behind the flow (a background); default is in front.
      final back = (pl['z'] as String?) == 'back';
      final items = <Object>[];

      double sizePt(Object? spec, double full) => spec == 'full'
          ? full
          : (spec is num ? spec.toDouble() * _mmToPt : double.nan);

      if (block is FormImageBlock) {
        final im = _decodeImage(block.src);
        if (im == null) continue;
        final fit = (pl['fit'] as String?) ?? block.style?['fit'] as String?;
        final imgRatio = block.aspectRatio ?? (im.h / im.w); // h / w
        // Target box: `full` = whole page (full-bleed), a number = mm, absent
        // falls back to maxWidth / a default with the natural ratio.
        var boxW = sizePt(pl['width'], pageWidthPt);
        var boxH = sizePt(pl['height'], outPageHeightPt);
        double drawW;
        double drawH;
        if (fit != null && !boxW.isNaN && !boxH.isNaN) {
          // Cover fills the box (may overflow → clipped by the page); contain
          // fits inside. Scale in pt-per-natural-unit using the aspect ratio.
          final boxRatio = boxH / boxW;
          final cover = fit == 'cover';
          if ((imgRatio > boxRatio) == cover) {
            drawW = boxW;
            drawH = boxW * imgRatio;
          } else {
            drawH = boxH;
            drawW = boxH / imgRatio;
          }
        } else {
          drawW = !boxW.isNaN
              ? boxW
              : (block.maxWidth != null
                  ? block.maxWidth!.toDouble() * 0.75
                  : 60.0);
          drawH = drawW * imgRatio;
          boxW = drawW;
          boxH = drawH;
        }
        // Anchor the box, then centre the (possibly larger) image within it.
        final at = placeBox(pl, boxW, boxH);
        items.add(_PdfImage(
          bytes: im.bytes,
          dctDecode: im.dct,
          pxW: im.w,
          pxH: im.h,
          drawW: drawW,
          drawH: drawH,
          yTop: 0,
          absX: at.x + (boxW - drawW) / 2,
          absYBottom: at.yBottom + (boxH - drawH) / 2,
        ));
      } else if (block is FormTextBlock) {
        // Absolute text: place each line via a computed yTop so the existing
        // text writer lands it at the anchor baseline (no writer change).
        final lines = block.content
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .toList();
        if (lines.isEmpty) continue;
        final lh = bodySize * 1.3;
        final blockH = lh * lines.length;
        for (var li = 0; li < lines.length; li++) {
          final text = lines[li];
          final w = measureText(text, bodySize, metrics: metrics);
          final at = placeBox(pl, w, blockH);
          // Top line sits at the box top; subsequent lines step down by lh.
          final baseline = at.yBottom + blockH - bodySize - li * lh;
          final yTop = outPageHeightPt - marginTop - baseline - bodySize;
          items.add(_PdfTextLine(
            segments: [_PdfSeg(text: text, x: at.x, size: bodySize)],
            yTop: yTop,
            maxSize: bodySize,
          ));
        }
      } else {
        continue;
      }

      final targets = repeat ? pages : <List<Object>>[pages.last];
      for (final p in targets) {
        if (back) {
          p.insertAll(0, items); // drawn first = behind the flow
        } else {
          p.addAll(items);
        }
      }
    }

    return _assemble(
      pages: pages,
      context: context,
      embedded: embedded,
      metrics: metrics,
      pageWidthPt: pageWidthPt,
      pageHeightPt: outPageHeightPt,
      marginTop: marginTop,
      marginBottom: marginBottom,
      marginLeft: baseMarginLeft,
      contentWidthPt: fullContentWidthPt,
      formFieldWidgets: formFieldWidgets,
      structTags: structTags,
      structParents: structParents,
      structAlt: structAlt,
    );
  }

  /// Build a positioned text line from a measured [TextLine], resolving colours
  /// and decorations. [rs] is null for plain (table / section) lines.
  _PdfTextLine _pdfLineFrom(
    TextLine line,
    double leftX,
    double availWidth,
    FormTextAlign align,
    ResolvedStyle? rs, {
    FontMetrics metrics = defaultMetrics,
    bool isLast = false,
    bool? baseRtl,
  }) {
    var startX = leftX;
    if (align == FormTextAlign.right) {
      startX = leftX + (availWidth - line.width);
    } else if (align == FormTextAlign.center) {
      startX = leftX + (availWidth - line.width) / 2;
    }

    // Build a positioned segment from a measured run [s], drawing [text] of
    // width [w] at [x] (text/width differ from s under bidi regrouping).
    _PdfSeg make(LineSegment s, String text, double x, double w) {
      final style = s.style;
      final colorRaw = style.color;
      final color = hexToRgb(
          colorRaw == null ? null : (rs?.resolveColor(colorRaw) ?? colorRaw));
      final hlRaw = style.highlight;
      final highlight = hexToRgb(
          hlRaw == null ? null : (rs?.resolveColor(hlRaw) ?? hlRaw));
      var shift = 0.0;
      if (style.baseline == RunBaseline.superscript) shift = s.size * 0.33;
      if (style.baseline == RunBaseline.subscript) shift = -s.size * 0.20;
      return _PdfSeg(
        text: text,
        x: x,
        size: s.size,
        bold: style.bold == true,
        italic: style.italic == true,
        color: color,
        underline: style.underline == true,
        strike: style.strike == true,
        highlight: highlight,
        baselineShift: shift,
        width: w,
        link: style.link,
      );
    }

    // Bidi: when the line has any right-to-left text, reorder characters into
    // visual (left-to-right display) order, then regroup contiguous same-run
    // characters into positioned segments. LTR-only lines skip this entirely.
    final plain = line.segments.map((s) => s.text).join();
    if (hasRtl(plain)) {
      final cps = <int>[];
      final owner = <LineSegment>[];
      final cw = <double>[];
      for (final s in line.segments) {
        for (final cp in s.text.runes) {
          cps.add(cp);
          owner.add(s);
          cw.add(measureText(String.fromCharCode(cp), s.size,
              bold: s.style.bold == true, metrics: metrics));
        }
      }
      final levels = resolveBidi(String.fromCharCodes(cps), baseRtl: baseRtl).levels;
      final order = reorderVisual(levels, cps.length);
      final segs = <_PdfSeg>[];
      var x = startX;
      var k = 0;
      while (k < order.length) {
        final s = owner[order[k]];
        final buf = StringBuffer();
        var w = 0.0;
        while (k < order.length && identical(owner[order[k]], s)) {
          final ci = order[k];
          // L4: mirror brackets / angle quotes drawn at a right-to-left level.
          buf.writeCharCode(
              levels[ci].isOdd ? mirrorGlyph(cps[ci]) : cps[ci]);
          w += cw[ci];
          k++;
        }
        segs.add(make(s, buf.toString(), x, w));
        x += w;
      }
      return _PdfTextLine(segments: segs, yTop: 0, maxSize: line.maxSize);
    }

    final segs = <_PdfSeg>[];
    var x = startX;
    for (final s in line.segments) {
      segs.add(make(s, s.text, x, s.width));
      x += s.width;
    }

    // Justify: distribute slack across inter-word spaces (never the last line).
    if (align == FormTextAlign.justify && !isLast) {
      final extra = availWidth - line.width;
      var gaps = 0;
      for (final s in segs) {
        gaps += ' '.allMatches(s.text).length;
      }
      if (gaps > 0 && extra > 0.3) {
        final per = extra / gaps;
        final out = <_PdfSeg>[];
        var jx = leftX;
        for (final s in segs) {
          final parts = s.text.split(' ');
          for (var i = 0; i < parts.length; i++) {
            if (i > 0) {
              jx += measureText(' ', s.size, bold: s.bold, metrics: metrics) +
                  per;
            }
            if (parts[i].isEmpty) continue;
            final pw =
                measureText(parts[i], s.size, bold: s.bold, metrics: metrics);
            out.add(s.copyWith(text: parts[i], x: jx, width: pw));
            jx += pw;
          }
        }
        return _PdfTextLine(segments: out, yTop: 0, maxSize: line.maxSize);
      }
    }

    // [yTop] is set by the caller to the current cursor offset before adding.
    return _PdfTextLine(segments: segs, yTop: 0, maxSize: line.maxSize);
  }

  Future<FormRenderOutput> _assemble({
    required List<List<Object>> pages,
    required RenderContext context,
    required TrueTypeFont? embedded,
    required FontMetrics metrics,
    required double pageWidthPt,
    required double pageHeightPt,
    required double marginTop,
    required double marginBottom,
    required double marginLeft,
    required double contentWidthPt,
    List<
            ({
              List<Object> page,
              double xLeft,
              double yTop,
              double width,
              double height,
              String name,
              String value
            })>
        formFieldWidgets = const [],
    List<String> structTags = const [],
    List<int> structParents = const [],
    Map<int, String> structAlt = const {},
  }) async {
    final doc = context.document;
    final opts = context.options;
    final taggedOut = context.options.taggedPdf && structTags.isNotEmpty;
    final pageCount = pages.length;
    final type0 = embedded != null;
    const fontName = 'MMEmbedded';

    final objects = <int, String>{};
    final binaryObjects = <int, List<int>>{};
    var nextObjId = 1;
    int allocObj() => nextObjId++;

    // Store a stream object, FlateDecode-compressed where the platform allows
    // (native) and the caller asked; embedded whole otherwise (web).
    void putStream(int id, String dictExtra, List<int> raw) {
      final comp = opts.compress ? deflate(raw) : null;
      final body = comp ?? raw;
      final filter = comp != null ? ' /Filter /FlateDecode' : '';
      final header = '<<$dictExtra$filter /Length ${body.length}>>\nstream\n';
      binaryObjects[id] = <int>[
        ...utf8.encode(header),
        ...body,
        ...utf8.encode('\nendstream'),
      ];
    }

    final catalogId = allocObj();
    final pagesObjId = allocObj();

    // Shared ExtGState for watermark opacity, allocated only when needed.
    final wmOn = context.effectiveWatermark != null;
    final extGStateId = wmOn ? allocObj() : 0;

    // The embedded font family for Type0 output: primary first, then fallbacks.
    final fonts = type0
        ? <TrueTypeFont>[embedded, ...context.fallbackFonts]
        : const <TrueTypeFont>[];

    // Font object ids — Helvetica family, or one Type0 set per embedded font.
    var fontRegularId = 0, fontBoldId = 0, fontItalicId = 0, fontBoldItalicId = 0;
    final fontType0Ids = <int>[];
    final cidFontIds = <int>[];
    final descriptorIds = <int>[];
    final fontFileIds = <int>[];
    final toUnicodeIds = <int>[];
    if (type0) {
      for (var i = 0; i < fonts.length; i++) {
        fontType0Ids.add(allocObj());
        cidFontIds.add(allocObj());
        descriptorIds.add(allocObj());
        fontFileIds.add(allocObj());
        toUnicodeIds.add(allocObj());
      }
    } else {
      fontRegularId = allocObj();
      fontBoldId = allocObj();
      fontItalicId = allocObj();
      fontBoldItalicId = allocObj();
    }

    final pageObjIds = <int>[];
    final contentObjIds = <int>[];
    for (var i = 0; i < pageCount; i++) {
      pageObjIds.add(allocObj());
      contentObjIds.add(allocObj());
    }
    final infoId = allocObj();

    // Tagged-PDF structure object ids (allocated up front; filled after the
    // page loop resolves MCIDs).
    final structTreeRootId = taggedOut ? allocObj() : 0;
    final documentElemId = taggedOut ? allocObj() : 0;
    final parentTreeId = taggedOut ? allocObj() : 0;
    final structElemIds =
        taggedOut ? [for (var i = 0; i < structTags.length; i++) allocObj()] : <int>[];

    // AcroForm field widgets: one object per field, grouped by page index.
    final fieldWidgetIds = <int, List<int>>{}; // page index -> widget obj ids
    final allFieldIds = <int>[];
    final fieldRecords = <int, (String name, String value, double x, double y,
        double w, double h)>{};
    for (final f in formFieldWidgets) {
      final pi = pages.indexOf(f.page);
      if (pi < 0) continue;
      final id = allocObj();
      allFieldIds.add(id);
      (fieldWidgetIds[pi] ??= []).add(id);
      fieldRecords[id] = (f.name, f.value, f.xLeft, f.yTop, f.width, f.height);
    }
    final acroFormId = allFieldIds.isEmpty ? 0 : allocObj();
    // PDF/A metadata (XMP) object.
    final metadataId = (context.options.pdfA || taggedOut) ? allocObj() : 0;

    final catalogParts = <String>['/Type /Catalog', '/Pages $pagesObjId 0 R'];
    if (acroFormId != 0) catalogParts.add('/AcroForm $acroFormId 0 R');
    if (metadataId != 0) catalogParts.add('/Metadata $metadataId 0 R');
    if (metadataId != 0 || taggedOut) {
      catalogParts.add('/MarkInfo <</Marked true>>');
    }
    if (taggedOut) {
      catalogParts.add('/StructTreeRoot $structTreeRootId 0 R');
      catalogParts.add('/Lang (en-US)');
    }
    objects[catalogId] = '<<${catalogParts.join(' ')}>>';
    final kidsStr = pageObjIds.map((id) => '$id 0 R').join(' ');
    objects[pagesObjId] =
        '<</Type /Pages /Kids [$kidsStr] /Count $pageCount>>';

    // Build the widget + AcroForm objects. Field appearance is left to the
    // viewer (`/NeedAppearances true`).
    if (acroFormId != 0) {
      for (final entry in fieldRecords.entries) {
        final id = entry.key;
        final (name, value, x, yTop, w, h) = entry.value;
        final pi = fieldWidgetIds.entries
            .firstWhere((e) => e.value.contains(id))
            .key;
        final top = pageHeightPt - marginTop - yTop;
        final bottom = top - h;
        objects[id] = '<</Type /Annot /Subtype /Widget /FT /Tx '
            '/T (${_escapePdfString(name)}) /V (${_escapePdfString(value)}) '
            '/Rect [${x.toStringAsFixed(2)} ${bottom.toStringAsFixed(2)} '
            '${(x + w).toStringAsFixed(2)} ${top.toStringAsFixed(2)}] '
            '/F 4 /P ${pageObjIds[pi]} 0 R /DA (/Helv 0 Tf 0 g)>>';
      }
      final fieldsStr = allFieldIds.map((id) => '$id 0 R').join(' ');
      objects[acroFormId] = '<</Fields [$fieldsStr] /NeedAppearances true '
          '/DA (/Helv 0 Tf 0 g)>>';
    }
    if (metadataId != 0) {
      final xmp = _xmpMetadata(context);
      final bytes = utf8.encode(xmp);
      binaryObjects[metadataId] = <int>[
        ...utf8.encode('<</Type /Metadata /Subtype /XML /Length '
            '${bytes.length}>>\nstream\n'),
        ...bytes,
        ...utf8.encode('\nendstream'),
      ];
    }

    final fontResDict = type0
        ? '/Font <<${[
            for (var i = 0; i < fonts.length; i++)
              '/F${i + 1} ${fontType0Ids[i]} 0 R'
          ].join(' ')}>>'
        : '/Font <</F1 $fontRegularId 0 R /F2 $fontBoldId 0 R '
            '/F3 $fontItalicId 0 R /F4 $fontBoldItalicId 0 R>>';
    final extRes = wmOn ? ' /ExtGState <</GSwm $extGStateId 0 R>>' : '';

    // Glyph usage collected while encoding text, for the Type0 W array and
    // ToUnicode map. Unused in Helvetica mode.
    final usedGids = [for (var i = 0; i < fonts.length; i++) <int>{}];
    final gidToUni = [for (var i = 0; i < fonts.length; i++) <int, int>{}];

    // First font that has a glyph for [cp]; primary (0) when none cover it.
    int fontFor(int cp) {
      for (var i = 0; i < fonts.length; i++) {
        final g = fonts[i].gidFor(cp);
        if (g != null && g != 0) return i;
      }
      return 0;
    }

    // Hex GID string for [text] against font [fi], recording glyph usage.
    String encodeWith(int fi, String text) {
      final f = fonts[fi];
      final sb = StringBuffer('<');
      for (final r in text.runes) {
        final gid = f.gidFor(r) ?? 0;
        usedGids[fi].add(gid);
        if (gid != 0) gidToUni[fi][gid] = r;
        sb.write(gid.toRadixString(16).padLeft(4, '0').toUpperCase());
      }
      sb.write('>');
      return sb.toString();
    }

    // Split [text] into (fontIndex, runText) by glyph coverage. A single font
    // (no fallbacks) yields one run, so the output matches the prior path.
    List<(int, String)> splitByFont(String text) {
      if (fonts.length <= 1) return [(0, text)];
      final runs = <(int, String)>[];
      final sb = StringBuffer();
      int? cur;
      for (final r in text.runes) {
        final fi = fontFor(r);
        if (cur != null && fi != cur) {
          runs.add((cur, sb.toString()));
          sb.clear();
        }
        sb.writeCharCode(r);
        cur = fi;
      }
      if (sb.isNotEmpty) runs.add((cur ?? 0, sb.toString()));
      return runs;
    }

    // Legacy single-font encode: Helvetica literals, plus Latin chrome
    // (watermark / running header / chart labels) that uses the primary font.
    String encode(String text) =>
        type0 ? encodeWith(0, text) : '(${_escapePdfString(text)})';

    // Tagged-PDF (PDF/UA) bookkeeping: MCID assignment per page and the
    // struct-element → marked-content references it feeds.
    final structMcrs = <int, List<({int page, int mcid})>>{};
    final pageMcidStruct = List.generate(pageCount, (_) => <int>[]);

    for (var i = 0; i < pageCount; i++) {
      final items = pages[i];
      final streamBuf = StringBuffer();
      final annots = <_LinkAnnot>[];
      var mcid = 0;

      // Optional page frame (official document / certificate border), inset by
      // half its width so the stroke stays inside the media box, drawn on
      // every page.
      if (opts.pageBorder) {
        final w = opts.pageBorderWidth;
        final inset = w / 2 + 2;
        streamBuf.writeln('q');
        streamBuf.writeln('${pdfRgb(hexToRgb(opts.pageBorderColor) ?? (r: 0.0, g: 0.0, b: 0.0))} RG');
        streamBuf.writeln('${w.toStringAsFixed(2)} w');
        streamBuf.writeln('${inset.toStringAsFixed(2)} ${inset.toStringAsFixed(2)} '
            '${(pageWidthPt - 2 * inset).toStringAsFixed(2)} '
            '${(pageHeightPt - 2 * inset).toStringAsFixed(2)} re S');
        streamBuf.writeln('Q');
      }

      // Wrap an item's operators in marked content: a structure element (with an
      // MCID that the struct tree references) or an artifact (skipped by AT).
      void tag(int? structId, void Function() writeOps) {
        if (!taggedOut) {
          writeOps();
          return;
        }
        if (structId != null) {
          streamBuf.writeln('/${structTags[structId]} <</MCID $mcid>> BDC');
          writeOps();
          streamBuf.writeln('EMC');
          (structMcrs[structId] ??= []).add((page: i, mcid: mcid));
          pageMcidStruct[i].add(structId);
          mcid++;
        } else {
          streamBuf.writeln('/Artifact BDC');
          writeOps();
          streamBuf.writeln('EMC');
        }
      }

      if (wmOn) {
        tag(
            null,
            () => _writeWatermark(streamBuf, context.effectiveWatermark!,
                pageWidthPt, pageHeightPt, encode, opts));
      }

      final pageImageRefs = <String, int>{};

      // Pass 1: boxes (behind everything).
      for (final item in items) {
        if (item is _PdfBox) {
          tag(item.structId, () => _writeBox(streamBuf, item, pageHeightPt, marginTop));
        }
      }

      // Pass 2: images and text, in flow order.
      for (final item in items) {
        if (item is _PdfImage) {
          tag(item.structId, () {
            final imK = '/Im${pageImageRefs.length}';
            final xobjId = allocObj();
            final filter = item.dctDecode ? '/Filter /DCTDecode ' : '';
            final dictHeader =
                '<</Type /XObject /Subtype /Image /Width ${item.pxW} '
                '/Height ${item.pxH} /BitsPerComponent 8 /ColorSpace /DeviceRGB '
                '$filter/Length ${item.bytes.length}>>\nstream\n';
            binaryObjects[xobjId] = <int>[
              ...utf8.encode(dictHeader),
              ...item.bytes,
              ...utf8.encode('\nendstream'),
            ];
            pageImageRefs[imK] = xobjId;
            final x = item.absX ?? marginLeft;
            final yBottom = item.absYBottom ??
                (pageHeightPt - marginTop - item.yTop - item.drawH);
            streamBuf.writeln('q');
            streamBuf.writeln(
              '${item.drawW.toStringAsFixed(2)} 0 0 ${item.drawH.toStringAsFixed(2)} '
              '${x.toStringAsFixed(2)} ${yBottom.toStringAsFixed(2)} cm',
            );
            streamBuf.writeln('$imK Do');
            streamBuf.writeln('Q');
          });
        } else if (item is _PdfChart) {
          tag(item.structId,
              () => _writeChart(streamBuf, item, pageHeightPt, marginTop, marginLeft, encode));
        } else if (item is _PdfTextLine) {
          tag(item.structId,
              () => _writeTextLine(streamBuf, item, pageHeightPt, marginTop, type0, fonts.length, encode, encodeWith, splitByFont, metrics, annots));
        }
      }

      // Running header / footer / page number in the page margins (artifact).
      tag(
          null,
          () => _writeRunningText(streamBuf, opts, encode, metrics, type0, i,
              pageCount, pageWidthPt, pageHeightPt, marginTop, marginBottom,
              marginLeft, contentWidthPt));

      putStream(contentObjIds[i], '', utf8.encode(streamBuf.toString()));

      // Link annotations for this page.
      final annotRefs = <int>[];
      for (final a in annots) {
        final id = allocObj();
        objects[id] = '<</Type /Annot /Subtype /Link '
            '/Rect [${a.x1.toStringAsFixed(2)} ${a.y1.toStringAsFixed(2)} '
            '${a.x2.toStringAsFixed(2)} ${a.y2.toStringAsFixed(2)}] '
            '/Border [0 0 0] /A <</S /URI /URI (${_escapePdfString(a.uri)})>>>>';
        annotRefs.add(id);
      }
      // AcroForm field widgets that landed on this page.
      annotRefs.addAll(fieldWidgetIds[i] ?? const []);
      final annotsRes = annotRefs.isEmpty
          ? ''
          : ' /Annots [${annotRefs.map((r) => '$r 0 R').join(' ')}]';

      final xobjRes = pageImageRefs.isEmpty
          ? ''
          : ' /XObject <<${pageImageRefs.entries.map((e) => '${e.key} ${e.value} 0 R').join(' ')}>>';
      final structParents = taggedOut ? ' /StructParents $i /Tabs /S' : '';
      objects[pageObjIds[i]] = '<</Type /Page /Parent $pagesObjId 0 R '
          '/MediaBox [0 0 ${pageWidthPt.toStringAsFixed(2)} ${pageHeightPt.toStringAsFixed(2)}] '
          '/Contents ${contentObjIds[i]} 0 R$annotsRes$structParents '
          '/Resources <<$fontResDict$xobjRes$extRes>>>>';
    }

    // Tagged-PDF structure tree: StructTreeRoot → Document → per-block elements,
    // plus the ParentTree mapping each page's MCIDs back to their elements.
    if (taggedOut) {
      // Children of each struct element (nesting) from the parent list.
      final childrenOf = <int, List<int>>{};
      final topLevel = <int>[];
      for (var s = 0; s < structParents.length; s++) {
        final p = structParents[s];
        if (p < 0) {
          topLevel.add(s);
        } else {
          (childrenOf[p] ??= []).add(s);
        }
      }
      final docKids = topLevel.map((s) => '${structElemIds[s]} 0 R').join(' ');
      objects[documentElemId] = '<</Type /StructElem /S /Document '
          '/P $structTreeRootId 0 R /K [$docKids]>>';
      for (var s = 0; s < structTags.length; s++) {
        final parentRef = structParents[s] < 0
            ? documentElemId
            : structElemIds[structParents[s]];
        final childKids =
            (childrenOf[s] ?? const []).map((c) => '${structElemIds[c]} 0 R');
        final mcrKids = (structMcrs[s] ?? const []).map((m) =>
            '<</Type /MCR /Pg ${pageObjIds[m.page]} 0 R /MCID ${m.mcid}>>');
        final kids = [...childKids, ...mcrKids].join(' ');
        final alt = structAlt[s];
        final altPart =
            alt != null ? ' /Alt (${_escapePdfString(alt)})' : '';
        objects[structElemIds[s]] = '<</Type /StructElem /S /${structTags[s]} '
            '/P $parentRef 0 R$altPart /K [$kids]>>';
      }
      // ParentTree: for each page, an array indexed by MCID → owning element.
      final nums = <String>[];
      for (var p = 0; p < pageCount; p++) {
        final refs = pageMcidStruct[p]
            .map((s) => '${structElemIds[s]} 0 R')
            .join(' ');
        nums.add('$p [$refs]');
      }
      objects[parentTreeId] = '<</Nums [${nums.join(' ')}]>>';
      objects[structTreeRootId] = '<</Type /StructTreeRoot '
          '/K [$documentElemId 0 R] /ParentTree $parentTreeId 0 R>>';
    }

    if (wmOn) {
      final a = opts.watermarkOpacity.clamp(0.0, 1.0);
      objects[extGStateId] =
          '<</Type /ExtGState /ca ${a.toStringAsFixed(3)} /CA ${a.toStringAsFixed(3)}>>';
    }

    // Build the font objects now that glyph usage is known — one Type0 set per
    // embedded font, each carrying only the glyphs actually drawn from it.
    if (type0) {
      for (var i = 0; i < fonts.length; i++) {
        final f = fonts[i];
        final name = '$fontName$i';
        // Embed only the glyphs actually drawn, renumbered to a compact subset —
        // a full CJK face is many MB. CIDs stay the original glyph ids; the
        // CIDToGIDMap remaps them onto the subset program.
        final sub = subsetTrueTypeFont(f.bytes, usedGids[i]);
        putStream(
            fontFileIds[i], '/Length1 ${sub.fontBytes.length}', sub.fontBytes);
        objects[descriptorIds[i]] =
            '<</Type /FontDescriptor /FontName /$name '
            '/Flags 4 /FontBBox [${f.bboxXMin} ${f.bboxYMin} '
            '${f.bboxXMax} ${f.bboxYMax}] /ItalicAngle 0 '
            '/Ascent ${f.ascent} /Descent ${f.descent} '
            '/CapHeight ${f.ascent} /StemV 80 '
            '/FontFile2 ${fontFileIds[i]} 0 R>>';
        final gids = usedGids[i].where((g) => g != 0).toList()..sort();
        final wBuf = StringBuffer();
        for (final g in gids) {
          wBuf.write('$g [${f.advanceWidth1000(g)}] ');
        }
        final String cidToGid;
        if (sub.cidToGidMap.isEmpty) {
          cidToGid = '/CIDToGIDMap /Identity';
        } else {
          final mapId = allocObj();
          putStream(mapId, '', sub.cidToGidMap);
          cidToGid = '/CIDToGIDMap $mapId 0 R';
        }
        objects[cidFontIds[i]] =
            '<</Type /Font /Subtype /CIDFontType2 /BaseFont /$name '
            '/CIDSystemInfo <</Registry (Adobe) /Ordering (Identity) /Supplement 0>> '
            '/FontDescriptor ${descriptorIds[i]} 0 R $cidToGid /DW 1000 '
            '/W [${wBuf.toString().trim()}]>>';
        putStream(toUnicodeIds[i], '', utf8.encode(_buildToUnicode(gidToUni[i])));
        objects[fontType0Ids[i]] =
            '<</Type /Font /Subtype /Type0 /BaseFont /$name '
            '/Encoding /Identity-H /DescendantFonts [${cidFontIds[i]} 0 R] '
            '/ToUnicode ${toUnicodeIds[i]} 0 R>>';
      }
    } else {
      objects[fontRegularId] =
          '<</Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding>>';
      objects[fontBoldId] =
          '<</Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding>>';
      objects[fontItalicId] =
          '<</Type /Font /Subtype /Type1 /BaseFont /Helvetica-Oblique /Encoding /WinAnsiEncoding>>';
      objects[fontBoldItalicId] =
          '<</Type /Font /Subtype /Type1 /BaseFont /Helvetica-BoldOblique /Encoding /WinAnsiEncoding>>';
    }

    final timestamp = doc.metadata.modifiedAt ?? doc.metadata.createdAt;
    final pdfDate = _formatPdfDate(timestamp);
    final infoParts = <String>[
      '/CreationDate ($pdfDate)',
      '/ModDate ($pdfDate)',
    ];
    if (context.options.includeMetadata) {
      infoParts.add('/Author (${_escapePdfString(doc.metadata.author)})');
      infoParts.add('/Subject (${_escapePdfString(doc.templateId)})');
      infoParts.add('/Title (${_escapePdfString(context.template.name)})');
    }
    objects[infoId] = '<<${infoParts.join(' ')}>>';

    final out = BytesBuilder();
    void w(String s) => out.add(utf8.encode(s));

    w('%PDF-1.4\n');
    final offsets = <int, int>{};
    final totalObjects = nextObjId - 1;
    for (var id = 1; id <= totalObjects; id++) {
      offsets[id] = out.length;
      w('$id 0 obj\n');
      if (binaryObjects.containsKey(id)) {
        out.add(binaryObjects[id]!);
        w('\n');
      } else {
        w('${objects[id]!}\n');
      }
      w('endobj\n');
    }

    final xrefOffset = out.length;
    w('xref\n');
    w('0 ${totalObjects + 1}\n');
    w('0000000000 65535 f \n');
    for (var id = 1; id <= totalObjects; id++) {
      w('${offsets[id]!.toString().padLeft(10, '0')} 00000 n \n');
    }
    w('trailer\n');
    final idPart = context.options.pdfA
        ? ' /ID [<${_docId(context)}> <${_docId(context)}>]'
        : '';
    w('<</Size ${totalObjects + 1} /Root $catalogId 0 R '
        '/Info $infoId 0 R$idPart>>\n');
    w('startxref\n');
    w('$xrefOffset\n');
    w('%%EOF\n');

    final bytes = out.toBytes();
    return FormRenderOutput(
      format: 'pdf',
      content: bytes,
      pageCount: pageCount,
      fileSize: bytes.length,
      generatedAt: timestamp,
    );
  }

  void _writeWatermark(
    StringBuffer buf,
    String text,
    double pageWidthPt,
    double pageHeightPt,
    String Function(String) encode,
    RenderOptions opts,
  ) {
    final color = hexToRgb(opts.watermarkColor) ?? (r: 0.85, g: 0.85, b: 0.85);
    final size = opts.watermarkFontSize;
    final rad = opts.watermarkAngle * math.pi / 180.0;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    buf.writeln('q');
    buf.writeln('/GSwm gs'); // opacity
    buf.writeln('${pdfRgb(color)} rg');
    final cx = pageWidthPt / 2;
    final cy = pageHeightPt / 2;
    buf.writeln('${cosA.toStringAsFixed(4)} ${sinA.toStringAsFixed(4)} '
        '${(-sinA).toStringAsFixed(4)} ${cosA.toStringAsFixed(4)} '
        '${cx.toStringAsFixed(2)} ${cy.toStringAsFixed(2)} cm');
    buf.writeln('BT');
    buf.writeln('/F1 ${size.toStringAsFixed(1)} Tf');
    final wmWidth = text.length * size * 0.5;
    buf.writeln('${(-wmWidth / 2).toStringAsFixed(2)} 0 Td');
    buf.writeln('${encode(text)} Tj');
    buf.writeln('ET');
    buf.writeln('Q');
  }

  /// Draw the running header, footer and page number in the page margins.
  void _writeRunningText(
    StringBuffer buf,
    RenderOptions opts,
    String Function(String) encode,
    FontMetrics metrics,
    bool type0,
    int pageIndex,
    int pageCount,
    double pageWidthPt,
    double pageHeightPt,
    double marginTop,
    double marginBottom,
    double marginLeft,
    double contentWidthPt,
  ) {
    const size = 9.0;
    void draw(String text, double y, _RunAlign align) {
      if (text.isEmpty) return;
      final w = measureText(text, size, metrics: metrics);
      var x = marginLeft;
      if (align == _RunAlign.center) {
        x = marginLeft + (contentWidthPt - w) / 2;
      } else if (align == _RunAlign.right) {
        x = marginLeft + contentWidthPt - w;
      }
      buf.writeln('q');
      buf.writeln('0.4 0.4 0.4 rg');
      buf.writeln('BT');
      buf.writeln('/F1 ${size.toStringAsFixed(1)} Tf');
      buf.writeln('${x.toStringAsFixed(2)} ${y.toStringAsFixed(2)} Td');
      buf.writeln('${encode(text)} Tj');
      buf.writeln('ET');
      buf.writeln('Q');
    }

    if (opts.headerText != null) {
      draw(opts.headerText!, pageHeightPt - marginTop * 0.55, _RunAlign.center);
    }
    final footerY = marginBottom * 0.45;
    if (opts.footerText != null) {
      draw(opts.footerText!, footerY, _RunAlign.left);
    }
    if (opts.showPageNumbers) {
      final label = opts.pageNumberTemplate
          .replaceAll('{page}', '${pageIndex + 1}')
          .replaceAll('{total}', '$pageCount');
      draw(label, footerY, _RunAlign.center);
    }
  }

  void _writeBox(
    StringBuffer buf,
    _PdfBox box,
    double pageHeightPt,
    double marginTop,
  ) {
    final top = pageHeightPt - marginTop - box.yTop;
    final bottom = top - box.height;
    final left = box.xLeft;
    final right = box.xLeft + box.width;

    if (box.fill != null) {
      buf.writeln('q');
      buf.writeln('${pdfRgb(box.fill!)} rg');
      buf.writeln('${left.toStringAsFixed(2)} ${bottom.toStringAsFixed(2)} '
          '${box.width.toStringAsFixed(2)} ${box.height.toStringAsFixed(2)} re f');
      buf.writeln('Q');
    }

    if (box.stroke != null) {
      buf.writeln('q');
      buf.writeln('${pdfRgb(box.stroke!)} RG');
      buf.writeln('${box.strokeWidth.toStringAsFixed(2)} w');
      // Sides always; top/bottom only when the frame is not open there.
      void line(double x1, double y1, double x2, double y2) => buf.writeln(
          '${x1.toStringAsFixed(2)} ${y1.toStringAsFixed(2)} m '
          '${x2.toStringAsFixed(2)} ${y2.toStringAsFixed(2)} l S');
      line(left, top, left, bottom);
      line(right, top, right, bottom);
      if (!box.topOpen) line(left, top, right, top);
      if (!box.bottomOpen) line(left, bottom, right, bottom);
      buf.writeln('Q');
    }
  }

  void _writeTextLine(
    StringBuffer buf,
    _PdfTextLine line,
    double pageHeightPt,
    double marginTop,
    bool type0,
    int fontCount,
    String Function(String) encode,
    String Function(int, String) encodeWith,
    List<(int, String)> Function(String) splitByFont,
    FontMetrics metrics,
    List<_LinkAnnot> annots,
  ) {
    final baseline = pageHeightPt - marginTop - line.yTop - line.maxSize;

    // Emit one positioned, styled piece (a whole run, or a font-run within a
    // run when several embedded fonts are in play).
    void drawPiece(_PdfSeg s, double y, String fontKey, String encoded,
        double pieceX, double pieceWidth, bool fauxBold, bool fauxItalic) {
      // Clickable link annotation over the piece box.
      if (s.link != null && s.link!.isNotEmpty) {
        annots.add(_LinkAnnot(pieceX, y - s.size * 0.2, pieceX + pieceWidth,
            y + s.size, s.link!));
      }

      // Highlight rectangle behind the piece.
      if (s.highlight != null) {
        buf.writeln('q');
        buf.writeln('${pdfRgb(s.highlight!)} rg');
        final hy = y - s.size * 0.2;
        buf.writeln('${pieceX.toStringAsFixed(2)} ${hy.toStringAsFixed(2)} '
            '${pieceWidth.toStringAsFixed(2)} ${(s.size * 1.0).toStringAsFixed(2)} re f');
        buf.writeln('Q');
      }

      buf.writeln('BT');
      if (s.color != null) buf.writeln('${pdfRgb(s.color!)} rg');
      if (fauxBold) {
        // Stroke the glyphs to thicken them.
        buf.writeln('2 Tr');
        buf.writeln('${(s.size * 0.03).toStringAsFixed(2)} w');
        if (s.color != null) buf.writeln('${pdfRgb(s.color!)} RG');
      }
      buf.writeln('$fontKey ${s.size.toStringAsFixed(1)} Tf');
      if (fauxItalic) {
        // Shear the text matrix ~10.5° for a synthetic oblique.
        buf.writeln('1 0 0.182 1 ${pieceX.toStringAsFixed(2)} '
            '${y.toStringAsFixed(2)} Tm');
      } else {
        buf.writeln('${pieceX.toStringAsFixed(2)} ${y.toStringAsFixed(2)} Td');
      }
      buf.writeln('$encoded Tj');
      if (fauxBold) buf.writeln('0 Tr');
      buf.writeln('ET');
      if (s.color != null) buf.writeln('0 0 0 rg');

      // Decorations.
      if (s.underline || s.strike) {
        buf.writeln('q');
        if (s.color != null) buf.writeln('${pdfRgb(s.color!)} RG');
        buf.writeln('${(s.size * 0.06).toStringAsFixed(2)} w');
        if (s.underline) {
          final uy = y - s.size * 0.12;
          buf.writeln('${pieceX.toStringAsFixed(2)} ${uy.toStringAsFixed(2)} m '
              '${(pieceX + pieceWidth).toStringAsFixed(2)} ${uy.toStringAsFixed(2)} l S');
        }
        if (s.strike) {
          final sy = y + s.size * 0.28;
          buf.writeln('${pieceX.toStringAsFixed(2)} ${sy.toStringAsFixed(2)} m '
              '${(pieceX + pieceWidth).toStringAsFixed(2)} ${sy.toStringAsFixed(2)} l S');
        }
        buf.writeln('Q');
      }
    }

    for (final s in line.segments) {
      if (s.text.isEmpty) continue;
      final y = baseline + s.baselineShift;
      // Type0 has a single face per font; bold / italic are synthesised (faux).
      final fauxBold = type0 && s.bold;
      final fauxItalic = type0 && s.italic;

      if (!type0 || fontCount <= 1) {
        // One piece. Helvetica picks a real variant; single Type0 uses /F1.
        final fontKey = type0
            ? '/F1'
            : s.bold && s.italic
                ? '/F4'
                : s.bold
                    ? '/F2'
                    : s.italic
                        ? '/F3'
                        : '/F1';
        drawPiece(
            s, y, fontKey, encode(s.text), s.x, s.width, fauxBold, fauxItalic);
      } else {
        // Several embedded fonts: split the run by glyph coverage and draw each
        // font-run with its own resource, advancing x by its measured width.
        var px = s.x;
        for (final (fi, runText) in splitByFont(s.text)) {
          final w = measureText(runText, s.size, bold: s.bold, metrics: metrics);
          drawPiece(s, y, '/F${fi + 1}', encodeWith(fi, runText), px, w,
              fauxBold, fauxItalic);
          px += w;
        }
      }
    }
  }

  /// Draw a chart's geometry. Geometry uses a top-left origin (y down); PDF
  /// user space is bottom-left (y up), so y is flipped about the chart's top.
  void _writeChart(
    StringBuffer buf,
    _PdfChart chart,
    double pageHeightPt,
    double marginTop,
    double marginLeft,
    String Function(String) encode,
  ) {
    final geo = chart.geometry;
    final originY = pageHeightPt - marginTop - chart.yTop;
    double px(double gx) => marginLeft + gx;
    double py(double gy) => originY - gy;

    // Filled rectangles (bars / legend swatches).
    for (final r in geo.rects) {
      buf.writeln('q');
      buf.writeln('${pdfRgb(r.color)} rg');
      buf.writeln('${px(r.x).toStringAsFixed(2)} '
          '${py(r.y + r.h).toStringAsFixed(2)} '
          '${r.w.toStringAsFixed(2)} ${r.h.toStringAsFixed(2)} re f');
      buf.writeln('Q');
    }

    // Pie wedges, approximated by a fan of short segments.
    for (final wge in geo.wedges) {
      buf.writeln('q');
      buf.writeln('${pdfRgb(wge.color)} rg');
      final steps = math.max(2, (wge.sweepRad / 0.1).ceil());
      buf.writeln('${px(wge.cx).toStringAsFixed(2)} '
          '${py(wge.cy).toStringAsFixed(2)} m');
      for (var i = 0; i <= steps; i++) {
        final a = wge.startRad + wge.sweepRad * (i / steps);
        final gx = wge.cx + math.cos(a) * wge.r;
        final gy = wge.cy + math.sin(a) * wge.r;
        buf.writeln('${px(gx).toStringAsFixed(2)} '
            '${py(gy).toStringAsFixed(2)} l');
      }
      buf.writeln('f');
      buf.writeln('Q');
    }

    // Poly-lines (line series).
    for (final pl in geo.polylines) {
      if (pl.points.isEmpty) continue;
      buf.writeln('q');
      buf.writeln('${pdfRgb(pl.color)} RG');
      buf.writeln('${pl.width.toStringAsFixed(2)} w');
      for (var i = 0; i < pl.points.length; i++) {
        final p = pl.points[i];
        buf.writeln('${px(p.x).toStringAsFixed(2)} '
            '${py(p.y).toStringAsFixed(2)} ${i == 0 ? 'm' : 'l'}');
      }
      buf.writeln('S');
      buf.writeln('Q');
    }

    // Axis / gridline segments.
    for (final s in geo.segments) {
      buf.writeln('q');
      buf.writeln('${pdfRgb(s.color)} RG');
      buf.writeln('${s.width.toStringAsFixed(2)} w');
      buf.writeln('${px(s.x1).toStringAsFixed(2)} ${py(s.y1).toStringAsFixed(2)} m '
          '${px(s.x2).toStringAsFixed(2)} ${py(s.y2).toStringAsFixed(2)} l S');
      buf.writeln('Q');
    }

    // Text labels (title / axis ticks / categories / legend / slice labels).
    for (final t in geo.texts) {
      final w = measureText(t.text, t.size);
      var x = px(t.x);
      if (t.anchor == ChartAnchor.middle) {
        x -= w / 2;
      } else if (t.anchor == ChartAnchor.end) {
        x -= w;
      }
      buf.writeln('BT');
      buf.writeln('${pdfRgb(t.color)} rg');
      buf.writeln('/F1 ${t.size.toStringAsFixed(1)} Tf');
      buf.writeln('${x.toStringAsFixed(2)} ${py(t.y).toStringAsFixed(2)} Td');
      buf.writeln('${encode(t.text)} Tj');
      buf.writeln('ET');
      buf.writeln('0 0 0 rg');
    }
  }

  /// Build a ToUnicode CMap so PDF text remains searchable / copyable: maps
  /// each used glyph id back to its Unicode code point.
  static String _buildToUnicode(Map<int, int> gidToUni) {
    String hex16(int v) => v.toRadixString(16).padLeft(4, '0').toUpperCase();
    String uniHex(int cp) {
      if (cp <= 0xFFFF) return hex16(cp);
      // Non-BMP → UTF-16 surrogate pair.
      final v = cp - 0x10000;
      final hi = 0xD800 + (v >> 10);
      final lo = 0xDC00 + (v & 0x3FF);
      return '${hex16(hi)}${hex16(lo)}';
    }

    final entries = gidToUni.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final sb = StringBuffer();
    sb.writeln('/CIDInit /ProcSet findresource begin');
    sb.writeln('12 dict begin');
    sb.writeln('begincmap');
    sb.writeln('/CIDSystemInfo <</Registry (Adobe) /Ordering (UCS) '
        '/Supplement 0>> def');
    sb.writeln('/CMapName /Adobe-Identity-UCS def');
    sb.writeln('/CMapType 2 def');
    sb.writeln('1 begincodespacerange <0000> <FFFF> endcodespacerange');
    // bfchar sections are capped at 100 entries each.
    for (var i = 0; i < entries.length; i += 100) {
      final chunk = entries.sublist(i, (i + 100).clamp(0, entries.length));
      sb.writeln('${chunk.length} beginbfchar');
      for (final e in chunk) {
        sb.writeln('<${hex16(e.key)}> <${uniHex(e.value)}>');
      }
      sb.writeln('endbfchar');
    }
    sb.writeln('endcmap');
    sb.writeln('CMapName currentdict /CMap defineresource pop');
    sb.writeln('end');
    sb.writeln('end');
    return sb.toString();
  }

  /// Unicode code points that map to WinAnsi (CP1252) bytes 0x80–0x9F, which
  /// differ from Latin-1 (em/en dashes, curly quotes, bullet, …).
  static const Map<int, int> _winAnsiHigh = {
    0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85,
    0x2020: 0x86, 0x2021: 0x87, 0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A,
    0x2039: 0x8B, 0x0152: 0x8C, 0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92,
    0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97,
    0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B, 0x0153: 0x9C,
    0x017E: 0x9E, 0x0178: 0x9F,
  };

  /// Escape and transcode a string into a PDF literal using the font's
  /// WinAnsiEncoding: ASCII passes through, Latin-1 / CP1252 punctuation become
  /// octal escapes (`\ddd`), and code points the built-in fonts cannot show
  /// (e.g. CJK — these need an embedded font) degrade to `?`.
  /// A deterministic 32-hex-char document ID derived from the document /
  /// template identity (no randomness available; PDF/A needs a stable /ID).
  static String _docId(RenderContext context) {
    final seed = '${context.document.documentId}:${context.document.templateId}'
        ':${context.document.templateVersion}';
    var h = 0x811c9dc5;
    for (final c in seed.codeUnits) {
      h = (h ^ c) & 0xffffffff;
      h = (h * 0x01000193) & 0xffffffff;
    }
    final buf = StringBuffer();
    for (var i = 0; i < 4; i++) {
      buf.write(h.toRadixString(16).padLeft(8, '0'));
      h = (h * 0x01000193 + i + 1) & 0xffffffff;
    }
    return buf.toString().substring(0, 32);
  }

  /// An XMP metadata packet for PDF/A output (Dublin Core + pdfaid).
  static String _xmpMetadata(RenderContext context) {
    final doc = context.document;
    final title = context.template.name;
    final author = doc.metadata.author;
    final created = (doc.metadata.createdAt).toIso8601String();
    String esc(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    final pdfaPart = context.options.pdfA
        ? '<pdfaid:part>2</pdfaid:part>'
            '<pdfaid:conformance>B</pdfaid:conformance>'
        : '';
    final pdfuaPart =
        context.options.taggedPdf ? '<pdfuaid:part>1</pdfuaid:part>' : '';
    return '<?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>'
        '<x:xmpmeta xmlns:x="adobe:ns:meta/">'
        '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
        '<rdf:Description rdf:about="" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:xmp="http://ns.adobe.com/xap/1.0/" '
        'xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/" '
        'xmlns:pdfuaid="http://www.aiim.org/pdfua/ns/id/">'
        '<dc:title><rdf:Alt><rdf:li xml:lang="x-default">${esc(title)}'
        '</rdf:li></rdf:Alt></dc:title>'
        '<dc:creator><rdf:Seq><rdf:li>${esc(author)}</rdf:li></rdf:Seq>'
        '</dc:creator>'
        '<xmp:CreateDate>$created</xmp:CreateDate>'
        '$pdfaPart$pdfuaPart'
        '</rdf:Description></rdf:RDF></x:xmpmeta><?xpacket end="w"?>';
  }

  static String _escapePdfString(String text) {
    final sb = StringBuffer();
    for (final r in text.runes) {
      if (r == 0x28) {
        sb.write(r'\(');
      } else if (r == 0x29) {
        sb.write(r'\)');
      } else if (r == 0x5C) {
        sb.write(r'\\');
      } else if (r >= 0x20 && r <= 0x7E) {
        sb.writeCharCode(r);
      } else {
        final b = (r >= 0xA0 && r <= 0xFF) ? r : _winAnsiHigh[r];
        if (b == null) {
          sb.write('?');
        } else {
          sb.write('\\${b.toRadixString(8).padLeft(3, '0')}');
        }
      }
    }
    return sb.toString();
  }

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

/// Alignment of running header / footer text.
enum _RunAlign { left, center, right }

/// A clickable link annotation rectangle (PDF user space).
class _LinkAnnot {
  _LinkAnnot(this.x1, this.y1, this.x2, this.y2, this.uri);
  final double x1, y1, x2, y2;
  final String uri;
}

/// A positioned, styled run on a page.
class _PdfSeg {
  _PdfSeg({
    required this.text,
    required this.x,
    required this.size,
    this.bold = false,
    this.italic = false,
    this.color,
    this.underline = false,
    this.strike = false,
    this.highlight,
    this.baselineShift = 0,
    this.width = 0,
    this.link,
  });

  final String text;
  final double x;
  final double size;
  final bool bold;
  final bool italic;
  final ({double r, double g, double b})? color;
  final bool underline;
  final bool strike;
  final ({double r, double g, double b})? highlight;
  final double baselineShift;
  final double width;
  final String? link;

  /// Copy with a new text / position / width (used by justify re-spacing).
  _PdfSeg copyWith({String? text, double? x, double? width}) => _PdfSeg(
        text: text ?? this.text,
        x: x ?? this.x,
        size: size,
        bold: bold,
        italic: italic,
        color: color,
        underline: underline,
        strike: strike,
        highlight: highlight,
        baselineShift: baselineShift,
        width: width ?? this.width,
        link: link,
      );
}

/// A laid-out line of styled runs. [yTop] is the cursor offset from the content
/// top in points; [maxSize] drives the baseline and line height.
class _PdfTextLine {
  _PdfTextLine({
    required this.segments,
    required this.yTop,
    required this.maxSize,
  });

  final List<_PdfSeg> segments;
  double yTop;
  final double maxSize;

  /// Structure-element index for tagged PDF, or null for an artifact.
  int? structId;
}

/// A background / border box fragment occupying one page. [topOpen] /
/// [bottomOpen] suppress the corresponding edge where the frame splits.
class _PdfBox {
  _PdfBox({
    required this.xLeft,
    required this.width,
    required this.yTop,
    required this.height,
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
    required this.topOpen,
    required this.bottomOpen,
  });

  final double xLeft;
  final double width;
  final double yTop;
  final double height;
  final ({double r, double g, double b})? fill;
  final ({double r, double g, double b})? stroke;
  final double strokeWidth;
  final bool topOpen;
  final bool bottomOpen;

  /// Structure-element index for tagged PDF, or null for an artifact.
  int? structId;
}

/// Mutable state for a box being laid out across (possibly) multiple pages.
class _ActiveBox {
  _ActiveBox({
    required this.list,
    required this.topY,
    required this.indent,
    required this.backgroundHex,
    required this.borderColor,
    required this.borderWidth,
    required this.topOpen,
  });

  List<Object> list;
  double topY;
  final double indent;
  final String? backgroundHex;
  final String? borderColor;
  final double borderWidth;
  bool topOpen;
}

/// An embedded raster image placed in the page flow.
class _PdfImage {
  _PdfImage({
    required this.bytes,
    required this.dctDecode,
    required this.pxW,
    required this.pxH,
    required this.drawW,
    required this.drawH,
    required this.yTop,
    this.absX,
    this.absYBottom,
  });

  final List<int> bytes;
  final bool dctDecode;
  final int pxW;
  final int pxH;
  final double drawW;
  final double drawH;
  final double yTop;

  /// Absolute page placement (PDF user space, from the page's left / bottom
  /// edges) for a `style.placement` block — bypasses the margin-relative flow
  /// position. Null for a normal in-flow image.
  final double? absX;
  final double? absYBottom;

  /// Structure-element index for tagged PDF, or null for an artifact.
  int? structId;
}

/// A native chart draw item: pre-computed geometry placed at [yTop].
class _PdfChart {
  _PdfChart({required this.geometry, required this.yTop});
  final ChartGeometry geometry;
  final double yTop;

  /// Structure-element index for tagged PDF, or null for an artifact.
  int? structId;
}

/// Decodes an image `src` for PDF embedding. A JPEG data URI passes through as
/// DCTDecode (compact, lossless). Other base64 data URIs (PNG / GIF / WebP /
/// BMP) are decoded to raw RGB samples (alpha flattened over white). Returns
/// null for non-data-URI sources or undecodable data.
({List<int> bytes, int w, int h, bool dct})? _decodeImage(String src) {
  final m = RegExp(r'^data:image/[^;]+;base64,(.+)$', dotAll: true)
      .firstMatch(src.trim());
  if (m == null) return null;
  Uint8List raw;
  try {
    raw = base64Decode(m.group(1)!.replaceAll(RegExp(r'\s'), ''));
  } catch (_) {
    return null;
  }
  if (raw.length >= 3 && raw[0] == 0xFF && raw[1] == 0xD8 && raw[2] == 0xFF) {
    final s = _jpegSize(raw);
    if (s != null && s.w > 0 && s.h > 0) {
      return (bytes: raw, w: s.w, h: s.h, dct: true);
    }
  }
  final decoded = img.decodeImage(raw);
  if (decoded == null || decoded.width == 0 || decoded.height == 0) return null;
  final w = decoded.width;
  final h = decoded.height;
  final rgb = Uint8List(w * h * 3);
  var k = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = decoded.getPixel(x, y);
      final a = p.aNormalized;
      rgb[k++] = ((p.rNormalized * a + (1 - a)) * 255).round().clamp(0, 255);
      rgb[k++] = ((p.gNormalized * a + (1 - a)) * 255).round().clamp(0, 255);
      rgb[k++] = ((p.bNormalized * a + (1 - a)) * 255).round().clamp(0, 255);
    }
  }
  return (bytes: rgb, w: w, h: h, dct: false);
}

/// Reads pixel dimensions from a JPEG's SOF marker. Returns null if not found.
({int w, int h})? _jpegSize(List<int> b) {
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    final isSof = (marker >= 0xC0 && marker <= 0xCF) &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isSof) {
      final h = (b[i + 5] << 8) | b[i + 6];
      final w = (b[i + 7] << 8) | b[i + 8];
      return (w: w, h: h);
    }
    final segLen = (b[i + 2] << 8) | b[i + 3];
    if (segLen < 2) return null;
    i += 2 + segLen;
  }
  return null;
}
