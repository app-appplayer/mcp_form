import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/mcp_form.dart';
import 'package:test/test.dart';

/// Build a heading block, opting into numbering by default.
FormHeadingBlock _h(String id, int level, String text,
        {bool numbering = true, String? label}) =>
    FormHeadingBlock(
      blockId: id,
      index: 0,
      content: text,
      level: level,
      numbering: numbering,
      style: label == null ? null : {'label': label},
    );

FormSection _sec(List<FormBlock> blocks) =>
    FormSection(sectionId: 's', index: 0, blocks: blocks);

void main() {
  group('DocumentNumbering.compute — heading numbers', () {
    test('assigns hierarchical numbers respecting level', () {
      final n = DocumentNumbering.compute([
        _sec([
          _h('a', 1, 'Intro'),
          _h('b', 2, 'Background'),
          _h('c', 2, 'Scope'),
          _h('d', 1, 'Method'),
          _h('e', 2, 'Setup'),
          _h('f', 3, 'Detail'),
        ]),
      ]);
      expect(n.headingNumber('a'), '1');
      expect(n.headingNumber('b'), '1.1');
      expect(n.headingNumber('c'), '1.2');
      expect(n.headingNumber('d'), '2');
      expect(n.headingNumber('e'), '2.1');
      expect(n.headingNumber('f'), '2.1.1');
    });

    test('deeper counters reset when a shallower level advances', () {
      final n = DocumentNumbering.compute([
        _sec([
          _h('a', 1, 'One'),
          _h('b', 3, 'Deep'), // 1.0.1 -> joins as "1.0.1"? no: counters[0]=1
          _h('c', 1, 'Two'),
          _h('d', 2, 'Sub'),
        ]),
      ]);
      // After "Two" (level 1), the level-2/3 counters reset, so "Sub" is 2.1.
      expect(n.headingNumber('c'), '2');
      expect(n.headingNumber('d'), '2.1');
    });

    test('unnumbered headings get no number but still appear in TOC', () {
      final n = DocumentNumbering.compute([
        _sec([
          _h('a', 1, 'Numbered'),
          _h('b', 1, 'Plain', numbering: false),
          _h('c', 1, 'Numbered2'),
        ]),
      ]);
      expect(n.headingNumber('a'), '1');
      expect(n.headingNumber('b'), isNull);
      // Counter is not consumed by the unnumbered heading.
      expect(n.headingNumber('c'), '2');
      expect(n.tocEntries.map((e) => e.text),
          ['Numbered', 'Plain', 'Numbered2']);
      expect(n.tocEntries[1].number, '');
    });

    test('isEmpty when no numbered headings or captions', () {
      final n = DocumentNumbering.compute([
        _sec([_h('a', 1, 'Plain', numbering: false)]),
      ]);
      expect(n.isEmpty, isTrue);
    });
  });

  group('DocumentNumbering — captions and cross-references', () {
    test('numbers figures and tables independently', () {
      final n = DocumentNumbering.compute([
        _sec([
          FormImageBlock(
              blockId: 'img1', index: 0, src: 'a.png', style: {'caption': 'A'}),
          FormTableBlock(
              blockId: 'tbl1',
              index: 1,
              columns: const [],
              rows: const [],
              style: {'caption': 'T'}),
          FormImageBlock(
              blockId: 'img2', index: 2, src: 'b.png', style: {'caption': 'B'}),
        ]),
      ]);
      expect(n.captionLabel('img1'), 'Figure 1');
      expect(n.captionLabel('tbl1'), 'Table 1');
      expect(n.captionLabel('img2'), 'Figure 2');
    });

    test('captionPrefix overrides the default kind label', () {
      final n = DocumentNumbering.compute([
        _sec([
          FormImageBlock(
              blockId: 'img1',
              index: 0,
              src: 'a.png',
              style: {'caption': 'A', 'captionPrefix': 'Diagram'}),
        ]),
      ]);
      expect(n.captionLabel('img1'), 'Diagram 1');
    });

    test('resolveRef maps a label to its heading or caption number', () {
      final n = DocumentNumbering.compute([
        _sec([
          _h('a', 1, 'Intro', label: 'intro'),
          _h('b', 2, 'Detail', label: 'detail'),
          FormImageBlock(
              blockId: 'img1',
              index: 0,
              src: 'a.png',
              style: {'caption': 'A', 'label': 'fig-a'}),
        ]),
      ]);
      expect(n.resolveRef('intro'), '1');
      expect(n.resolveRef('detail'), '1.1');
      expect(n.resolveRef('fig-a'), 'Figure 1');
      expect(n.resolveRef('missing'), isNull);
    });

    test('applyCrossRefs replaces [ref:label]; unknown marked with ?', () {
      final n = DocumentNumbering.compute([
        _sec([_h('a', 1, 'Intro', label: 'intro')]),
      ]);
      expect(applyCrossRefs('See section [ref:intro] above.', n),
          'See section 1 above.');
      expect(applyCrossRefs('See [ref:nope].', n), 'See [ref:nope]?.');
      expect(applyCrossRefs('no tokens here', n), 'no tokens here');
    });
  });

  group('renderers consume heading numbering', () {
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
        _sec([
          _h('a', 1, 'Overview', label: 'ov'),
          _h('b', 2, 'Goals'),
          FormTextBlock(
              blockId: 't1', index: 2, content: 'Back to [ref:ov] please.'),
        ]),
      ],
      metadata: FormDocumentMetadata(author: 'x', createdAt: DateTime(2026)),
    );

    final ctx = RenderContext(
      document: doc,
      layoutPolicy: layout,
      template: tpl,
      // Uncompressed so the PDF assertion can read literal text runs.
      options: const RenderOptions(compress: false),
    );

    test('markdown prefixes heading numbers and resolves refs', () async {
      final out = await const MarkdownRenderer().render(ctx);
      final md = utf8.decode(out.content as List<int>);
      expect(md, contains('# 1 Overview'));
      expect(md, contains('## 1.1 Goals'));
      expect(md, contains('Back to 1 please.'));
    });

    test('html prefixes heading numbers in a numbered span', () async {
      final out = await const HtmlRenderer().render(ctx);
      final html = utf8.decode(out.content as List<int>);
      expect(html, contains('<span class="heading-number">1</span>'));
      expect(html, contains('id="a"'));
      expect(html, contains('Back to 1 please.'));
    });

    test('pdf embeds the numbered heading text', () async {
      final out = await const PdfRenderer().render(ctx);
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      // The heading number prefixes the title in one drawn run. The PDF text
      // encoder emits the joining spaces as octal-escaped non-breaking spaces.
      expect(pdf, contains(r'1\240\240Overview'));
    });
  });

  group('footnotes ([fn:...] endnotes)', () {
    test('FootnoteCollector numbers sequentially and collects bodies', () {
      final fc = FootnoteCollector();
      expect(fc.consume('See here[fn:first note] and there[fn:second note].'),
          'See here[1] and there[2].');
      expect(fc.consume('plain text'), 'plain text');
      expect(fc.consume('again[fn:third].'), 'again[3].');
      expect(fc.notes, ['first note', 'second note', 'third']);
      expect(fc.isEmpty, isFalse);
    });

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
        _sec([
          FormTextBlock(
              blockId: 'p1',
              index: 0,
              content: 'A claim[fn:Smith 2020] and another[fn:Jones 2021].'),
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

    test('html replaces markers and emits a footnotes ordered list', () async {
      final out = await const HtmlRenderer().render(ctx());
      final html = utf8.decode(out.content as List<int>);
      expect(html, contains('A claim[1] and another[2].'));
      expect(html, contains('<section class="footnotes">'));
      expect(html, contains('<li>Smith 2020</li>'));
      expect(html, contains('<li>Jones 2021</li>'));
    });

    test('markdown appends a Notes section', () async {
      final out = await const MarkdownRenderer().render(ctx());
      final md = utf8.decode(out.content as List<int>);
      expect(md, contains('A claim[1] and another[2].'));
      expect(md, contains('**Notes**'));
      expect(md, contains('1. Smith 2020'));
      expect(md, contains('2. Jones 2021'));
    });

    test('pdf draws inline markers and a Notes section', () async {
      final out = await const PdfRenderer().render(ctx(compress: false));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      expect(pdf, contains('Notes'));
      expect(pdf, contains('1. Smith 2020'));
    });

    test('ui dsl appends a Footnotes node', () async {
      final out = await const UiDslRenderer().render(ctx());
      final dsl = jsonDecode(utf8.decode(out.content as List<int>))
          as Map<String, dynamic>;
      final body = dsl['body'] as Map<String, dynamic>;
      final children = body['children'] as List;
      final fn = children
          .firstWhere((c) => (c as Map)['type'] == 'Footnotes') as Map;
      final notes = fn['notes'] as List;
      expect(notes.length, 2);
      expect((notes.first as Map)['text'], 'Smith 2020');
      expect((notes.first as Map)['number'], 1);
    });
  });

  group('caption rendering (style.caption)', () {
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
        _sec([
          FormImageBlock(
              blockId: 'img1',
              index: 0,
              src: 'a.png',
              style: const {'caption': 'A photo', 'label': 'img1'}),
          FormTableBlock(
              blockId: 'tbl1',
              index: 1,
              columns: const [
                FormTableColumn(id: 'c', title: 'Col', type: 'string')
              ],
              rows: const [],
              style: const {'caption': 'A table'}),
          FormTextBlock(
              blockId: 't1', index: 2, content: 'As shown in [ref:img1].'),
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

    test('html emits figcaption and table caption with auto numbers', () async {
      final out = await const HtmlRenderer().render(ctx());
      final html = utf8.decode(out.content as List<int>);
      expect(html, contains('<figcaption>Figure 1: A photo</figcaption>'));
      expect(html, contains('<caption>Table 1: A table</caption>'));
    });

    test('markdown emits italic captions', () async {
      final out = await const MarkdownRenderer().render(ctx());
      final md = utf8.decode(out.content as List<int>);
      expect(md, contains('*Figure 1: A photo*'));
      expect(md, contains('*Table 1: A table*'));
    });

    test('pdf draws the caption text', () async {
      final out = await const PdfRenderer().render(ctx(compress: false));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      expect(pdf, contains('Figure 1: A photo'));
      expect(pdf, contains('Table 1: A table'));
    });

    test('caption labels resolve as cross-references', () async {
      final out = await const MarkdownRenderer().render(ctx());
      final md = utf8.decode(out.content as List<int>);
      // The image carries label 'img1' -> "Figure 1".
      expect(md, contains('As shown in Figure 1.'));
    });
  });

  group('table of contents (style.toc)', () {
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
        _sec([
          FormTextBlock(
              blockId: 'toc',
              index: 0,
              content: 'Contents',
              style: const {'toc': true}),
          _h('a', 1, 'Overview'),
          _h('b', 2, 'Goals'),
          _h('c', 1, 'Method'),
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

    test('html emits a nav.toc with anchor links to heading ids', () async {
      final out = await const HtmlRenderer().render(ctx());
      final html = utf8.decode(out.content as List<int>);
      expect(html, contains('<nav class="toc">'));
      expect(html, contains('<p class="toc-title">Contents</p>'));
      expect(html, contains('<a href="#a">1 Overview</a>'));
      expect(html, contains('<a href="#b">1.1 Goals</a>'));
      expect(html, contains('<a href="#c">2 Method</a>'));
    });

    test('markdown emits an indented outline list', () async {
      final out = await const MarkdownRenderer().render(ctx());
      final md = utf8.decode(out.content as List<int>);
      expect(md, contains('**Contents**'));
      expect(md, contains('- 1 Overview'));
      expect(md, contains('  - 1.1 Goals'));
      expect(md, contains('- 2 Method'));
    });

    test('pdf draws the title and numbered entries', () async {
      final out = await const PdfRenderer().render(ctx(compress: false));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      expect(pdf, contains('Contents'));
      // Entry "1  Overview" — joining spaces are octal-escaped NBSP.
      expect(pdf, contains(r'1\240\240Overview'));
      expect(pdf, contains(r'1.1\240\240Goals'));
    });

    test('pdf draws right-aligned page numbers resolving across pages',
        () async {
      // TOC, a heading on page 1, enough filler to push a second heading to a
      // later page, then that heading.
      final filler = [
        for (var i = 0; i < 80; i++)
          FormTextBlock(
              blockId: 'f$i',
              index: i + 2,
              content: 'Filler line $i lorem ipsum dolor sit amet.'),
      ];
      final big = FormDocument(
        documentId: 'd',
        templateId: 't',
        templateVersion: '1.0.0',
        data: const {},
        sections: [
          _sec([
            FormTextBlock(
                blockId: 'toc',
                index: 0,
                content: 'Contents',
                style: const {'toc': true}),
            _h('a', 1, 'First'),
            ...filler,
            _h('z', 1, 'Second'),
          ]),
        ],
        metadata: FormDocumentMetadata(author: 'x', createdAt: DateTime(2026)),
      );
      final out = await const PdfRenderer().render(RenderContext(
        document: big,
        layoutPolicy: layout,
        template: tpl,
        options: const RenderOptions(compress: false),
      ));
      expect(out.pageCount, greaterThan(1));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      // Right-aligned page-number runs: a Td at a large x followed by (N) Tj.
      final re = RegExp(r'5[0-9][0-9]\.[0-9]+ 7[0-9][0-9]\.[0-9]+ Td\n'
          r'\(([0-9]+)\) Tj');
      final nums = re.allMatches(pdf).map((m) => int.parse(m.group(1)!)).toList();
      expect(nums, contains(1)); // "First" is on page 1
      expect(nums.any((n) => n > 1), isTrue); // "Second" is on a later page
      expect(nums.reduce((a, b) => a > b ? a : b), out.pageCount);
    });

    test('ui dsl emits a TableOfContents node with entries', () async {
      final out = await const UiDslRenderer().render(ctx());
      final dsl = jsonDecode(utf8.decode(out.content as List<int>))
          as Map<String, dynamic>;
      final body = dsl['body'] as Map<String, dynamic>;
      final section = (body['children'] as List).first as Map<String, dynamic>;
      final children = section['children'] as List;
      final toc = children.firstWhere(
          (c) => (c as Map)['type'] == 'TableOfContents') as Map<String, dynamic>;
      expect(toc['title'], 'Contents');
      final entries = toc['entries'] as List;
      expect(entries.length, 3);
      expect((entries.first as Map)['number'], '1');
      expect((entries.first as Map)['target'], 'a');
      expect((entries[1] as Map)['number'], '1.1');
    });
  });
}
