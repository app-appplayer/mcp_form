import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/adapters/form_port_impl.dart';
import 'package:mcp_form/src/adapters/form_renderer_port_impl.dart';
import 'package:mcp_form/src/adapters/form_template_port_impl.dart';
import 'package:mcp_form/src/feat/mcp/argument_validator.dart';
import 'package:mcp_form/src/feat/mcp/form_template_json_schema.dart';
import 'package:mcp_form/src/feat/mcp/form_tool_handler.dart';
import 'package:mcp_form/src/feat/mcp/mcp_types.dart';
import 'package:mcp_form/src/infra/renderer/renderer_registry.dart';
import 'package:test/test.dart';

/// A template as a host sends it: decoded JSON, every block type once,
/// blocks nested inside `repeatable` and `conditional`.
Map<String, dynamic> fullTemplate() => jsonDecode('''{
  "templateId": "tpl-full",
  "version": "1.0.0",
  "name": "Every block",
  "description": "d",
  "locale": "en",
  "components": ["c1"],
  "i18nStrings": {"k": "v"},
  "schema": {
    "fields": [{"name": "title", "type": "string", "required": true}],
    "rules": [{"ruleId": "r1", "description": "d", "expression": "true"}],
    "strict": false
  },
  "layoutPolicy": {
    "pageSize": {"size": "A4", "width": 210, "height": 297.5},
    "margins": {"top": 20, "right": 20, "bottom": 20, "left": 20},
    "fontPolicy": {"defaultFont": "Inter", "defaultSize": 11,
      "headingSize": 16, "bodySize": 11, "minSize": 8},
    "gridColumns": 12
  },
  "defaultSections": [{
    "sectionId": "s1", "index": 0, "title": "T",
    "blocks": [
      {"type": "text", "blockId": "b1", "index": 0, "content": "x"},
      {"type": "heading", "blockId": "b2", "index": 1, "content": "H", "level": 2},
      {"type": "table", "blockId": "b3", "index": 2,
        "columns": [{"id": "c", "title": "C", "type": "string", "width": 40}],
        "rows": [{"cells": {"c": "1"}}]},
      {"type": "chart", "blockId": "b4", "index": 3, "chartType": "bar",
        "data": [], "xAxis": {"label": "x", "min": 0}},
      {"type": "image", "blockId": "b5", "index": 4, "src": "a.png"},
      {"type": "canvas", "blockId": "b6", "index": 5, "target": "scene"},
      {"type": "formField", "blockId": "b7", "index": 6,
        "fieldName": "f", "fieldType": "text"},
      {"type": "repeatable", "blockId": "b8", "index": 7, "itemTemplate": [
        {"type": "text", "blockId": "b8a", "index": 0, "content": "i"}]},
      {"type": "conditional", "blockId": "b9", "index": 8, "condition": "true",
        "thenBlock": {"type": "text", "blockId": "b9a", "index": 0, "content": "t"},
        "elseBlock": {"type": "heading", "blockId": "b9b", "index": 0, "content": "e"}}
    ]
  }],
  "manifest": {"compatRange": ">=0.2.0",
    "dependencies": [{"componentId": "c1", "version": "1.0.0"}]}
}''') as Map<String, dynamic>;

void main() {
  late FormToolHandler handler;

  setUp(() {
    final templatePort = FormTemplatePortImpl();
    handler = FormToolHandler(
      formPort: FormPortImpl(templatePort: templatePort),
      templatePort: templatePort,
      rendererPort: FormRendererPortImpl(
          registry: RendererRegistry(), templatePort: templatePort),
    );
  });

  Future<McpToolError> refusal(String tool, Map<String, dynamic> args) async {
    try {
      await handler.handleToolCall(toolName: tool, arguments: args);
    } on McpToolError catch (e) {
      return e;
    }
    fail('$tool accepted $args');
  }

  List<String> pathsOf(McpToolError e) =>
      [for (final i in e.data!['issues'] as List) (i as Map)['path'] as String];

  group('form.save_template refuses a malformed template by path', () {
    test('an unrelated object names every missing field', () async {
      final e = await refusal('form.save_template', {
        'template': {'bogus': 1}
      });
      expect(e.code, 'INVALID_PARAMS');
      expect(e.data!['formErrorCode'], 'template.invalid_schema');
      expect(
          pathsOf(e),
          containsAll([
            'template.templateId',
            'template.version',
            'template.name',
            'template.schema',
            'template.layoutPolicy',
          ]));
      expect(e.message, isNot(contains('subtype')));
    });

    test('a missing nested object', () async {
      final t = fullTemplate();
      (t['layoutPolicy'] as Map).remove('fontPolicy');
      final e = await refusal('form.save_template', {'template': t});
      expect(pathsOf(e), ['template.layoutPolicy.fontPolicy']);
      expect(
          e.message, contains('template.layoutPolicy.fontPolicy is required'));
    });

    test('a mistyped field', () async {
      final t = fullTemplate()..['templateId'] = 7;
      final e = await refusal('form.save_template', {'template': t});
      expect(pathsOf(e), ['template.templateId']);
      expect(e.message, contains('must be a string, got an integer'));
    });

    test('a block missing its content, by index', () async {
      final t = fullTemplate();
      final blocks =
          ((t['defaultSections'] as List)[0] as Map)['blocks'] as List;
      (blocks[0] as Map).remove('content');
      final e = await refusal('form.save_template', {'template': t});
      expect(pathsOf(e), ['template.defaultSections[0].blocks[0].content']);
    });

    test('blocks nested in conditional and repeatable are checked', () async {
      final t = fullTemplate();
      final blocks =
          ((t['defaultSections'] as List)[0] as Map)['blocks'] as List;
      ((blocks[8] as Map)['thenBlock'] as Map).remove('content');
      (((blocks[7] as Map)['itemTemplate'] as List)[0] as Map)['index'] = '0';
      final e = await refusal('form.save_template', {'template': t});
      expect(
          pathsOf(e),
          containsAll([
            'template.defaultSections[0].blocks[8].thenBlock.content',
            'template.defaultSections[0].blocks[7].itemTemplate[0].index',
          ]));
    });

    test('an unknown block type is checked as the text block it reads as',
        () async {
      final t = fullTemplate();
      final blocks =
          ((t['defaultSections'] as List)[0] as Map)['blocks'] as List;
      blocks.add({'type': 'mystery', 'blockId': 'bx', 'index': 9});
      final e = await refusal('form.save_template', {'template': t});
      expect(pathsOf(e), ['template.defaultSections[0].blocks[9].content']);
    });

    test('an integer field refuses 1.0, which the model cannot cast', () async {
      final t = fullTemplate();
      ((t['defaultSections'] as List)[0] as Map)['index'] = 1.0;
      final e = await refusal('form.save_template', {'template': t});
      expect(pathsOf(e), ['template.defaultSections[0].index']);
    });

    test('a template that is not an object', () async {
      final e = await refusal('form.save_template', {'template': 'x'});
      expect(pathsOf(e), ['template']);
    });
  });

  group('the schema is not stricter than the model', () {
    test('a full template saves', () async {
      final r = await handler.handleToolCall(
          toolName: 'form.save_template',
          arguments: {'template': fullTemplate()});
      expect(r['templateId'], 'tpl-full');
    });

    test('what the model writes back validates', () {
      final emitted =
          jsonDecode(jsonEncode(FormTemplate.fromJson(fullTemplate()).toJson()))
              as Map<String, dynamic>;
      expect(validateArgument(emitted, formTemplateJsonSchema), isEmpty);
    });

    test('the published input schema carries its own definitions', () {
      final def = handler.toolDefinitions
          .firstWhere((d) => d.name == 'form.save_template');
      expect(def.inputSchema[r'$defs'], isNotEmpty);
      expect(validateArgument({'template': fullTemplate()}, def.inputSchema),
          isEmpty);
    });
  });

  group('every tool checks its own arguments', () {
    test('a missing required argument', () async {
      final e = await refusal('form.get_template', {});
      expect(pathsOf(e), ['templateId']);
      expect(e.data!.containsKey('formErrorCode'), isFalse);
    });

    test('a mistyped argument', () async {
      final e = await refusal('form.get_document', {'documentId': 3});
      expect(pathsOf(e), ['documentId']);
    });

    test('a patch operation without op', () async {
      final e = await refusal('form.patch', {
        'documentId': 'd',
        'patches': [
          {'path': '/x'}
        ],
      });
      expect(pathsOf(e), ['patches[0].op']);
    });

    test('an enum value outside the list', () async {
      final e = await refusal('form.patch', {
        'documentId': 'd',
        'patches': [
          {'op': 'explode', 'path': '/x'}
        ],
      });
      expect(pathsOf(e), ['patches[0].op']);
    });

    test('create_document takes no data, as its description says', () async {
      await handler.handleToolCall(
          toolName: 'form.save_template',
          arguments: {'template': fullTemplate()});
      final r = await handler.handleToolCall(
          toolName: 'form.create_document',
          arguments: {'templateId': 'tpl-full'});
      expect(r['status'], 'draft');
    });
  });

  test('template.invalid_schema from a port maps to INVALID_PARAMS', () {
    final e = FormToolHandler.mapFormErrorToMcpError(FormError(
        code: 'template.invalid_schema', message: 'm', path: 'schema'));
    expect(e.code, 'INVALID_PARAMS');
    expect(e.data!['path'], 'schema');
  });
}
