import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/mcp_form.dart';
import 'package:test/test.dart';

void main() {
  group('parseMath + MathML', () {
    test('superscript / subscript become msup / msub', () {
      expect(mathToMathml(parseMath('x^2'), display: false),
          contains('<msup><mi>x</mi><mn>2</mn></msup>'));
      expect(mathToMathml(parseMath('x_i'), display: false),
          contains('<msub><mi>x</mi><mi>i</mi></msub>'));
    });

    test('combined scripts become msubsup', () {
      final ml = mathToMathml(parseMath('x_i^2'), display: false);
      expect(ml, contains('<msubsup><mi>x</mi><mi>i</mi><mn>2</mn></msubsup>'));
    });

    test('\\frac becomes mfrac, \\sqrt becomes msqrt', () {
      expect(mathToMathml(parseMath(r'\frac{a}{b}'), display: false),
          contains('<mfrac><mrow><mi>a</mi></mrow><mrow><mi>b</mi></mrow></mfrac>'));
      expect(mathToMathml(parseMath(r'\sqrt{x}'), display: false),
          contains('<msqrt><mrow><mi>x</mi></mrow></msqrt>'));
    });

    test('named symbols map to Unicode operators', () {
      final ml = mathToMathml(parseMath(r'\alpha + \sum \times'), display: false);
      expect(ml, contains('α')); // Greek letter mapped from \alpha
      expect(ml, contains('<mo>∑</mo>'));
      expect(ml, contains('<mo>×</mo>'));
    });

    test('display flag sets the math mode', () {
      expect(mathToMathml(parseMath('x'), display: true),
          contains('display="block"'));
    });

    test('the quadratic formula parses into nested structure', () {
      final ml =
          mathToMathml(parseMath(r'\frac{-b \pm \sqrt{b^2-4ac}}{2a}'), display: true);
      expect(ml, contains('<mfrac>'));
      expect(ml, contains('<msqrt>'));
      expect(ml, contains('<mo>±</mo>'));
      expect(ml, contains('<msup><mi>b</mi><mn>2</mn></msup>'));
    });
  });

  group('inline math (dollar-delimited)', () {
    test('substituteInlineMath renders Unicode super/subscripts', () {
      expect(substituteInlineMath(r'$E=mc^2$'), 'E=mc²');
      expect(substituteInlineMath(r'$x_i$'), 'xᵢ');
    });

    test('symbols and fractions are approximated', () {
      expect(substituteInlineMath(r'$\alpha + \beta$'), 'α+β');
      expect(substituteInlineMath(r'$\frac{1}{2}$'), '1/2');
    });

    test('an escaped dollar is literal, not math', () {
      expect(substituteInlineMath(r'Cost \$5'), r'Cost $5');
    });

    test('text without dollars is unchanged', () {
      expect(substituteInlineMath('plain text'), 'plain text');
    });
  });

  group('renderers handle inline math', () {
    const layout = FormLayoutPolicy(
      pageSize: FormPageSize(size: 'A4', width: 210, height: 297),
      margins: FormMargins(top: 20, right: 20, bottom: 20, left: 20),
      fontPolicy: FormFontPolicy(
        defaultFont: 'sans-serif',
        defaultSize: 12,
        headingSize: 18,
        bodySize: 12,
        minSize: 8,
      ),
    );
    final tpl = FormTemplate(
      templateId: 't',
      version: '1.0.0',
      name: 'T',
      schema: const FormSchema(),
      layoutPolicy: layout,
    );
    final doc = FormDocument(
      documentId: 'd',
      templateId: 't',
      templateVersion: '1.0.0',
      data: const {},
      sections: [
        FormSection(sectionId: 's', index: 0, blocks: [
          FormTextBlock(
              blockId: 'p', index: 0, content: r'The mass energy $E=mc^2$ holds.'),
        ]),
      ],
      metadata: FormDocumentMetadata(author: 'x', createdAt: DateTime(2026)),
    );
    final ctx = RenderContext(
        document: doc, layoutPolicy: layout, template: tpl);

    test('html splits the paragraph and emits inline MathML', () async {
      final out = await const HtmlRenderer().render(ctx);
      final html = utf8.decode(out.content as List<int>);
      expect(html, contains('<math'));
      expect(html, contains('display="inline"'));
      expect(html, contains('The mass energy'));
      expect(html, contains('holds.'));
    });

    test('markdown keeps native dollar math for MathJax', () async {
      final out = await const MarkdownRenderer().render(ctx);
      final md = utf8.decode(out.content as List<int>);
      expect(md, contains(r'$E=mc^2$'));
    });
  });

  group('layoutMath (PDF geometry)', () {
    double measure(String t, double s) => t.length * s * 0.5;

    test('a fraction produces a bar rule', () {
      final laid = layoutMath(parseMath(r'\frac{a}{b}'), 12, measure);
      expect(laid.rules.length, 1);
      expect(laid.height, greaterThan(12)); // taller than a single line
    });

    test('a square root produces an overline rule', () {
      final laid = layoutMath(parseMath(r'\sqrt{x}'), 12, measure);
      expect(laid.rules.length, 1);
      expect(laid.glyphs.any((g) => g.text == '√'), isTrue);
    });

    test('a superscript glyph sits above the base baseline', () {
      final laid = layoutMath(parseMath('x^2'), 12, measure);
      final base = laid.glyphs.firstWhere((g) => g.text == 'x');
      final sup = laid.glyphs.firstWhere((g) => g.text == '2');
      // Smaller baselineTop = higher on the page (top-down coordinates).
      expect(sup.baselineTop, lessThan(base.baselineTop));
      expect(sup.size, lessThan(base.size));
    });
  });

  group('renderers draw display math (style.math)', () {
    const layout = FormLayoutPolicy(
      pageSize: FormPageSize(size: 'A4', width: 210, height: 297),
      margins: FormMargins(top: 20, right: 20, bottom: 20, left: 20),
      fontPolicy: FormFontPolicy(
        defaultFont: 'sans-serif',
        defaultSize: 12,
        headingSize: 18,
        bodySize: 12,
        minSize: 8,
      ),
    );
    final tpl = FormTemplate(
      templateId: 't',
      version: '1.0.0',
      name: 'T',
      schema: const FormSchema(),
      layoutPolicy: layout,
    );
    final doc = FormDocument(
      documentId: 'd',
      templateId: 't',
      templateVersion: '1.0.0',
      data: const {},
      sections: [
        FormSection(sectionId: 's', index: 0, blocks: [
          FormTextBlock(
              blockId: 'eq',
              index: 0,
              content: r'\frac{a}{b} + x^2',
              style: const {'math': true}),
        ]),
      ],
      metadata: FormDocumentMetadata(author: 'x', createdAt: DateTime(2026)),
    );
    RenderContext ctx({bool compress = true}) => RenderContext(
          document: doc,
          layoutPolicy: layout,
          template: tpl,
          options: RenderOptions(compress: compress),
        );

    test('html emits a MathML display block', () async {
      final out = await const HtmlRenderer().render(ctx());
      final html = utf8.decode(out.content as List<int>);
      expect(html, contains('<div class="math-display">'));
      expect(html, contains('<math'));
      expect(html, contains('<mfrac>'));
    });

    test('markdown emits a \$\$ display equation', () async {
      final out = await const MarkdownRenderer().render(ctx());
      final md = utf8.decode(out.content as List<int>);
      expect(md, contains(r'$$\frac{a}{b} + x^2$$'));
    });

    test('pdf draws math glyphs and a fraction rule', () async {
      final out = await const PdfRenderer().render(ctx(compress: false));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      // Fraction bar = a filled black rectangle.
      expect(pdf, contains('0.000 0.000 0.000 rg'));
      expect(pdf, contains('re f'));
    });

    test('ui dsl emits a Math node with mathml', () async {
      final out = await const UiDslRenderer().render(ctx());
      final dsl = jsonDecode(utf8.decode(out.content as List<int>))
          as Map<String, dynamic>;
      final body = dsl['body'] as Map<String, dynamic>;
      final section = (body['children'] as List).first as Map<String, dynamic>;
      final math = (section['children'] as List).first as Map<String, dynamic>;
      expect(math['type'], 'Math');
      expect(math['expression'], r'\frac{a}{b} + x^2');
      expect(math['mathml'], contains('<mfrac>'));
    });
  });
}
