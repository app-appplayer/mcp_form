import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/mcp_form.dart';
import 'package:test/test.dart';

FormRepeatableBlock _rep({
  String? itemsBinding,
  int? minItems,
  int? maxItems,
  List<FormBlock>? template,
}) =>
    FormRepeatableBlock(
      blockId: 'rep',
      index: 0,
      itemsBinding: itemsBinding,
      minItems: minItems,
      maxItems: maxItems,
      itemTemplate: template ??
          [
            FormFieldBlock(
                blockId: 'f', index: 0, fieldName: 'name', fieldType: 'text'),
          ],
    );

void main() {
  group('resolveRepeatableItems', () {
    test('null binding yields a single parent-data scope (legacy)', () {
      final scopes = resolveRepeatableItems(_rep(), {'x': 1});
      expect(scopes.length, 1);
      expect(scopes.first, {'x': 1});
    });

    test('reads the bound array, one scope per element', () {
      final scopes = resolveRepeatableItems(
        _rep(itemsBinding: 'items'),
        {
          'items': [
            {'name': 'A'},
            {'name': 'B'},
          ],
        },
      );
      expect(scopes.map((s) => s['name']), ['A', 'B']);
    });

    test('dotted path navigates nested maps', () {
      final scopes = resolveRepeatableItems(
        _rep(itemsBinding: 'order.lines'),
        {
          'order': {
            'lines': [
              {'sku': 'X'},
            ],
          },
        },
      );
      expect(scopes.single['sku'], 'X');
    });

    test('scalars are wrapped as {value: ...}', () {
      final scopes = resolveRepeatableItems(
        _rep(itemsBinding: 'tags'),
        {
          'tags': ['red', 'blue'],
        },
      );
      expect(scopes.map((s) => s['value']), ['red', 'blue']);
    });

    test('maxItems truncates, minItems pads with empty scopes', () {
      final tooMany = resolveRepeatableItems(
        _rep(itemsBinding: 'items', maxItems: 1),
        {
          'items': [
            {'name': 'A'},
            {'name': 'B'},
          ],
        },
      );
      expect(tooMany.length, 1);

      final tooFew = resolveRepeatableItems(
        _rep(itemsBinding: 'items', minItems: 3),
        {
          'items': [
            {'name': 'A'},
          ],
        },
      );
      expect(tooFew.length, 3);
      expect(tooFew[1], isEmpty);
    });

    test('missing path resolves to no items', () {
      final scopes = resolveRepeatableItems(
          _rep(itemsBinding: 'nope'), {'items': <dynamic>[]});
      expect(scopes, isEmpty);
    });
  });

  group('renderers expand repeatable over bound data', () {
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
      data: const {
        'lines': [
          {'item': 'Apples'},
          {'item': 'Oranges'},
          {'item': 'Pears'},
        ],
      },
      sections: [
        FormSection(sectionId: 's', index: 0, blocks: [
          FormRepeatableBlock(
            blockId: 'rep',
            index: 0,
            itemsBinding: 'lines',
            itemTemplate: [
              FormFieldBlock(
                  blockId: 'f',
                  index: 0,
                  fieldName: 'item',
                  fieldType: 'text'),
            ],
          ),
        ]),
      ],
      metadata: FormDocumentMetadata(author: 'x', createdAt: DateTime(2026)),
    );
    final ctx = RenderContext(
      document: doc,
      layoutPolicy: layout,
      template: tpl,
      options: const RenderOptions(compress: false),
    );

    test('html renders one field instance per bound item', () async {
      final out = await const HtmlRenderer().render(ctx);
      final html = utf8.decode(out.content as List<int>);
      expect(html, contains('Apples'));
      expect(html, contains('Oranges'));
      expect(html, contains('Pears'));
    });

    test('markdown renders each item value', () async {
      final out = await const MarkdownRenderer().render(ctx);
      final md = utf8.decode(out.content as List<int>);
      expect(md, contains('Apples'));
      expect(md, contains('Oranges'));
      expect(md, contains('Pears'));
    });

    test('pdf draws each item value', () async {
      final out = await const PdfRenderer().render(ctx);
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      expect(pdf, contains('Apples'));
      expect(pdf, contains('Pears'));
    });
  });
}
