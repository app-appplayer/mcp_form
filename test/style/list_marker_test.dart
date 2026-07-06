import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/html_renderer.dart';
import 'package:mcp_form/src/infra/renderer/renderers/markdown_renderer.dart';
import 'package:mcp_form/src/infra/renderer/renderers/pdf_renderer.dart';
import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

/// Bullet / ordered list rendering driven by `style.listStyle` + `numberFormat`
/// (a render-time feature; mcp_bundle core untouched — the keys already exist on
/// FormBlock.style). Each source line of the block content is one list item.
void main() {
  group('listMarker (format-independent)', () {
    test('bullet glyphs by numberFormat', () {
      expect(listMarker(0, 'bullet', null), '•');
      expect(listMarker(5, 'bullet', 'circle'), '◦');
      expect(listMarker(2, 'bullet', 'square'), '▪');
    });

    test('ordered decimal counts from 1', () {
      expect(listMarker(0, 'ordered', null), '1.');
      expect(listMarker(2, 'ordered', 'decimal'), '3.');
    });

    test('ordered lower/upper alpha', () {
      expect(listMarker(0, 'ordered', 'lower-alpha'), 'a.');
      expect(listMarker(26, 'ordered', 'lower-alpha'), 'aa.');
      expect(listMarker(1, 'ordered', 'upper-alpha'), 'B.');
    });

    test('ordered roman', () {
      expect(listMarker(0, 'ordered', 'lower-roman'), 'i.');
      expect(listMarker(3, 'ordered', 'upper-roman'), 'IV.');
      expect(listMarker(8, 'ordered', 'lower-roman'), 'ix.');
    });

    test('non-list returns empty; isListStyle gates', () {
      expect(listMarker(0, null, null), '');
      expect(isListStyle('bullet'), isTrue);
      expect(isListStyle('ordered'), isTrue);
      expect(isListStyle(null), isFalse);
      expect(isListStyle('paragraph'), isFalse);
    });
  });

  RenderContext ctx(FormTextBlock block) {
    final layout = FormLayoutPolicy(
      pageSize: const FormPageSize(size: 'A4', width: 210, height: 297),
      margins: const FormMargins(top: 20, right: 20, bottom: 20, left: 20),
      fontPolicy: const FormFontPolicy(
        defaultFont: 'x',
        defaultSize: 12,
        headingSize: 18,
        bodySize: 12,
        minSize: 8,
      ),
    );
    return RenderContext(
      document: FormDocument(
        documentId: 'd',
        templateId: 't',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(author: 'a', createdAt: DateTime(2026)),
        sections: [FormSection(sectionId: 's', index: 0, blocks: [block])],
      ),
      layoutPolicy: layout,
      template: FormTemplate(
        templateId: 't',
        version: '1.0.0',
        name: 'T',
        schema: const FormSchema(),
        layoutPolicy: layout,
      ),
      options: const RenderOptions(compress: false),
    );
  }

  FormTextBlock list(String content, String listStyle, {String? numberFormat}) =>
      FormTextBlock(
        blockId: 'l',
        index: 0,
        content: content,
        style: {
          'listStyle': listStyle,
          if (numberFormat != null) 'numberFormat': numberFormat,
        },
      );

  group('PDF list rendering', () {
    test('ordered list draws incrementing number markers', () async {
      final out = await const PdfRenderer()
          .render(ctx(list('First\nSecond\nThird', 'ordered')));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      expect(pdf, contains('(1.) Tj'));
      expect(pdf, contains('(2.) Tj'));
      expect(pdf, contains('(3.) Tj'));
      expect(pdf, contains('First'));
    });

    test('bullet list draws bullet markers and skips blank lines', () async {
      final out = await const PdfRenderer()
          .render(ctx(list('Alpha\n\nBeta', 'bullet')));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      // Two items only (blank line dropped): exactly two bullet markers.
      // The bullet U+2022 encodes as octal \225 under WinAnsi (Helvetica path).
      expect(RegExp(r'\(\\225\) Tj').allMatches(pdf).length, 2);
      expect(pdf, contains('Alpha'));
      expect(pdf, contains('Beta'));
    });
  });

  group('HTML list rendering', () {
    test('ordered → <ol> with lower-roman list-style-type', () async {
      final out = await const HtmlRenderer()
          .render(ctx(list('a\nb', 'ordered', numberFormat: 'lower-roman')));
      final html = utf8.decode(out.content as List<int>);
      expect(html, contains('<ol'));
      expect(html, contains('list-style-type: lower-roman'));
      expect('<li>'.allMatches(html).length, 2);
    });

    test('bullet → <ul> with disc; blank lines skipped', () async {
      final out =
          await const HtmlRenderer().render(ctx(list('x\n\ny', 'bullet')));
      final html = utf8.decode(out.content as List<int>);
      expect(html, contains('<ul'));
      expect('<li>'.allMatches(html).length, 2);
    });
  });

  group('Markdown list rendering', () {
    test('ordered → native "1." lines', () async {
      final out = await const MarkdownRenderer()
          .render(ctx(list('one\ntwo', 'ordered')));
      final md = utf8.decode(out.content as List<int>);
      expect(md, contains('1. one'));
      expect(md, contains('2. two'));
    });

    test('bullet → native "- " lines', () async {
      final out =
          await const MarkdownRenderer().render(ctx(list('p\nq', 'bullet')));
      final md = utf8.decode(out.content as List<int>);
      expect(md, contains('- p'));
      expect(md, contains('- q'));
    });
  });
}
