import 'dart:convert';
import 'dart:math' as math;

import 'package:mcp_bundle/mcp_bundle.dart';

import '../../../core/binding/repeatable_binding.dart';
import '../../../core/condition/condition_evaluator.dart';
import '../../../core/document/document_numbering.dart';
import '../../../core/template/layout_extensions.dart';
import '../../../style/style.dart';
import '../render_context.dart';
import '../renderer_registry.dart';

/// HTML5 output renderer.
///
/// Produces self-contained HTML with embedded CSS derived from
/// the document's [FormLayoutPolicy]. Rich inline runs and per-block styling
/// (from the `style` layer) become spans + inline CSS; the browser handles
/// layout and pagination.
class HtmlRenderer implements DocumentRenderer {
  const HtmlRenderer();

  @override
  List<String> get supportedFormats => const ['html'];

  @override
  String? get supportedTemplateRange => '>= 1.0.0 < 2.0.0';

  @override
  Future<FormRenderOutput> render(RenderContext context) async {
    final doc = context.document;
    final numbering = DocumentNumbering.compute(doc.sections);
    final footnotes = FootnoteCollector();
    final layout = context.layoutPolicy;
    final buf = StringBuffer();

    buf.writeln('<!DOCTYPE html>');
    buf.writeln('<html lang="en">');
    buf.writeln('<head>');
    buf.writeln('<meta charset="UTF-8">');
    buf.writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
    );

    if (context.options.includeMetadata) {
      buf.writeln('<meta name="author" content="${doc.metadata.author}">');
      buf.writeln(
        '<meta name="templateId" content="${doc.templateId}">',
      );
    }

    final sheet = context.styleSheet;

    buf.writeln('<title>${context.template.name}</title>');
    buf.writeln('<style>');
    _writeStyles(buf, layout, context.options, sheet);
    if (sheet != null) _writeThemeStyles(buf, sheet);
    buf.writeln('</style>');
    buf.writeln('</head>');
    buf.writeln('<body>');
    buf.writeln('<div class="document">');

    final logo = sheet?.theme.logo;
    if (logo != null && logo.isNotEmpty) {
      buf.writeln('<img class="logo" src="${_escape(logo)}" alt="logo">');
    }

    // `style.placement` blocks (any type) are pulled out of the flow and
    // emitted as absolute-positioned elements after the document body.
    final placedBlocks = <FormBlock>[];
    for (final section in doc.sections) {
      buf.writeln('<section>');
      if (section.title != null) {
        buf.writeln('<h2>${_escape(section.title!)}</h2>');
      }
      final blocks = section.blocks.where((b) {
        if (b.style?['placement'] != null) {
          placedBlocks.add(b);
          return false;
        }
        return true;
      }).toList();
      var i = 0;
      while (i < blocks.length) {
        // `style.pageBreak: before` → CSS page break for print (cover / TOC /
        // body / back-page structure). Screen is continuous; print honours it.
        // (`after` is expressed as `before` on the following block.)
        if (blocks[i].style?['pageBreak'] == 'before') {
          buf.writeln('<div style="break-before: page; '
              'page-break-before: always;"></div>');
        }
        final span = _colSpan(blocks[i]);
        if (span >= 12) {
          _renderBlock(buf, blocks[i], doc.data, sheet, numbering, footnotes);
          i++;
          continue;
        }
        // Gather consecutive blocks whose spans fit within one 12-column row.
        final row = <FormBlock>[blocks[i]];
        var acc = span;
        var j = i + 1;
        while (j < blocks.length) {
          final s = _colSpan(blocks[j]);
          if (s >= 12 || acc + s > 12) break;
          row.add(blocks[j]);
          acc += s;
          j++;
        }
        buf.writeln('<div class="grid-row">');
        for (final cell in row) {
          buf.writeln(
              '<div class="grid-cell" style="grid-column: span ${_colSpan(cell)};">');
          _renderBlock(buf, cell, doc.data, sheet, numbering, footnotes);
          buf.writeln('</div>');
        }
        buf.writeln('</div>');
        i = j;
      }
      buf.writeln('</section>');
    }

    if (!footnotes.isEmpty) {
      buf.writeln('<section class="footnotes">');
      buf.writeln('<hr>');
      buf.writeln('<ol>');
      for (final note in footnotes.notes) {
        buf.writeln('<li>${_escape(note)}</li>');
      }
      buf.writeln('</ol>');
      buf.writeln('</section>');
    }

    buf.writeln('</div>');

    // Absolute-placement blocks (any type — a corner seal, a footer company
    // name, …), anchored to the page box. The block renders through the normal
    // path, then the result is wrapped in an absolute container.
    for (final block in placedBlocks) {
      final pl = (block.style!['placement'] as Map).cast<String, dynamic>();
      final anchor = pl['anchor'] as String? ?? 'bottom-right';
      final x = (pl['x'] as num?)?.toDouble() ?? 0;
      final y = (pl['y'] as num?)?.toDouble() ?? 0;
      final pos = switch (anchor) {
        'top-left' => 'top: ${y}mm; left: ${x}mm;',
        'top-right' => 'top: ${y}mm; right: ${x}mm;',
        'top-center' =>
          'top: ${y}mm; left: 50%; transform: translateX(-50%);',
        'bottom-left' => 'bottom: ${y}mm; left: ${x}mm;',
        'bottom-center' =>
          'bottom: ${y}mm; left: 50%; transform: translateX(-50%);',
        'center' =>
          'top: 50%; left: 50%; transform: translate(-50%, -50%) '
              'translate(${x}mm, ${y}mm);',
        _ => 'bottom: ${y}mm; right: ${x}mm;', // bottom-right
      };
      final z = pl['z'] as String?;
      final fit = (pl['fit'] as String?) ??
          (block is FormImageBlock
              ? (block.style?['fit'] as String?)
              : null);
      final wSpec = pl['width'];
      final hSpec = pl['height'];
      String size(Object? s, String dim) => s == 'full'
          ? '$dim: 100%;'
          : (s is num ? '$dim: ${s}mm;' : '');
      final width = size(wSpec, 'width');
      final height = size(hSpec, 'height');
      final zc = z == 'back' ? 'z-index: -1;' : '';

      if (block is FormImageBlock && (fit != null || z == 'back')) {
        // Background / cover image — fill the absolute box with object-fit
        // instead of the in-flow figure rendering.
        final objectFit = fit ?? 'cover';
        buf.writeln('<div style="position: absolute; $pos $width $height $zc '
            'overflow: hidden;">');
        buf.write('<img src="${_escape(block.src)}" '
            'style="width: 100%; height: 100%; object-fit: $objectFit;"');
        if (block.alt != null) buf.write(' alt="${_escape(block.alt!)}"');
        buf.writeln('>');
        buf.writeln('</div>');
      } else {
        buf.writeln('<div style="position: absolute; $pos $width $zc">');
        _renderBlock(buf, block, doc.data, sheet, numbering, footnotes);
        buf.writeln('</div>');
      }
    }

    if (context.effectiveWatermark != null) {
      buf.writeln(
        '<div class="watermark">${_escape(context.effectiveWatermark!)}</div>',
      );
    }

    buf.writeln('</body>');
    buf.writeln('</html>');

    final content = buf.toString();
    final bytes = utf8.encode(content);

    return FormRenderOutput(
      format: 'html',
      content: bytes,
      pageCount: 1,
      fileSize: bytes.length,
      generatedAt: doc.metadata.modifiedAt ?? doc.metadata.createdAt,
    );
  }

  /// Inline `list-style-type` CSS for a list block, mapping the schema's
  /// `numberFormat` to the CSS keyword. Empty when the default suffices.
  String _listCss(String? listStyle, String? numberFormat) {
    final type = listStyle == 'ordered'
        ? switch (numberFormat) {
            'lower-alpha' => 'lower-alpha',
            'upper-alpha' => 'upper-alpha',
            'lower-roman' => 'lower-roman',
            'upper-roman' => 'upper-roman',
            _ => 'decimal',
          }
        : switch (numberFormat) {
            'circle' => 'circle',
            'square' => 'square',
            _ => 'disc',
          };
    return ' style="list-style-type: $type;"';
  }

  /// A block's 12-column grid span (`style.colSpan`); 12 (full width) by default.
  int _colSpan(FormBlock b) {
    final v = b.style?['colSpan'];
    return v is num ? v.toInt().clamp(1, 12) : 12;
  }

  /// Escaped caption text ("Figure 1: ...") for a figure / table, or null when
  /// the block carries no caption.
  String? _captionHtml(FormBlock block, DocumentNumbering numbering) {
    final label = numbering.captionLabel(block.blockId);
    if (label == null) return null;
    final caption = block.style?['caption'] as String?;
    final text = caption == null || caption.isEmpty
        ? label
        : '$label: $caption';
    return _escape(text);
  }

  void _writeStyles(
    StringBuffer buf,
    FormLayoutPolicy layout,
    RenderOptions options,
    FormStyleSheet? sheet,
  ) {
    final contentWidth = layout.contentWidth;
    final fontPolicy = layout.fontPolicy;

    buf.writeln('body {');
    buf.writeln('  font-family: ${layout.fontFamily}, sans-serif;');
    buf.writeln('  font-size: ${fontPolicy.bodySize}pt;');
    buf.writeln('  max-width: ${contentWidth}mm;');
    buf.writeln('  margin: 0 auto;');
    // Positioned page box so `style.placement` blocks (absolute) anchor to the
    // paper, not the content height. `min-height` gives a full page even when
    // the content is short, so a bottom-anchored seal sits at the paper bottom
    // (matching the PDF), and `box-sizing` keeps the padding (margins) inside.
    buf.writeln('  position: relative;');
    buf.writeln('  box-sizing: border-box;');
    buf.writeln('  min-height: ${layout.effectivePageHeight}mm;');
    // Optional page frame (official document / certificate outline).
    final opt = options;
    if (opt.pageBorder) {
      buf.writeln('  border: ${opt.pageBorderWidth}pt solid '
          '${sheet?.theme.resolveColor(opt.pageBorderColor) ?? opt.pageBorderColor};');
      if (opt.pageBorderRadius > 0) {
        buf.writeln('  border-radius: ${opt.pageBorderRadius}pt;');
      }
    }
    buf.writeln('  padding: ${layout.margins.top}mm ${layout.margins.right}mm '
        '${layout.margins.bottom}mm ${layout.margins.left}mm;');
    buf.writeln('}');

    buf.writeln('h1, h2, h3, h4, h5, h6 {');
    buf.writeln('  font-size: ${fontPolicy.headingSize}pt;');
    buf.writeln('}');

    buf.writeln('table { border-collapse: collapse; width: 100%; }');
    buf.writeln(
      'th, td { border: 1px solid #ccc; padding: 8px; text-align: left; }',
    );
    buf.writeln('th { background-color: #f5f5f5; }');

    buf.writeln(
      '.grid-row { display: grid; grid-template-columns: repeat(12, 1fr); '
      'gap: 18px; align-items: start; }',
    );

    buf.writeln('.form-field { margin: 8px 0; }');
    buf.writeln(
      '.form-field.unfilled { color: #999; font-style: italic; }',
    );

    if (layout.autoWrap) {
      buf.writeln('p { word-wrap: break-word; }');
    }

    buf.writeln('.watermark {');
    buf.writeln('  position: fixed; top: 50%; left: 50%;');
    buf.writeln('  transform: translate(-50%, -50%) rotate(-45deg);');
    buf.writeln('  font-size: 60pt; color: rgba(0,0,0,0.1);');
    buf.writeln('  pointer-events: none; z-index: 1000;');
    buf.writeln('}');

    // Table of contents + heading numbers.
    buf.writeln('.heading-number { font-variant-numeric: tabular-nums; }');
    buf.writeln('.toc ul { list-style: none; padding-left: 0; }');
    buf.writeln('.toc-title { font-weight: bold; }');
    for (var lvl = 1; lvl <= 6; lvl++) {
      buf.writeln('.toc-level-$lvl { margin-left: ${(lvl - 1) * 1.5}em; }');
    }
  }

  void _renderBlock(
    StringBuffer buf,
    FormBlock block,
    Map<String, dynamic> data,
    FormStyleSheet? sheet,
    DocumentNumbering numbering,
    FootnoteCollector footnotes,
  ) {
    switch (block) {
      case FormTextBlock():
        if (block.style?['math'] == true) {
          buf.writeln('<div class="math-display">'
              '${mathToMathml(parseMath(block.content), display: true)}</div>');
          break;
        }
        if (block.style?['toc'] == true) {
          buf.writeln('<nav class="toc">');
          final title = block.content.trim();
          if (title.isNotEmpty) {
            buf.writeln('<p class="toc-title">${_escape(title)}</p>');
          }
          buf.writeln('<ul>');
          for (final e in numbering.tocEntries) {
            final prefix = e.number.isEmpty ? '' : '${_escape(e.number)} ';
            buf.writeln('<li class="toc-level-${e.level}">'
                '<a href="#${_escape(e.blockId)}">$prefix${_escape(e.text)}</a>'
                '</li>');
          }
          buf.writeln('</ul>');
          buf.writeln('</nav>');
          break;
        }
        final listStyle = block.style?['listStyle'] as String?;
        if (isListStyle(listStyle)) {
          final tag = listStyle == 'ordered' ? 'ol' : 'ul';
          final css = _listCss(listStyle, block.style?['numberFormat'] as String?);
          buf.writeln('<$tag$css>');
          for (final raw in block.content.split('\n')) {
            if (raw.trim().isEmpty) continue;
            final item = _inlineRunsHtml(
              FormRichText.parse(
                  footnotes.consume(applyCrossRefs(raw, numbering)),
                  format: block.format),
              sheet,
            );
            buf.writeln('<li>$item</li>');
          }
          buf.writeln('</$tag>');
          break;
        }
        final inner = _redlineWrap(
          _inlineWithMath(
            footnotes.consume(applyCrossRefs(block.content, numbering)),
            block.format,
            sheet,
          ),
          block.style?['change'] as String?,
        );
        final style = _blockStyleAttr(block.style, sheet);
        buf.writeln('<p$style>$inner</p>');

      case FormHeadingBlock():
        final level = block.level.clamp(1, 6);
        final number = numbering.headingNumber(block.blockId);
        final text = footnotes.consume(applyCrossRefs(block.content, numbering));
        final inner = _inlineRunsHtml(FormRichText.plain(text), sheet);
        final prefix = number != null
            ? '<span class="heading-number">$number</span> '
            : '';
        final style = _blockStyleAttr(block.style, sheet);
        final id = _escape(block.blockId);
        buf.writeln('<h$level id="$id"$style>$prefix$inner</h$level>');

      case FormTableBlock():
        buf.writeln('<table>');
        final tCap = _captionHtml(block, numbering);
        if (tCap != null) buf.writeln('<caption>$tCap</caption>');
        buf.writeln('<thead><tr>');
        for (final col in block.columns) {
          buf.writeln('<th>${_escape(col.title)}</th>');
        }
        buf.writeln('</tr></thead>');
        buf.writeln('<tbody>');
        for (final row in block.rows) {
          buf.writeln('<tr>');
          for (final col in block.columns) {
            final cell = row.cells[col.id];
            buf.writeln('<td>${_escape(cell?.toString() ?? '')}</td>');
          }
          buf.writeln('</tr>');
        }
        buf.writeln('</tbody>');
        buf.writeln('</table>');

      case FormImageBlock():
        buf.writeln('<figure>');
        if (isQrSrc(block.src)) {
          buf.writeln(_qrSvg(block));
        } else if (isBarcodeSrc(block.src)) {
          buf.writeln(_barcodeSvg(block));
        } else {
          buf.write('<img src="${_escape(block.src)}"');
          if (block.alt != null) buf.write(' alt="${_escape(block.alt!)}"');
          if (block.maxWidth != null) {
            buf.write(' style="max-width: ${block.maxWidth}px"');
          }
          buf.writeln('>');
        }
        final iCap = _captionHtml(block, numbering);
        if (iCap != null) buf.writeln('<figcaption>$iCap</figcaption>');
        buf.writeln('</figure>');

      case FormChartBlock():
        buf.writeln(
          '<figure class="chart" data-type="${_escape(block.chartType)}">',
        );
        buf.writeln(_chartSvg(block));
        final cCap = _captionHtml(block, numbering);
        if (cCap != null) buf.writeln('<figcaption>$cCap</figcaption>');
        buf.writeln('</figure>');

      case FormCanvasBlock():
        // Scene-live embed. Prefer inline SVG when the resolver pre-
        // injected one under `data[block.blockId]` as a
        // CanvasRenderResult-shaped Map; otherwise emit a placeholder
        // with the target URI for downstream resolution.
        buf.writeln(
          '<figure class="canvas" data-target="${_escape(block.target)}" data-mode="${_escape(block.mode)}">',
        );
        final resolved = data[block.blockId];
        if (resolved is Map && resolved['format'] == 'svg' && resolved['svg'] is String) {
          buf.writeln(resolved['svg'] as String);
        } else if (resolved is Map && resolved['format'] == 'png' && resolved['bytes'] is List) {
          // byte-encoded preview omitted in minimal stub — fall through to
          // the <img> placeholder with the resolver URI.
          buf.writeln('<img src="${_escape(block.target)}" alt="${_escape(block.alt ?? block.target)}">');
        } else {
          buf.writeln(
            '<div class="canvas-placeholder"><code>${_escape(block.target)}</code></div>',
          );
        }
        if (block.caption != null) {
          buf.writeln('<figcaption>${_escape(block.caption!)}</figcaption>');
        }
        buf.writeln('</figure>');

      case FormFieldBlock():
        final value = data[block.fieldName];
        final filled = value != null;
        final cssClass = filled ? 'form-field' : 'form-field unfilled';
        buf.writeln('<div class="$cssClass">');
        buf.writeln(
          '<strong>${_escape(block.fieldName)}</strong>: ',
        );
        buf.writeln(filled ? _escape(value.toString()) : '<em>unfilled</em>');
        buf.writeln('</div>');

      case FormRepeatableBlock():
        buf.writeln('<div class="repeatable">');
        for (final item in resolveRepeatableItems(block, data)) {
          for (final tplBlock in block.itemTemplate) {
            _renderBlock(buf, tplBlock, item, sheet, numbering, footnotes);
          }
        }
        buf.writeln('</div>');

      case FormConditionalBlock():
        if (evaluateCondition(block.condition, data)) {
          _renderBlock(buf, block.thenBlock, data, sheet, numbering, footnotes);
        } else if (block.elseBlock != null) {
          _renderBlock(buf, block.elseBlock!, data, sheet, numbering, footnotes);
        }

      default:
        break;
    }
  }

  /// Emit theme-derived CSS: body/heading fonts and named-style classes.
  void _writeThemeStyles(StringBuffer buf, FormStyleSheet sheet) {
    final theme = sheet.theme;
    if (theme.baseFontSize != null) {
      buf.writeln('body { font-size: ${theme.baseFontSize}pt; }');
    }
    if (theme.bodyFont != null) {
      buf.writeln('body { font-family: ${theme.bodyFont}, sans-serif; }');
    }
    if (theme.logo != null) {
      final w = theme.logoWidth ?? 120;
      buf.writeln('.logo { display: block; width: ${w}px; margin-bottom: 12px; }');
    }
    if (theme.headingFont != null) {
      buf.writeln(
          'h1,h2,h3,h4,h5,h6 { font-family: ${theme.headingFont}, sans-serif; }');
    }
    sheet.styles.forEach((name, style) {
      final css = _blockCss(style, theme);
      if (css.isNotEmpty) buf.writeln('.style-${_escape(name)} { $css }');
    });
  }

  /// Build the `style`/`class` attributes for a block from its explicit style
  /// map (resolved defaults are left to CSS, so unstyled blocks stay clean).
  String _blockStyleAttr(Map<String, dynamic>? raw, FormStyleSheet? sheet) {
    final inline = BlockStyle.fromMap(raw);
    final named = sheet?.named(inline.styleRef);
    final box = (named ?? BlockStyle.empty).merge(inline);
    final theme = sheet?.theme ?? FormTheme.empty;
    final css = _blockCss(box, theme);
    final cls = inline.styleRef != null
        ? ' class="style-${_escape(inline.styleRef!)}"'
        : '';
    final style = css.isEmpty ? '' : ' style="${_escape(css)}"';
    return '$cls$style';
  }

  /// Translate a [BlockStyle] into a CSS declaration list.
  String _blockCss(BlockStyle box, FormTheme theme) {
    final out = <String>[];
    if (box.align != null) out.add('text-align: ${box.align!.token}');
    final t = box.text;
    if (t.color != null) out.add('color: ${theme.resolveColor(t.color!)}');
    if (t.fontFamily != null) out.add('font-family: ${t.fontFamily}');
    if (t.fontSize != null) out.add('font-size: ${t.fontSize}pt');
    if (t.bold == true) out.add('font-weight: bold');
    if (t.italic == true) out.add('font-style: italic');
    if (box.background != null) {
      out.add('background-color: ${theme.resolveColor(box.background!)}');
    }
    if (box.lineHeight != null) out.add('line-height: ${box.lineHeight}');
    if (box.indent != null) out.add('padding-left: ${box.indent}pt');
    if (box.padding != null) out.add('padding: ${box.padding}pt');
    if (box.spaceBefore != null) out.add('margin-top: ${box.spaceBefore}pt');
    if (box.spaceAfter != null) out.add('margin-bottom: ${box.spaceAfter}pt');
    final b = box.border;
    if (b != null) {
      out.add('border: ${b.width}pt solid ${theme.resolveColor(b.color)}');
      if (b.radius != 0) out.add('border-radius: ${b.radius}pt');
      // Keep a bordered box together where the browser can.
      out.add('break-inside: auto');
    }
    return out.isEmpty ? '' : '${out.join('; ')};';
  }

  /// Render rich inline runs to HTML — plain unstyled runs emit bare escaped
  /// text (no span) so simple content stays clean and safe.
  String _inlineRunsHtml(FormRichText rich, FormStyleSheet? sheet) {
    final theme = sheet?.theme ?? FormTheme.empty;
    final b = StringBuffer();
    for (final run in rich.runs) {
      final text = _escape(run.text).replaceAll('\n', '<br>');
      final s = run.style;
      if (s.isEmpty) {
        b.write(text);
        continue;
      }
      var inner = text;
      if (s.baseline == RunBaseline.superscript) inner = '<sup>$inner</sup>';
      if (s.baseline == RunBaseline.subscript) inner = '<sub>$inner</sub>';
      final css = _runCss(s, theme);
      if (s.link != null) {
        final styleAttr = css.isEmpty ? '' : ' style="${_escape(css)}"';
        b.write('<a href="${_escape(s.link!)}"$styleAttr>$inner</a>');
      } else if (css.isNotEmpty) {
        b.write('<span style="${_escape(css)}">$inner</span>');
      } else {
        b.write(inner);
      }
    }
    return b.toString();
  }

  /// Translate a run's marks into a CSS declaration list (baseline/link handled
  /// by the caller).
  String _runCss(TextRunStyle s, FormTheme theme) {
    final out = <String>[];
    if (s.bold == true) out.add('font-weight: bold');
    if (s.italic == true) out.add('font-style: italic');
    final deco = <String>[];
    if (s.underline == true) deco.add('underline');
    if (s.strike == true) deco.add('line-through');
    if (deco.isNotEmpty) out.add('text-decoration: ${deco.join(' ')}');
    if (s.color != null) out.add('color: ${theme.resolveColor(s.color!)}');
    if (s.highlight != null) {
      out.add('background-color: ${theme.resolveColor(s.highlight!)}');
    }
    if (s.fontFamily != null) out.add('font-family: ${s.fontFamily}');
    if (s.fontSize != null) out.add('font-size: ${s.fontSize}pt');
    if (s.letterSpacing != null) out.add('letter-spacing: ${s.letterSpacing}pt');
    return out.join('; ');
  }

  String _escape(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  /// Render a chart block as inline SVG using the shared geometry.
  /// Build a paragraph's inner HTML, turning inline `$…$` math into MathML and
  /// the surrounding text into rich runs. Text with no math takes the plain
  /// rich-run path unchanged.
  String _inlineWithMath(String content, String format, FormStyleSheet? sheet) {
    if (!content.contains(r'$')) {
      return _inlineRunsHtml(
          FormRichText.parse(content, format: format), sheet);
    }
    final buf = StringBuffer();
    var last = 0;
    for (final m in inlineMathToken.allMatches(content)) {
      if (m.start > last) {
        buf.write(_inlineRunsHtml(
            FormRichText.parse(content.substring(last, m.start),
                format: format),
            sheet));
      }
      buf.write(mathToMathml(parseMath(m.group(1)!), display: false));
      last = m.end;
    }
    if (last < content.length) {
      buf.write(_inlineRunsHtml(
          FormRichText.parse(content.substring(last).replaceAll(r'\$', r'$'),
              format: format),
          sheet));
    }
    return buf.toString();
  }

  /// Wrap redline content in a semantic `<ins>` / `<del>` element (the browser
  /// underlines / strikes them); unchanged content passes through.
  String _redlineWrap(String inner, String? change) {
    final deco = redlineDecoration(change);
    if (deco == null) return inner;
    final tag = change == 'deleted' ? 'del' : 'ins';
    return '<$tag style="color: ${deco.color}">$inner</$tag>';
  }

  /// Render a `qr:` image block as an SVG grid of black modules.
  String _qrSvg(FormImageBlock block) {
    final qr = encodeQr(qrData(block.src));
    const unit = 4.0; // px per module
    const quiet = 4;
    final side = (qr.size + 2 * quiet) * unit;
    final rects = StringBuffer();
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
        final x = (quiet + col) * unit;
        final y = (quiet + row) * unit;
        rects.write('<rect x="${x.toStringAsFixed(0)}" '
            'y="${y.toStringAsFixed(0)}" '
            'width="${(run * unit).toStringAsFixed(0)}" '
            'height="${unit.toStringAsFixed(0)}" fill="#000"/>');
        col += run;
      }
    }
    final s = side.toStringAsFixed(0);
    return '<svg class="qr" xmlns="http://www.w3.org/2000/svg" '
        'width="$s" height="$s" viewBox="0 0 $s $s">'
        '<rect width="$s" height="$s" fill="#fff"/>$rects</svg>';
  }

  /// Render a `barcode:` image block as an inline SVG of black bars.
  String _barcodeSvg(FormImageBlock block) {
    final code = encodeCode128B(barcodeData(block.src));
    const unit = 2.0; // px per module
    final barH = block.style?['height'] is num
        ? (block.style!['height'] as num).toDouble()
        : 60.0;
    const quiet = 10 * unit;
    final totalW = (code.width * unit) + 2 * quiet;
    final rects = StringBuffer();
    var x = quiet;
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
      rects.write('<rect x="${x.toStringAsFixed(1)}" y="0" '
          'width="${(run * unit).toStringAsFixed(1)}" height="$barH" '
          'fill="#000"/>');
      x += run * unit;
    }
    return '<svg class="barcode" xmlns="http://www.w3.org/2000/svg" '
        'width="${totalW.toStringAsFixed(1)}" height="$barH" '
        'viewBox="0 0 ${totalW.toStringAsFixed(1)} $barH">'
        '<rect width="${totalW.toStringAsFixed(1)}" height="$barH" fill="#fff"/>'
        '$rects</svg>';
  }

  String _chartSvg(FormChartBlock block) {
    const w = 480.0, h = 280.0;
    final geo = buildChartGeometry(block, width: w, height: h);
    String col(RgbColor c) =>
        'rgb(${(c.r * 255).round()},${(c.g * 255).round()},${(c.b * 255).round()})';
    String n(double v) => v.toStringAsFixed(2);
    final b = StringBuffer();
    b.writeln('<svg viewBox="0 0 ${n(w)} ${n(h)}" '
        'class="chart-svg" role="img" preserveAspectRatio="xMidYMid meet" '
        'xmlns="http://www.w3.org/2000/svg">');
    if (block.title != null && block.title!.isNotEmpty) {
      b.writeln('<title>${_escape(block.title!)}</title>');
    }
    for (final r in geo.rects) {
      b.writeln('<rect x="${n(r.x)}" y="${n(r.y)}" width="${n(r.w)}" '
          'height="${n(r.h)}" fill="${col(r.color)}"/>');
    }
    for (final wge in geo.wedges) {
      final x0 = wge.cx + math.cos(wge.startRad) * wge.r;
      final y0 = wge.cy + math.sin(wge.startRad) * wge.r;
      final end = wge.startRad + wge.sweepRad;
      final x1 = wge.cx + math.cos(end) * wge.r;
      final y1 = wge.cy + math.sin(end) * wge.r;
      final large = wge.sweepRad > math.pi ? 1 : 0;
      b.writeln('<path d="M ${n(wge.cx)} ${n(wge.cy)} L ${n(x0)} ${n(y0)} '
          'A ${n(wge.r)} ${n(wge.r)} 0 $large 1 ${n(x1)} ${n(y1)} Z" '
          'fill="${col(wge.color)}"/>');
    }
    for (final pl in geo.polylines) {
      final pts = pl.points.map((p) => '${n(p.x)},${n(p.y)}').join(' ');
      b.writeln('<polyline points="$pts" fill="none" '
          'stroke="${col(pl.color)}" stroke-width="${n(pl.width)}"/>');
    }
    for (final s in geo.segments) {
      b.writeln('<line x1="${n(s.x1)}" y1="${n(s.y1)}" x2="${n(s.x2)}" '
          'y2="${n(s.y2)}" stroke="${col(s.color)}" '
          'stroke-width="${n(s.width)}"/>');
    }
    for (final t in geo.texts) {
      final anchor = t.anchor == ChartAnchor.middle
          ? 'middle'
          : t.anchor == ChartAnchor.end
              ? 'end'
              : 'start';
      b.writeln('<text x="${n(t.x)}" y="${n(t.y)}" font-size="${n(t.size)}" '
          'text-anchor="$anchor" fill="${col(t.color)}">'
          '${_escape(t.text)}</text>');
    }
    b.write('</svg>');
    return b.toString();
  }
}
