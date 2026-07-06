import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/pdf_renderer.dart';
import 'package:test/test.dart';

/// B1 — paged pagination quality: keep-together and widow/orphan control.
/// Defaults (orphans/widows = 1, keepTogether off) preserve break-anywhere
/// behaviour; raising them gives professional break control.
void main() {
  // A short page so a handful of lines overflow predictably.
  RenderContext ctx(List<FormBlock> blocks, {double height = 70}) {
    final layout = FormLayoutPolicy(
      pageSize: FormPageSize(size: 'custom', width: 120, height: height),
      margins: const FormMargins(top: 12, right: 12, bottom: 12, left: 12),
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
        sections: [FormSection(sectionId: 's', index: 0, blocks: blocks)],
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

  /// The PDF's page content streams, in page order (no embedded font here, so
  /// every readable `stream`…`endstream` body carrying `Tj` is a page).
  List<String> pageStreams(List<int> bytes) {
    final pdf = latin1.decode(bytes, allowInvalid: true);
    return RegExp(r'stream\r?\n(.*?)endstream', dotAll: true)
        .allMatches(pdf)
        .map((m) => m.group(1)!)
        .where((s) => s.contains('Tj'))
        .toList();
  }

  /// Index of the page whose stream contains [marker]; -1 if none.
  int pageOf(List<String> pages, String marker) =>
      pages.indexWhere((p) => p.contains(marker));

  FormTextBlock para(String id, int lines, {Map<String, dynamic>? style}) =>
      FormTextBlock(
        blockId: id,
        index: 0,
        content: List.generate(lines, (i) => '$id$i').join('\n'),
        style: style,
      );

  group('keep-together', () {
    test('a keepTogether block is not split across a page break', () async {
      // Filler nearly fills page 1; the 3-line block would split by default.
      final blocks = [
        para('F', 6),
        para('K', 3, style: {'keepTogether': true}),
      ];
      final pages = pageStreams(
          (await const PdfRenderer().render(ctx(blocks))).content as List<int>);
      // All three K lines land on one page (not split).
      expect(pageOf(pages, 'K0'), greaterThanOrEqualTo(0));
      expect(pageOf(pages, 'K0'), pageOf(pages, 'K2'));
    });

    test('without keepTogether the same block does split', () async {
      final blocks = [para('F', 6), para('K', 3)];
      final pages = pageStreams(
          (await const PdfRenderer().render(ctx(blocks))).content as List<int>);
      // Default: the block straddles the page boundary (K0 earlier than K2).
      expect(pageOf(pages, 'K0') == pageOf(pages, 'K2'), isFalse);
    });
  });

  group('orphans / widows', () {
    test('orphans keeps a minimum run together at the bottom', () async {
      // 4-line block; with orphans=4 it must not start unless all 4 fit, so it
      // moves to a fresh page and stays whole.
      final blocks = [
        para('F', 6),
        para('P', 4, style: {'orphans': 4, 'widows': 4}),
      ];
      final pages = pageStreams(
          (await const PdfRenderer().render(ctx(blocks))).content as List<int>);
      expect(pageOf(pages, 'P0'), pageOf(pages, 'P3')); // whole block together
    });

    test('default (1/1) still paginates and renders every line', () async {
      final blocks = [para('B', 8)];
      final out = await const PdfRenderer().render(ctx(blocks));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      for (var i = 0; i < 8; i++) {
        expect(pdf, contains('B$i'));
      }
      expect(out.pageCount, greaterThan(1));
    });
  });
}
