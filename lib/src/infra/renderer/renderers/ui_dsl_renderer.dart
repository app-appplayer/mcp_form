import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';

import '../render_context.dart';
import '../renderer_registry.dart';

/// AppPlayer UI DSL renderer adapter.
///
/// Produces a JSON-based widget tree that AppPlayer can interpret
/// to render interactive document views. Unlike PDF/HTML which
/// produce static output, the UI DSL preserves interactivity
/// for form fields and editing.
class UiDslRenderer implements DocumentRenderer {
  const UiDslRenderer();

  @override
  List<String> get supportedFormats => const ['uiDsl'];

  @override
  String? get supportedTemplateRange => '>= 1.0.0 < 2.0.0';

  @override
  Future<FormRenderOutput> render(RenderContext context) async {
    final document = context.document;
    final widgetTree = _buildWidgetTree(document, context);
    final dslJson = jsonEncode(widgetTree);
    final dslBytes = utf8.encode(dslJson);

    return FormRenderOutput(
      format: 'uiDsl',
      content: dslBytes,
      pageCount: 1,
      fileSize: dslBytes.length,
      generatedAt: document.metadata.modifiedAt ?? document.metadata.createdAt,
    );
  }

  Map<String, dynamic> _buildWidgetTree(
    FormDocument document,
    RenderContext context,
  ) {
    return {
      'type': 'Scaffold',
      'metadata': {
        'documentId': document.documentId,
        'templateId': document.templateId,
        'status': document.status.name,
      },
      'body': {
        'type': 'ScrollView',
        'padding': {
          'top': context.layoutPolicy.margins.top,
          'right': context.layoutPolicy.margins.right,
          'bottom': context.layoutPolicy.margins.bottom,
          'left': context.layoutPolicy.margins.left,
        },
        'children':
            document.sections.map((s) => _buildSection(s, document)).toList(),
      },
    };
  }

  Map<String, dynamic> _buildSection(
    FormSection section,
    FormDocument document,
  ) {
    return {
      'type': 'Card',
      'id': section.sectionId,
      if (section.title != null) 'title': section.title,
      'children':
          section.blocks.map((b) => _buildBlock(b, document)).toList(),
    };
  }

  Map<String, dynamic> _buildBlock(FormBlock block, FormDocument document) {
    switch (block) {
      case FormTextBlock():
        return {
          'type': 'Text',
          'id': block.blockId,
          'content': block.content,
        };

      case FormHeadingBlock():
        return {
          'type': 'Heading',
          'id': block.blockId,
          'level': block.level,
          'content': block.content,
        };

      case FormTableBlock():
        return {
          'type': 'DataTable',
          'id': block.blockId,
          'columns': block.columns
              .map((col) => {
                    'id': col.id,
                    'title': col.title,
                    'type': col.type,
                    if (col.width != null) 'width': col.width,
                    if (col.alignment != null) 'alignment': col.alignment,
                  })
              .toList(),
          'rows': block.rows.map((row) => row.cells).toList(),
          'headerRepeat': block.headerRepeat,
        };

      case FormChartBlock():
        return {
          'type': 'Chart',
          'id': block.blockId,
          'chartType': block.chartType,
          'data': block.data,
          if (block.title != null) 'title': block.title,
          if (block.xAxis != null) 'xAxis': block.xAxis,
          if (block.yAxis != null) 'yAxis': block.yAxis,
          if (block.unit != null) 'unit': block.unit,
        };

      case FormImageBlock():
        return {
          'type': 'Image',
          'id': block.blockId,
          'src': block.src,
          'alt': block.alt,
        };

      case FormCanvasBlock():
        return {
          'type': 'Canvas',
          'id': block.blockId,
          'target': block.target,
          'mode': block.mode,
          'format': block.format,
          'fallback': block.fallback,
          if (block.viewport != null) 'viewport': block.viewport,
          if (block.caption != null) 'caption': block.caption,
          if (block.alt != null) 'alt': block.alt,
          if (block.maxWidth != null) 'maxWidth': block.maxWidth,
          if (block.aspectRatio != null) 'aspectRatio': block.aspectRatio,
        };

      case FormFieldBlock():
        return {
          'type': 'FormField',
          'id': block.blockId,
          'fieldType': block.fieldType,
          'fieldName': block.fieldName,
          'constraints': block.constraints,
          'interactive': true,
          'value': document.data[block.fieldName],
        };

      case FormRepeatableBlock():
        return {
          'type': 'RepeatingSection',
          'id': block.blockId,
          'itemTemplate':
              block.itemTemplate.map((b) => _buildBlock(b, document)).toList(),
          if (block.itemsBinding != null) 'itemsBinding': block.itemsBinding,
          'minItems': block.minItems,
          'maxItems': block.maxItems,
        };

      case FormConditionalBlock():
        return {
          'type': 'Conditional',
          'id': block.blockId,
          'condition': block.condition,
          'thenBlock': _buildBlock(block.thenBlock, document),
          if (block.elseBlock != null)
            'elseBlock': _buildBlock(block.elseBlock!, document),
        };

      default:
        return {'type': 'Unknown', 'id': block.blockId};
    }
  }
}
