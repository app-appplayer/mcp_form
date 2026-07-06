import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:mcp_bundle/mcp_bundle.dart';

import '../../../core/template/layout_extensions.dart';
import '../../../style/truetype_font.dart';
import '../render_context.dart';
import '../renderer_registry.dart';

/// Pure-Dart raster renderer: a [FormDocument] → a PNG image.
///
/// Text is drawn by rasterizing the injected TrueType font's own glyph
/// outlines (contours → quadratic-bezier flatten → scanline even-odd fill), so
/// multilingual output (CJK included) renders correctly given a suitable
/// `context.embeddedFont`. No browser, no platform canvas.
///
/// Scope (v1): the common blocks — headings, text, images, and page
/// background — enough for business cards and typical single-column documents.
/// Tables, charts, math, columns and `style.placement` are a follow-up; a
/// block type it does not lay out is skipped.
class ImageRenderer implements DocumentRenderer {
  const ImageRenderer({this.dpi = 150});

  /// Output resolution. Points → pixels at `dpi / 72`.
  final double dpi;

  @override
  List<String> get supportedFormats => const ['image', 'png'];

  @override
  String? get supportedTemplateRange => null;

  @override
  Future<FormRenderOutput> render(RenderContext context) async {
    final layout = context.layoutPolicy;
    final fonts = context.template.layoutPolicy.fontPolicy;
    final font = context.embeddedFont;
    final ptToPx = dpi / 72.0;
    final mmToPx = dpi / 25.4;

    final paged = context.options.pageFlow != PageFlow.continuous;
    final width = (layout.effectivePageWidth * mmToPx).round();
    final pageBoxH = (layout.effectivePageHeight * mmToPx).round();
    // Paged → the full page box (A4/A3/card at its real aspect). Continuous →
    // grow, then crop to content (web/app-like).
    final maxHeight = paged ? pageBoxH : math.max(pageBoxH, 6000);
    final canvas = img.Image(width: width, height: maxHeight);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

    final marginL = layout.margins.left * mmToPx;
    final marginR = layout.margins.right * mmToPx;
    final marginT = layout.margins.top * mmToPx;
    final contentW = width - marginL - marginR;
    final black = img.ColorRgb8(0, 0, 0);

    // `style.placement` blocks leave the flow and draw at page coordinates.
    // Backgrounds (`z: 'back'`) draw first (behind), the rest after (in front).
    final placed = <FormBlock>[];
    bool isPlaced(FormBlock b) => b.style?['placement'] != null;
    for (final s in context.document.sections) {
      for (final b in s.blocks) {
        if (isPlaced(b)) placed.add(b);
      }
    }
    for (final b in placed.where((b) => b.style!['placement']['z'] == 'back')) {
      _drawPlaced(canvas, b, width.toDouble(), pageBoxH.toDouble(), mmToPx,
          ptToPx, font, fonts, black, context.document.data);
    }

    var y = marginT; // pen baseline advances downward

    void drawParagraph(String text, double sizePt, {bool bold = false}) {
      final sizePx = sizePt * ptToPx;
      final lineH = sizePx * 1.35;
      for (final raw in text.split('\n')) {
        for (final line in _wrap(raw, sizePx, contentW, font)) {
          y += sizePx; // move to baseline
          _drawText(canvas, line, marginL, y, sizePx, font, black);
          y += lineH - sizePx;
        }
      }
      y += lineH * 0.3; // paragraph gap
    }

    for (final section in context.document.sections) {
      if (section.title != null) {
        drawParagraph(section.title!, fonts.headingSize.toDouble(), bold: true);
      }
      for (final block in section.blocks) {
        if (isPlaced(block)) continue; // drawn absolutely, not in flow
        switch (block) {
          case FormHeadingBlock():
            drawParagraph(block.content,
                fonts.headingSizeForLevel(block.level).toDouble(),
                bold: true);
          case FormTextBlock():
            drawParagraph(block.content, fonts.bodySize.toDouble());
          case FormFieldBlock():
            final v = context.document.data[block.fieldName];
            drawParagraph('${block.fieldName}: ${v ?? ''}',
                fonts.bodySize.toDouble());
          case FormTableBlock():
            y = _drawTable(canvas, block, marginL, y, contentW,
                fonts.bodySize.toDouble() * ptToPx, font, black);
          case FormImageBlock():
            y = _drawImage(canvas, block, marginL, y, contentW, mmToPx);
          default:
            // Charts / math / columns / repeatable — a follow-up; skipped.
            break;
        }
        if (y > maxHeight - 200) break;
      }
    }

    // Foreground placement (seals, footer company name). Anchor to the page
    // box (paged) or the content bottom (continuous).
    final pageH = paged ? pageBoxH.toDouble() : (y + marginT);
    for (final b in placed.where((b) => b.style!['placement']['z'] != 'back')) {
      _drawPlaced(canvas, b, width.toDouble(), pageH, mmToPx, ptToPx, font,
          fonts, black, context.document.data);
    }

    // Paged output is the whole page box; continuous crops to the content.
    final outH = paged ? pageBoxH : (y + marginT).clamp(1, maxHeight).round();
    final cropped = img.copyCrop(canvas, x: 0, y: 0, width: width, height: outH);
    final png = img.encodePng(cropped);

    return FormRenderOutput(
      format: 'image',
      content: png,
      pageCount: 1,
      generatedAt: context.document.metadata.modifiedAt ??
          context.document.metadata.createdAt,
    );
  }

  /// Word-wrap [text] to [maxW] px using glyph advances (or an estimate).
  List<String> _wrap(
      String text, double sizePx, double maxW, TrueTypeFont? font) {
    if (text.isEmpty) return const [''];
    final words = text.split(' ');
    final lines = <String>[];
    var line = '';
    for (final w in words) {
      final candidate = line.isEmpty ? w : '$line $w';
      if (_measure(candidate, sizePx, font) > maxW && line.isNotEmpty) {
        lines.add(line);
        line = w;
      } else {
        line = candidate;
      }
    }
    if (line.isNotEmpty || lines.isEmpty) lines.add(line);
    return lines;
  }

  double _measure(String s, double sizePx, TrueTypeFont? font) {
    if (font == null) return s.length * sizePx * 0.55;
    final scale = sizePx / font.unitsPerEm;
    var w = 0.0;
    for (final cp in s.runes) {
      final gid = font.gidFor(cp) ?? 0;
      w += font.advanceWidthFontUnits(gid) * scale;
    }
    return w;
  }

  /// Draw a text run, glyph by glyph, at baseline ([x], [y]).
  void _drawText(img.Image canvas, String text, double x, double y,
      double sizePx, TrueTypeFont? font, img.Color color) {
    if (font == null) {
      // No font injected: fall back to the bundled bitmap font (ASCII only).
      img.drawString(canvas, text,
          font: img.arial24, x: x.round(), y: (y - sizePx).round(), color: color);
      return;
    }
    final scale = sizePx / font.unitsPerEm;
    var penX = x;
    for (final cp in text.runes) {
      final gid = font.gidFor(cp) ?? 0;
      if (cp != 0x20) {
        _fillGlyph(canvas, font.glyphContours(gid), penX, y, scale, color);
      }
      penX += font.advanceWidthFontUnits(gid) * scale;
    }
  }

  /// Rasterize one glyph's contours with the even-odd rule.
  void _fillGlyph(
    img.Image canvas,
    List<List<(double, double, bool)>> contours,
    double originX,
    double baselineY,
    double scale,
    img.Color color,
  ) {
    if (contours.isEmpty) return;
    // Flatten each contour (quadratic beziers) to a device-space polygon.
    final polys = <List<({double x, double y})>>[];
    for (final c in contours) {
      polys.add(_flatten(c, originX, baselineY, scale));
    }
    // Even-odd scanline fill across all contours (holes handled).
    var minY = double.infinity, maxY = -double.infinity;
    for (final p in polys) {
      for (final pt in p) {
        minY = math.min(minY, pt.y);
        maxY = math.max(maxY, pt.y);
      }
    }
    final y0 = minY.floor().clamp(0, canvas.height - 1);
    final y1 = maxY.ceil().clamp(0, canvas.height - 1);
    for (var sy = y0; sy <= y1; sy++) {
      final yc = sy + 0.5;
      final xs = <double>[];
      for (final poly in polys) {
        for (var i = 0; i < poly.length; i++) {
          final a = poly[i];
          final b = poly[(i + 1) % poly.length];
          final ay = a.y, by = b.y;
          if ((ay <= yc && by > yc) || (by <= yc && ay > yc)) {
            xs.add(a.x + (yc - ay) / (by - ay) * (b.x - a.x));
          }
        }
      }
      xs.sort();
      for (var i = 0; i + 1 < xs.length; i += 2) {
        final xa = xs[i].round().clamp(0, canvas.width - 1);
        final xb = xs[i + 1].round().clamp(0, canvas.width - 1);
        for (var px = xa; px <= xb; px++) {
          canvas.setPixel(px, sy, color);
        }
      }
    }
  }

  /// Flatten a glyph contour (on/off-curve points) into a device polygon.
  List<({double x, double y})> _flatten(
    List<(double, double, bool)> c,
    double originX,
    double baselineY,
    double scale,
  ) {
    ({double x, double y}) dev(double gx, double gy) =>
        (x: originX + gx * scale, y: baselineY - gy * scale); // font y-up → down

    // Ensure the contour starts on-curve (insert a midpoint if needed).
    final pts = <(double, double, bool)>[...c];
    if (pts.isNotEmpty && !pts.first.$3) {
      if (pts.last.$3) {
        pts.insert(0, pts.removeLast());
      } else {
        final mid = (
          (pts.first.$1 + pts.last.$1) / 2,
          (pts.first.$2 + pts.last.$2) / 2,
          true,
        );
        pts.insert(0, mid);
      }
    }

    final out = <({double x, double y})>[];
    if (pts.isEmpty) return out;
    out.add(dev(pts.first.$1, pts.first.$2));
    for (var i = 1; i <= pts.length; i++) {
      final cur = pts[i % pts.length];
      if (cur.$3) {
        out.add(dev(cur.$1, cur.$2));
      } else {
        // Quadratic control; next on-curve is either the following point or an
        // implied midpoint between two consecutive off-curve points.
        final nxt = pts[(i + 1) % pts.length];
        final end = nxt.$3
            ? (nxt.$1, nxt.$2)
            : ((cur.$1 + nxt.$1) / 2, (cur.$2 + nxt.$2) / 2);
        final p0 = out.last;
        const steps = 8;
        for (var s = 1; s <= steps; s++) {
          final t = s / steps;
          final mt = 1 - t;
          final gx = mt * mt * (p0.x - originX) / scale +
              2 * mt * t * cur.$1 +
              t * t * end.$1;
          final gy = mt * mt * (baselineY - p0.y) / scale +
              2 * mt * t * cur.$2 +
              t * t * end.$2;
          out.add(dev(gx, gy));
        }
        if (nxt.$3) i++; // consumed the end point
      }
    }
    return out;
  }

  /// Draw a `style.placement` block at page coordinates (device px, y down),
  /// measured from the paper corner. Handles image (with `z`/`fit`/full-bleed)
  /// and text blocks; other types are skipped.
  void _drawPlaced(
    img.Image canvas,
    FormBlock block,
    double pageW,
    double pageH,
    double mmToPx,
    double ptToPx,
    TrueTypeFont? font,
    FormFontPolicy fonts,
    img.Color color,
    Map<String, dynamic> data,
  ) {
    final pl = (block.style!['placement'] as Map).cast<String, dynamic>();
    final anchor = pl['anchor'] as String? ?? 'bottom-right';
    final xPx = ((pl['x'] as num?)?.toDouble() ?? 0) * mmToPx;
    final yPx = ((pl['y'] as num?)?.toDouble() ?? 0) * mmToPx;

    // Top-left of a w×h box for the given anchor (y measured downward).
    (double, double) box(double w, double h) => switch (anchor) {
          'top-left' => (xPx, yPx),
          'top-right' => (pageW - xPx - w, yPx),
          'top-center' => ((pageW - w) / 2 + xPx, yPx),
          'bottom-left' => (xPx, pageH - yPx - h),
          'bottom-center' => ((pageW - w) / 2 + xPx, pageH - yPx - h),
          'center' => ((pageW - w) / 2 + xPx, (pageH - h) / 2 + yPx),
          _ => (pageW - xPx - w, pageH - yPx - h), // bottom-right
        };

    if (block is FormImageBlock) {
      final bytes = _dataUriBytes(block.src);
      if (bytes == null) return;
      final im = img.decodeImage(bytes);
      if (im == null) return;
      double sizePx(Object? spec, double full) => spec == 'full'
          ? full
          : (spec is num ? spec.toDouble() * mmToPx : double.nan);
      final fit = (pl['fit'] as String?) ?? block.style?['fit'] as String?;
      var boxW = sizePx(pl['width'], pageW);
      var boxH = sizePx(pl['height'], pageH);
      final ratio = block.aspectRatio ?? (im.height / im.width);
      double drawW;
      double drawH;
      if (fit != null && !boxW.isNaN && !boxH.isNaN) {
        final cover = fit == 'cover';
        if ((ratio > boxH / boxW) == cover) {
          drawW = boxW;
          drawH = boxW * ratio;
        } else {
          drawH = boxH;
          drawW = boxH / ratio;
        }
      } else {
        drawW = !boxW.isNaN
            ? boxW
            : (block.maxWidth != null ? block.maxWidth! * (dpi / 96.0) : 120.0);
        drawH = drawW * ratio;
        boxW = drawW;
        boxH = drawH;
      }
      final (bx, by) = box(boxW, boxH);
      final resized =
          img.copyResize(im, width: drawW.round(), height: drawH.round());
      img.compositeImage(canvas, resized,
          dstX: (bx + (boxW - drawW) / 2).round(),
          dstY: (by + (boxH - drawH) / 2).round());
    } else if (block is FormTextBlock) {
      final sizePx = fonts.bodySize * ptToPx;
      final lines =
          block.content.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) return;
      final lh = sizePx * 1.3;
      final blockH = lh * lines.length;
      final blockW =
          lines.map((l) => _measure(l, sizePx, font)).fold(0.0, math.max);
      final (bx, byTop) = box(blockW, blockH);
      for (var i = 0; i < lines.length; i++) {
        _drawText(canvas, lines[i], bx, byTop + sizePx + i * lh, sizePx, font,
            color);
      }
    }
  }

  /// Draw a table (header row + data rows) with cell borders; returns the new
  /// cursor y. Column widths follow `FormTableColumn.width` as proportional
  /// weights (default 1.0 each = equal), matching the PDF renderer.
  double _drawTable(img.Image canvas, FormTableBlock block, double x, double y,
      double width, double sizePx, TrueTypeFont? font, img.Color color) {
    final cols = block.columns;
    if (cols.isEmpty) return y;
    final weights = [for (final c in cols) (c.width ?? 1.0)];
    final total = weights.fold(0.0, (a, b) => a + b);
    // Per-column widths + left edges from the weights.
    final colW = [for (final w in weights) width * w / total];
    final colX = <double>[];
    var acc = x;
    for (final w in colW) {
      colX.add(acc);
      acc += w;
    }
    final rowH = sizePx * 1.9;
    final grid = img.ColorRgb8(180, 180, 180);
    final headerFill = img.ColorRgb8(240, 240, 240);

    void cell(String text, int c, double cy, {bool header = false}) {
      final cx = colX[c];
      final w = colW[c];
      if (header) {
        img.fillRect(canvas,
            x1: cx.round(),
            y1: cy.round(),
            x2: (cx + w).round(),
            y2: (cy + rowH).round(),
            color: headerFill);
      }
      img.drawRect(canvas,
          x1: cx.round(),
          y1: cy.round(),
          x2: (cx + w).round(),
          y2: (cy + rowH).round(),
          color: grid);
      // Horizontal alignment per FormTableColumn.alignment (left / center /
      // right), measuring the text to place it in the cell.
      final pad = sizePx * 0.4;
      final tw = _measure(text, sizePx, font);
      final tx = switch (cols[c].alignment) {
        'right' => cx + w - tw - pad,
        'center' => cx + (w - tw) / 2,
        _ => cx + pad,
      };
      _drawText(canvas, text, tx, cy + rowH * 0.68, sizePx, font, color);
    }

    for (var c = 0; c < cols.length; c++) {
      cell(cols[c].title, c, y, header: true);
    }
    y += rowH;
    for (final row in block.rows) {
      if (y > canvas.height - rowH * 2) break;
      for (var c = 0; c < cols.length; c++) {
        final v = row.cells[cols[c].id];
        cell(v?.toString() ?? '', c, y);
      }
      y += rowH;
    }
    return y + sizePx * 0.6;
  }

  /// Decode + composite an image block; returns the new cursor y.
  double _drawImage(img.Image canvas, FormImageBlock block, double x, double y,
      double contentW, double mmToPx) {
    final src = block.src;
    final bytes = _dataUriBytes(src);
    if (bytes == null) return y;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return y;
    var drawW = contentW;
    if (block.maxWidth != null) {
      final capPx = block.maxWidth! * (dpi / 96.0); // maxWidth is CSS px
      drawW = math.min(drawW, capPx);
    }
    final ratio = block.aspectRatio ?? (decoded.height / decoded.width);
    final drawH = drawW * ratio;
    final resized =
        img.copyResize(decoded, width: drawW.round(), height: drawH.round());
    img.compositeImage(canvas, resized, dstX: x.round(), dstY: y.round());
    return y + drawH + 8;
  }

  Uint8List? _dataUriBytes(String src) {
    final m = RegExp(r'^data:[^;]+;base64,(.+)$', dotAll: true).firstMatch(src);
    if (m == null) return null; // only embedded (data-URI) images in v1
    try {
      return base64Decode(m.group(1)!.replaceAll(RegExp(r'\s'), ''));
    } catch (_) {
      return null;
    }
  }
}
