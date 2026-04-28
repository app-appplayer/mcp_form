import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/ui_dsl_renderer.dart';
import 'package:test/test.dart';

const _renderer = UiDslRenderer();

/// A custom FormBlock subclass that doesn't match any known type.
/// Used to exercise the default branch in _buildBlock.
class _UnknownBlock extends FormBlock {
  _UnknownBlock({required super.blockId, required super.index})
      : super(type: FormBlockType.text); // type value is irrelevant here

  @override
  Map<String, dynamic> toJson() => {'blockId': blockId, 'type': 'unknown', 'index': index};
}

FormDocument _makeDoc({
  List<FormSection> sections = const [],
  Map<String, dynamic> data = const {},
  DateTime? modifiedAt,
}) {
  return FormDocument(
    documentId: 'doc-1',
    templateId: 'tpl-1',
    templateVersion: '1.0.0',
    metadata: FormDocumentMetadata(
      author: 'tester',
      createdAt: DateTime(2026),
      modifiedAt: modifiedAt,
    ),
    sections: sections,
    data: data,
  );
}

FormTemplate _makeTemplate() {
  return FormTemplate(
    templateId: 'tpl-1',
    version: '1.0.0',
    name: 'Test',
    schema: const FormSchema(),
    layoutPolicy: const FormLayoutPolicy(
      pageSize: FormPageSize(size: 'A4', width: 210, height: 297),
      margins: FormMargins(top: 20, right: 20, bottom: 20, left: 20),
      fontPolicy: FormFontPolicy(
        defaultFont: 'sans-serif',
        defaultSize: 12,
        headingSize: 18,
        bodySize: 12,
        minSize: 8,
      ),
    ),
  );
}

RenderContext _ctx(FormDocument doc) {
  return RenderContext(
    document: doc,
    layoutPolicy: _makeTemplate().layoutPolicy,
    template: _makeTemplate(),
  );
}

Map<String, dynamic> _renderToJson(FormRenderOutput output) {
  final jsonStr = utf8.decode(output.content as List<int>);
  return jsonDecode(jsonStr) as Map<String, dynamic>;
}

void main() {
  group('UiDslRenderer', () {
    test('supportedFormats includes uiDsl', () {
      expect(_renderer.supportedFormats, contains('uiDsl'));
    });

    test('output format is uiDsl', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      expect(output.format, 'uiDsl');
    });

    test('output has file size', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      expect(output.fileSize, greaterThan(0));
    });

    test('output is valid JSON', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final jsonStr = utf8.decode(output.content as List<int>);
      expect(() => jsonDecode(jsonStr), returnsNormally);
    });

    test('uses document modifiedAt for generatedAt', () async {
      final fixedTime = DateTime.utc(2026, 1, 15, 10);
      final output = await _renderer.render(_ctx(
        _makeDoc(modifiedAt: fixedTime),
      ));
      expect(output.generatedAt, fixedTime);
    });

    test('uses createdAt when modifiedAt is null', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      expect(output.generatedAt, DateTime(2026));
    });

    // Scaffold / ScrollView structure

    test('root type is Scaffold', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final tree = _renderToJson(output);
      expect(tree['type'], 'Scaffold');
    });

    test('scaffold contains metadata with documentId and templateId',
        () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final tree = _renderToJson(output);
      final metadata = tree['metadata'] as Map<String, dynamic>;
      expect(metadata['documentId'], 'doc-1');
      expect(metadata['templateId'], 'tpl-1');
      expect(metadata['status'], 'draft');
    });

    test('body is a ScrollView', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final tree = _renderToJson(output);
      final body = tree['body'] as Map<String, dynamic>;
      expect(body['type'], 'ScrollView');
    });

    test('padding from layout margins', () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final tree = _renderToJson(output);
      final body = tree['body'] as Map<String, dynamic>;
      final padding = body['padding'] as Map<String, dynamic>;
      expect(padding['top'], 20);
      expect(padding['right'], 20);
      expect(padding['bottom'], 20);
      expect(padding['left'], 20);
    });

    // Section rendering

    test('sections are rendered as Card widgets', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          const FormSection(
            sectionId: 's1',
            index: 0,
            title: 'Overview',
          ),
        ]),
      ));
      final tree = _renderToJson(output);
      final body = tree['body'] as Map<String, dynamic>;
      final children = body['children'] as List<dynamic>;
      expect(children, hasLength(1));
      final card = children[0] as Map<String, dynamic>;
      expect(card['type'], 'Card');
      expect(card['id'], 's1');
      expect(card['title'], 'Overview');
    });

    test('section without title omits title field', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(blockId: 'txt', index: 0, content: 'Hello'),
          ]),
        ]),
      ));
      final tree = _renderToJson(output);
      final body = tree['body'] as Map<String, dynamic>;
      final children = body['children'] as List<dynamic>;
      final card = children[0] as Map<String, dynamic>;
      expect(card.containsKey('title'), isFalse);
    });

    // TextBlock -> Text

    test('renders TextBlock as Text widget', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(blockId: 'txt', index: 0, content: 'Hello World'),
          ]),
        ]),
      ));
      final tree = _renderToJson(output);
      final block = _firstBlock(tree);
      expect(block['type'], 'Text');
      expect(block['id'], 'txt');
      expect(block['content'], 'Hello World');
    });

    // HeadingBlock -> Heading

    test('renders HeadingBlock as Heading widget', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormHeadingBlock(
              blockId: 'h',
              index: 0,
              content: 'Title',
              level: 3,
            ),
          ]),
        ]),
      ));
      final tree = _renderToJson(output);
      final block = _firstBlock(tree);
      expect(block['type'], 'Heading');
      expect(block['id'], 'h');
      expect(block['level'], 3);
      expect(block['content'], 'Title');
    });

    // TableBlock -> DataTable

    test('renders TableBlock as DataTable widget', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTableBlock(
              blockId: 'tbl',
              index: 0,
              columns: [
                const FormTableColumn(
                  id: 'name',
                  title: 'Name',
                  type: 'string',
                ),
                const FormTableColumn(
                  id: 'val',
                  title: 'Value',
                  type: 'string',
                ),
              ],
              rows: [FormTableRow(cells: {'name': 'Alice', 'val': '100'})],
            ),
          ]),
        ]),
      ));
      final tree = _renderToJson(output);
      final block = _firstBlock(tree);
      expect(block['type'], 'DataTable');
      expect(block['id'], 'tbl');
      final columns = block['columns'] as List<dynamic>;
      expect(columns, hasLength(2));
      expect(
        (columns[0] as Map<String, dynamic>)['title'],
        'Name',
      );
      final rows = block['rows'] as List<dynamic>;
      expect(rows, hasLength(1));
      expect(
        (rows[0] as Map<String, dynamic>)['name'],
        'Alice',
      );
    });

    // ChartBlock -> Chart

    test('renders ChartBlock as Chart widget', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormChartBlock(
              blockId: 'chart',
              index: 0,
              chartType: 'bar',
              unit: 'kg',
              title: 'Sales',
            ),
          ]),
        ]),
      ));
      final tree = _renderToJson(output);
      final block = _firstBlock(tree);
      expect(block['type'], 'Chart');
      expect(block['id'], 'chart');
      expect(block['chartType'], 'bar');
      expect(block['unit'], 'kg');
      expect(block['title'], 'Sales');
    });

    test('chart without optional fields omits them', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormChartBlock(
              blockId: 'chart',
              index: 0,
              chartType: 'pie',
            ),
          ]),
        ]),
      ));
      final tree = _renderToJson(output);
      final block = _firstBlock(tree);
      expect(block['type'], 'Chart');
      expect(block.containsKey('title'), isFalse);
      expect(block.containsKey('unit'), isFalse);
      expect(block.containsKey('xAxis'), isFalse);
      expect(block.containsKey('yAxis'), isFalse);
    });

    // ImageBlock -> Image

    test('renders ImageBlock as Image widget', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormImageBlock(
              blockId: 'img',
              index: 0,
              src: 'photo.png',
              alt: 'A photo',
            ),
          ]),
        ]),
      ));
      final tree = _renderToJson(output);
      final block = _firstBlock(tree);
      expect(block['type'], 'Image');
      expect(block['id'], 'img');
      expect(block['src'], 'photo.png');
      expect(block['alt'], 'A photo');
    });

    // FormFieldBlock -> FormField with interactive:true

    test('renders FormFieldBlock as FormField with interactive:true',
        () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(
          sections: [
            FormSection(sectionId: 's1', index: 0, blocks: [
              FormFieldBlock(
                blockId: 'f',
                index: 0,
                fieldName: 'Inspector',
                fieldType: 'text',
                constraints: {'required': true},
              ),
            ]),
          ],
          data: {'Inspector': 'John'},
        ),
      ));
      final tree = _renderToJson(output);
      final block = _firstBlock(tree);
      expect(block['type'], 'FormField');
      expect(block['id'], 'f');
      expect(block['fieldName'], 'Inspector');
      expect(block['fieldType'], 'text');
      expect(block['interactive'], true);
      expect(block['value'], 'John');
      expect(
        (block['constraints'] as Map<String, dynamic>)['required'],
        true,
      );
    });

    test('renders unfilled FormFieldBlock with null value', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormFieldBlock(
              blockId: 'f',
              index: 0,
              fieldName: 'Inspector',
              fieldType: 'text',
            ),
          ]),
        ]),
      ));
      final tree = _renderToJson(output);
      final block = _firstBlock(tree);
      expect(block['value'], isNull);
      expect(block['interactive'], true);
    });

    // RepeatableBlock -> RepeatingSection

    test('renders RepeatableBlock as RepeatingSection widget', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormRepeatableBlock(
              blockId: 'rep',
              index: 0,
              itemTemplate: [
                FormTextBlock(blockId: 'rt1', index: 0, content: 'Item A'),
                FormTextBlock(blockId: 'rt2', index: 1, content: 'Item B'),
              ],
              minItems: 1,
              maxItems: 5,
              itemsBinding: 'data.items',
            ),
          ]),
        ]),
      ));
      final tree = _renderToJson(output);
      final block = _firstBlock(tree);
      expect(block['type'], 'RepeatingSection');
      expect(block['id'], 'rep');
      expect(block['minItems'], 1);
      expect(block['maxItems'], 5);
      expect(block['itemsBinding'], 'data.items');
      final itemTemplate = block['itemTemplate'] as List<dynamic>;
      expect(itemTemplate, hasLength(2));
      expect(
        (itemTemplate[0] as Map<String, dynamic>)['type'],
        'Text',
      );
      expect(
        (itemTemplate[0] as Map<String, dynamic>)['content'],
        'Item A',
      );
    });

    // ConditionalBlock -> Conditional with thenBlock/elseBlock

    test('renders ConditionalBlock with thenBlock and elseBlock', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormConditionalBlock(
              blockId: 'cond',
              index: 0,
              condition: 'data.score >= 80',
              thenBlock: FormTextBlock(
                blockId: 'then',
                index: 0,
                content: 'Pass',
              ),
              elseBlock: FormTextBlock(
                blockId: 'else',
                index: 0,
                content: 'Fail',
              ),
            ),
          ]),
        ]),
      ));
      final tree = _renderToJson(output);
      final block = _firstBlock(tree);
      expect(block['type'], 'Conditional');
      expect(block['id'], 'cond');
      expect(block['condition'], 'data.score >= 80');
      final thenBlock = block['thenBlock'] as Map<String, dynamic>;
      expect(thenBlock['type'], 'Text');
      expect(thenBlock['content'], 'Pass');
      final elseBlock = block['elseBlock'] as Map<String, dynamic>;
      expect(elseBlock['type'], 'Text');
      expect(elseBlock['content'], 'Fail');
    });

    test('renders ConditionalBlock without elseBlock', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormConditionalBlock(
              blockId: 'cond',
              index: 0,
              condition: 'active',
              thenBlock: FormTextBlock(
                blockId: 'then',
                index: 0,
                content: 'Active',
              ),
            ),
          ]),
        ]),
      ));
      final tree = _renderToJson(output);
      final block = _firstBlock(tree);
      expect(block['type'], 'Conditional');
      expect(block.containsKey('elseBlock'), isFalse);
    });

    // Full document with all block types

    test('renders document with all 8 block types without errors', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(
          sections: [
            FormSection(sectionId: 's1', index: 0, blocks: [
              FormTextBlock(blockId: 'b1', index: 0, content: 'Text'),
              FormHeadingBlock(
                blockId: 'b2',
                index: 1,
                content: 'Heading',
                level: 1,
              ),
              FormTableBlock(
                blockId: 'b3',
                index: 2,
                columns: [
                  const FormTableColumn(
                    id: 'c1',
                    title: 'Col',
                    type: 'string',
                  ),
                ],
                rows: [FormTableRow(cells: {'c1': 'val'})],
              ),
              FormImageBlock(blockId: 'b4', index: 3, src: 'img.png'),
              FormChartBlock(blockId: 'b5', index: 4, chartType: 'line'),
              FormFieldBlock(
                blockId: 'b6',
                index: 5,
                fieldName: 'name',
                fieldType: 'text',
              ),
              FormRepeatableBlock(
                blockId: 'b7',
                index: 6,
                itemTemplate: [
                  FormTextBlock(
                    blockId: 'inner',
                    index: 0,
                    content: 'Repeated',
                  ),
                ],
              ),
              FormConditionalBlock(
                blockId: 'b8',
                index: 7,
                condition: 'true',
                thenBlock: FormTextBlock(
                  blockId: 'then',
                  index: 0,
                  content: 'Then',
                ),
              ),
            ]),
          ],
          data: {'name': 'Alice'},
        ),
      ));
      final tree = _renderToJson(output);
      final body = tree['body'] as Map<String, dynamic>;
      final sections = body['children'] as List<dynamic>;
      final card = sections[0] as Map<String, dynamic>;
      final blocks = card['children'] as List<dynamic>;
      expect(blocks, hasLength(8));
    });

    // Table column optional fields

    test('table column includes width and alignment when set', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTableBlock(
              blockId: 'tbl',
              index: 0,
              columns: [
                const FormTableColumn(
                  id: 'name',
                  title: 'Name',
                  type: 'string',
                  width: 200,
                  alignment: 'left',
                ),
              ],
              rows: const [],
            ),
          ]),
        ]),
      ));
      final tree = _renderToJson(output);
      final block = _firstBlock(tree);
      final columns = block['columns'] as List<dynamic>;
      final col = columns[0] as Map<String, dynamic>;
      expect(col['width'], 200);
      expect(col['alignment'], 'left');
    });

    test('table includes headerRepeat field', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTableBlock(
              blockId: 'tbl',
              index: 0,
              columns: [
                const FormTableColumn(
                  id: 'c1',
                  title: 'Col',
                  type: 'string',
                ),
              ],
              rows: const [],
            ),
          ]),
        ]),
      ));
      final tree = _renderToJson(output);
      final block = _firstBlock(tree);
      // headerRepeat should be present (default value)
      expect(block.containsKey('headerRepeat'), isTrue);
    });

    // Empty document

    test('empty document produces valid Scaffold with empty children',
        () async {
      final output = await _renderer.render(_ctx(_makeDoc()));
      final tree = _renderToJson(output);
      expect(tree['type'], 'Scaffold');
      final body = tree['body'] as Map<String, dynamic>;
      final children = body['children'] as List<dynamic>;
      expect(children, isEmpty);
    });

    // Unknown block type -> default branch
    test('renders unknown block type as Unknown widget', () async {
      final output = await _renderer.render(_ctx(
        _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            _UnknownBlock(blockId: 'unk-1', index: 0),
          ]),
        ]),
      ));
      final tree = _renderToJson(output);
      final block = _firstBlock(tree);
      expect(block['type'], 'Unknown');
      expect(block['id'], 'unk-1');
    });
  });
}

/// Helper to extract the first block from a rendered widget tree.
Map<String, dynamic> _firstBlock(Map<String, dynamic> tree) {
  final body = tree['body'] as Map<String, dynamic>;
  final sections = body['children'] as List<dynamic>;
  final card = sections[0] as Map<String, dynamic>;
  final blocks = card['children'] as List<dynamic>;
  return blocks[0] as Map<String, dynamic>;
}
