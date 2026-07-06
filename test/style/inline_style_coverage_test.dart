import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

void main() {
  group('FormRichText.parse — runs / markdown / html', () {
    test('runs format parses a JSON array of run objects and strings', () {
      final rt = FormRichText.parse(
        '[{"text":"Hi","bold":true},"plain",42]',
        format: 'runs',
      );
      expect(rt.plainText, 'Hiplain');
      expect(rt.runs.first.style.bold, isTrue);
    });

    test('runs format falls back to plain on a non-list or malformed JSON', () {
      expect(FormRichText.parse('{"x":1}', format: 'runs').plainText, '{"x":1}');
      expect(FormRichText.parse('not json', format: 'runs').plainText,
          'not json');
    });

    test('markdown inline handles escapes and inline code', () {
      final esc = FormRichText.parse(r'a\*b', format: 'markdown');
      expect(esc.plainText, 'a*b');
      final code = FormRichText.parse('a `x` b', format: 'markdown');
      expect(code.runs.any((r) => r.style.fontFamily == 'monospace'), isTrue);
    });

    test('html inline: links, quoted attrs, style attr, entities', () {
      final link = FormRichText.parse('<a href="u">t</a>tail', format: 'html');
      expect(link.runs.any((r) => r.style.link == 'u'), isTrue);
      expect(link.plainText, contains('tail'));

      final sq = FormRichText.parse("<a href='v'>t</a>", format: 'html');
      expect(sq.runs.any((r) => r.style.link == 'v'), isTrue);

      final styled = FormRichText.parse(
        '<span style="background:yellow; font-weight:bold; '
        'font-family:Arial,sans-serif; text-decoration:line-through">z</span>',
        format: 'html',
      );
      final s = styled.runs.first.style;
      expect(s.strike, isTrue);
      expect(s.fontFamily, 'Arial');

      final ent = FormRichText.parse('&#65;', format: 'html');
      expect(ent.plainText, 'A');
    });

    test('InlineRun.withStyle and FormRichText.isEmpty', () {
      final run = const InlineRun('a').withStyle(const TextRunStyle(bold: true));
      expect(run.style.bold, isTrue);
      expect(FormRichText(const [InlineRun('')]).isEmpty, isTrue);
    });
  });

  group('TextRunStyle equality, hashCode and baseline tokens', () {
    test('RunBaseline.token', () {
      expect(RunBaseline.superscript.token, 'super');
      expect(RunBaseline.subscript.token, 'sub');
      expect(RunBaseline.normal.token, 'normal');
    });

    test('== and hashCode', () {
      const a = TextRunStyle(bold: true, color: '#111', baseline: RunBaseline.superscript);
      const b = TextRunStyle(bold: true, color: '#111', baseline: RunBaseline.superscript);
      const c = TextRunStyle(bold: false);
      expect(a, equals(b));
      expect(a == c, isFalse);
      expect(a.hashCode, b.hashCode);
    });
  });
}
