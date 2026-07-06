import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

void main() {
  group('measureText', () {
    test('wider glyphs measure wider', () {
      expect(measureText('m', 12), greaterThan(measureText('i', 12)));
    });
    test('empty string is zero', () {
      expect(measureText('', 12), 0);
    });
    test('bold can differ from regular', () {
      expect(measureText('f', 12, bold: true),
          greaterThan(measureText('f', 12)));
    });
    test('letterSpacing adds width', () {
      expect(measureText('abc', 12, letterSpacing: 2),
          greaterThan(measureText('abc', 12)));
    });
  });

  group('TextRunStyle', () {
    test('merge overrides non-null fields', () {
      const a = TextRunStyle(bold: true, color: '#111');
      const b = TextRunStyle(color: '#222', italic: true);
      final m = a.merge(b);
      expect(m.bold, true);
      expect(m.italic, true);
      expect(m.color, '#222');
    });
    test('fromMap reads aliases', () {
      final s = TextRunStyle.fromMap(
          {'font': 'Times', 'size': 14, 'bold': true, 'baseline': 'super'});
      expect(s.fontFamily, 'Times');
      expect(s.fontSize, 14);
      expect(s.bold, true);
      expect(s.baseline, RunBaseline.superscript);
    });
    test('empty round-trips to empty map', () {
      expect(TextRunStyle.empty.toMap(), isEmpty);
    });
  });

  group('BlockStyle.fromMap', () {
    test('reads box keys and inline marks', () {
      final b = BlockStyle.fromMap({
        'align': 'center',
        'height': 100,
        'overflow': 'shrink',
        'bold': true,
        'color': '#333',
        'border': {'width': 2, 'color': '#000'},
      });
      expect(b.align, FormTextAlign.center);
      expect(b.height, 100);
      expect(b.overflow, BlockOverflow.shrinkToFit);
      expect(b.text.bold, true);
      expect(b.text.color, '#333');
      expect(b.border!.width, 2);
    });
    test('shorthand border via borderWidth', () {
      final b = BlockStyle.fromMap({'borderWidth': 1.5, 'borderColor': '#abc'});
      expect(b.border, isNotNull);
      expect(b.border!.color, '#abc');
    });
  });

  group('markdown inline', () {
    test('bold / italic / strike / highlight', () {
      final r = parseMarkdownInline('a **b** *c* ~~d~~ ==e==');
      expect(r.runs.any((x) => x.text == 'b' && x.style.bold == true), isTrue);
      expect(r.runs.any((x) => x.text == 'c' && x.style.italic == true), isTrue);
      expect(r.runs.any((x) => x.text == 'd' && x.style.strike == true), isTrue);
      expect(
          r.runs.any((x) => x.text == 'e' && x.style.highlight != null), isTrue);
    });
    test('link', () {
      final r = parseMarkdownInline('see [docs](https://x)');
      final link = r.runs.firstWhere((x) => x.text == 'docs');
      expect(link.style.link, 'https://x');
    });
    test('plainText reconstructs visible text', () {
      expect(parseMarkdownInline('**hi** there').plainText, 'hi there');
    });
  });

  group('html inline', () {
    test('tags map to marks', () {
      final r = parseHtmlInline(
          '<b>x</b><i>y</i><u>z</u><span style="color:#f00">c</span>');
      expect(r.runs.firstWhere((e) => e.text == 'x').style.bold, true);
      expect(r.runs.firstWhere((e) => e.text == 'y').style.italic, true);
      expect(r.runs.firstWhere((e) => e.text == 'z').style.underline, true);
      expect(r.runs.firstWhere((e) => e.text == 'c').style.color, '#f00');
    });
    test('sup / sub / br / entities', () {
      final r = parseHtmlInline('H<sub>2</sub>O&amp;<br>x');
      expect(r.runs.firstWhere((e) => e.text == '2').style.baseline,
          RunBaseline.subscript);
      expect(r.plainText.contains('&'), isTrue);
      expect(r.plainText.contains('\n'), isTrue);
    });
    test('unknown tags are dropped but text kept', () {
      final r = parseHtmlInline('<script>alert(1)</script>ok');
      expect(r.plainText, 'alert(1)ok');
    });
  });

  group('wrapRichText', () {
    test('wraps to multiple lines', () {
      final lines = wrapRichText(
        FormRichText.plain('one two three four five six seven eight nine ten'),
        60,
        const TextRunStyle(fontSize: 12),
      );
      expect(lines.length, greaterThan(1));
    });
    test('forced newline breaks lines', () {
      final lines = wrapRichText(
        FormRichText.plain('a\nb\nc'),
        500,
        const TextRunStyle(fontSize: 12),
      );
      expect(lines.length, 3);
    });

    test('CJK without spaces still wraps (no horizontal overflow)', () {
      const zh = '从同一个模板生成可打印的文档而且这段中文没有任何空格';
      final lines = wrapRichText(
          FormRichText.plain(zh), 80, const TextRunStyle(fontSize: 12));
      expect(lines.length, greaterThan(1));
      for (final l in lines) {
        expect(l.width, lessThanOrEqualTo(80 + 12)); // within one glyph of box
      }
    });

    test('an over-long single word breaks by character', () {
      final lines = wrapRichText(
          FormRichText.plain('supercalifragilisticexpialidocious'),
          60,
          const TextRunStyle(fontSize: 12));
      expect(lines.length, greaterThan(1));
    });
  });

  group('fitText copyfit', () {
    final tall = FormRichText.plain(
        List.generate(40, (i) => 'line $i content here').join('\n'));
    const base = TextRunStyle(fontSize: 12);

    test('grow keeps all lines, flags overflow', () {
      final r = fitText(tall, 300, base,
          maxHeightPt: 50, overflow: BlockOverflow.grow);
      expect(r.overflowed, isTrue);
      expect(r.scale, 1.0);
    });
    test('shrinkToFit reduces scale', () {
      final r = fitText(tall, 300, base,
          maxHeightPt: 80, overflow: BlockOverflow.shrinkToFit, minSize: 4);
      expect(r.scale, lessThan(1.0));
    });
    test('clip drops overflowing lines', () {
      final r = fitText(tall, 300, base,
          maxHeightPt: 50, overflow: BlockOverflow.clip);
      expect(r.droppedLines, greaterThan(0));
      expect(r.lines.length, lessThan(40));
    });
    test('summarize reports a character budget', () {
      final r = fitText(tall, 300, base,
          maxHeightPt: 50, overflow: BlockOverflow.summarize);
      expect(r.targetChars, isNotNull);
      expect(r.targetChars, lessThan(tall.plainText.length));
    });
    test('content that fits is not overflowed', () {
      final r = fitText(FormRichText.plain('short'), 300, base,
          maxHeightPt: 200, overflow: BlockOverflow.clip);
      expect(r.overflowed, isFalse);
    });
  });

  group('FormStyleSheet + resolveStyle', () {
    const layout = FormLayoutPolicy(
      pageSize: FormPageSize(size: 'A4', width: 210, height: 297),
      margins: FormMargins(top: 20, right: 20, bottom: 20, left: 20),
      fontPolicy: FormFontPolicy(
        defaultFont: 'sans-serif',
        defaultSize: 12,
        headingSize: 24,
        bodySize: 12,
        minSize: 8,
      ),
    );

    test('named style resolves and inline overrides it', () {
      final sheet = FormStyleSheet.fromMap({
        'theme': {
          'colors': {'brand': '#0066CC'}
        },
        'styles': {
          'lead': {'size': 30, 'color': 'brand', 'bold': true}
        },
      });
      final rs = resolveStyle(
        blockStyle: {'styleRef': 'lead', 'color': '#FF0000'},
        layout: layout,
        sheet: sheet,
      );
      expect(rs.base.fontSize, 30);
      expect(rs.base.bold, true);
      // inline color overrides the named style's brand colour
      expect(rs.base.color, '#FF0000');
    });

    test('theme colour token resolves to hex', () {
      final sheet = FormStyleSheet.fromMap({
        'theme': {
          'colors': {'brand': '#0066CC'}
        },
      });
      final rs = resolveStyle(
        blockStyle: {'color': 'brand'},
        layout: layout,
        sheet: sheet,
      );
      expect(rs.base.color, '#0066CC');
    });

    test('heading falls back to heading size', () {
      final rs = resolveStyle(
        blockStyle: null,
        layout: layout,
        heading: true,
        headingLevel: 1,
      );
      expect(rs.base.fontSize, greaterThan(layout.fontPolicy.bodySize));
    });
  });

  group('hexToRgb', () {
    test('parses #RRGGBB', () {
      final c = hexToRgb('#FF0000')!;
      expect(c.r, 1.0);
      expect(c.g, 0.0);
    });
    test('parses shorthand #RGB', () {
      final c = hexToRgb('#0F0')!;
      expect(c.g, 1.0);
    });
    test('null on garbage', () {
      expect(hexToRgb('nope'), isNull);
    });
  });
}
