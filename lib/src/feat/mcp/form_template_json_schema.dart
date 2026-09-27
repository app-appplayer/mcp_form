/// JSON Schema for a `FormTemplate` as `form.save_template` receives it.
///
/// It states what `FormTemplate.fromJson` (mcp_bundle) needs to build a
/// template: every field that model reads with a non-null cast is
/// `required` here, with the type it is cast to. Checking against it before
/// parsing is what turns a malformed template into `template.invalid_schema`
/// with the path at fault, instead of the raw cast error the parser throws.
///
/// Blocks are chosen by their `type` through `x-discriminator`; an unknown
/// type is checked as a text block, which is how the model reads it. Hosts
/// that validate with a general JSON Schema validator ignore that keyword
/// and still check the fields every block shares.
///
/// The `$ref`s point at `#/$defs/…` of the document they sit in, so the
/// definitions travel with whichever schema embeds the template:
/// [formTemplateJsonSchema] carries them itself, and a tool input schema
/// that puts [formTemplateObjectSchema] under a property carries
/// [formTemplateSchemaDefs] at its own root.
const Map<String, dynamic> formTemplateJsonSchema = {
  ...formTemplateObjectSchema,
  r'$defs': formTemplateSchemaDefs,
};

/// The template object itself, without its definitions.
const Map<String, dynamic> formTemplateObjectSchema = {
  'type': 'object',
  'description': 'Full FormTemplate JSON (FormTemplate.toJson shape)',
  'required': ['templateId', 'version', 'name', 'schema', 'layoutPolicy'],
  'properties': {
    'templateId': {'type': 'string'},
    'version': {'type': 'string'},
    'name': {'type': 'string'},
    'description': {'type': 'string'},
    'schema': {r'$ref': r'#/$defs/schema'},
    'layoutPolicy': {r'$ref': r'#/$defs/layoutPolicy'},
    'defaultSections': {
      'type': 'array',
      'items': {r'$ref': r'#/$defs/section'},
    },
    'locale': {'type': 'string'},
    'components': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'i18nStrings': {'type': 'object'},
    'manifest': {r'$ref': r'#/$defs/manifest'},
  },
};

/// The definitions [formTemplateObjectSchema] refers to.
const Map<String, dynamic> formTemplateSchemaDefs = {
  'schema': {
    'type': 'object',
    'properties': {
      'fields': {
        'type': 'array',
        'items': {r'$ref': r'#/$defs/schemaField'},
      },
      'rules': {
        'type': 'array',
        'items': {r'$ref': r'#/$defs/schemaRule'},
      },
      'strict': {'type': 'boolean'},
    },
  },
  'schemaField': {
    'type': 'object',
    'required': ['name', 'type'],
    'properties': {
      'name': {'type': 'string'},
      'type': {'type': 'string'},
      'required': {'type': 'boolean'},
      'label': {'type': 'string'},
      'placeholder': {'type': 'string'},
      'format': {'type': 'string'},
      'pattern': {'type': 'string'},
      'enumValues': {'type': 'array'},
      'description': {'type': 'string'},
      'sensitive': {'type': 'boolean'},
    },
  },
  'schemaRule': {
    'type': 'object',
    'required': ['ruleId', 'description', 'expression'],
    'properties': {
      'ruleId': {'type': 'string'},
      'description': {'type': 'string'},
      'expression': {'type': 'string'},
      'errorMessage': {'type': 'string'},
    },
  },
  'layoutPolicy': {
    'type': 'object',
    'required': ['pageSize', 'margins', 'fontPolicy'],
    'properties': {
      'pageSize': {r'$ref': r'#/$defs/pageSize'},
      'margins': {r'$ref': r'#/$defs/margins'},
      'fontFamily': {'type': 'string'},
      'fontPolicy': {r'$ref': r'#/$defs/fontPolicy'},
      'gridColumns': {'type': 'integer'},
      'maxTableRows': {'type': 'integer'},
      'maxLineLength': {'type': 'integer'},
      'autoWrap': {'type': 'boolean'},
      'autoScale': {'type': 'boolean'},
    },
  },
  'pageSize': {
    'type': 'object',
    'required': ['size', 'width', 'height'],
    'properties': {
      'size': {'type': 'string'},
      'width': {'type': 'number'},
      'height': {'type': 'number'},
      'orientation': {'type': 'string'},
    },
  },
  'margins': {
    'type': 'object',
    'required': ['top', 'right', 'bottom', 'left'],
    'properties': {
      'top': {'type': 'number'},
      'right': {'type': 'number'},
      'bottom': {'type': 'number'},
      'left': {'type': 'number'},
    },
  },
  'fontPolicy': {
    'type': 'object',
    'required': [
      'defaultFont',
      'defaultSize',
      'headingSize',
      'bodySize',
      'minSize',
    ],
    'properties': {
      'defaultFont': {'type': 'string'},
      'defaultSize': {'type': 'number'},
      'headingSize': {'type': 'number'},
      'bodySize': {'type': 'number'},
      'minSize': {'type': 'number'},
    },
  },
  'section': {
    'type': 'object',
    'required': ['sectionId', 'index'],
    'properties': {
      'sectionId': {'type': 'string'},
      'index': {'type': 'integer'},
      'title': {'type': 'string'},
      'description': {'type': 'string'},
      'blocks': {
        'type': 'array',
        'items': {r'$ref': r'#/$defs/block'},
      },
    },
  },
  'block': {
    'type': 'object',
    'required': ['type', 'blockId', 'index'],
    'properties': {
      'type': {'type': 'string'},
      'blockId': {'type': 'string'},
      'index': {'type': 'integer'},
      'style': {'type': 'object'},
    },
    'x-discriminator': {
      'property': 'type',
      'fallback': 'text',
      'mapping': {
        'text': {
          'required': ['content'],
          'properties': {
            'content': {'type': 'string'},
            'format': {'type': 'string'},
          },
        },
        'heading': {
          'required': ['content'],
          'properties': {
            'content': {'type': 'string'},
            'level': {'type': 'integer'},
            'numbering': {'type': 'boolean'},
          },
        },
        'table': {
          'properties': {
            'columns': {
              'type': 'array',
              'items': {r'$ref': r'#/$defs/tableColumn'},
            },
            'rows': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'cells': {'type': 'object'},
                  'attributes': {'type': 'object'},
                },
              },
            },
            'headerRepeat': {'type': 'boolean'},
            'maxRows': {'type': 'integer'},
            'unit': {'type': 'string'},
          },
        },
        'chart': {
          'required': ['chartType'],
          'properties': {
            'chartType': {'type': 'string'},
            'data': {'type': 'array'},
            'title': {'type': 'string'},
            'xAxis': {r'$ref': r'#/$defs/axis'},
            'yAxis': {r'$ref': r'#/$defs/axis'},
            'unit': {'type': 'string'},
          },
        },
        'image': {
          'required': ['src'],
          'properties': {
            'src': {'type': 'string'},
            'alt': {'type': 'string'},
            'maxWidth': {'type': 'number'},
            'aspectRatio': {'type': 'number'},
          },
        },
        'canvas': {
          'required': ['target'],
          'properties': {
            'target': {'type': 'string'},
            'mode': {'type': 'string'},
            'format': {'type': 'string'},
            'fallback': {'type': 'string'},
            'viewport': {'type': 'object'},
            'maxWidth': {'type': 'number'},
            'aspectRatio': {'type': 'number'},
            'caption': {'type': 'string'},
            'alt': {'type': 'string'},
          },
        },
        'formField': {
          'required': ['fieldName', 'fieldType'],
          'properties': {
            'fieldName': {'type': 'string'},
            'fieldType': {'type': 'string'},
            'placeholder': {'type': 'string'},
            'options': {'type': 'array'},
            'constraints': {'type': 'object'},
          },
        },
        'repeatable': {
          'required': ['itemTemplate'],
          'properties': {
            'itemTemplate': {
              'type': 'array',
              'items': {r'$ref': r'#/$defs/block'},
            },
            'itemsBinding': {'type': 'string'},
            'minItems': {'type': 'integer'},
            'maxItems': {'type': 'integer'},
          },
        },
        'conditional': {
          'required': ['condition', 'thenBlock'],
          'properties': {
            'condition': {'type': 'string'},
            'thenBlock': {r'$ref': r'#/$defs/block'},
            'elseBlock': {r'$ref': r'#/$defs/block'},
          },
        },
      },
    },
  },
  'tableColumn': {
    'type': 'object',
    'required': ['id', 'title', 'type'],
    'properties': {
      'id': {'type': 'string'},
      'title': {'type': 'string'},
      'type': {'type': 'string'},
      'width': {'type': 'number'},
      'alignment': {'type': 'string'},
    },
  },
  'axis': {
    'type': 'object',
    'properties': {
      'label': {'type': 'string'},
      'unit': {'type': 'string'},
      'min': {'type': 'number'},
      'max': {'type': 'number'},
    },
  },
  'manifest': {
    'type': 'object',
    'required': ['compatRange'],
    'properties': {
      'dependencies': {
        'type': 'array',
        'items': {
          'type': 'object',
          'required': ['componentId', 'version'],
          'properties': {
            'componentId': {'type': 'string'},
            'version': {'type': 'string'},
            'type': {'type': 'string'},
          },
        },
      },
      'compatRange': {'type': 'string'},
      'metadata': {'type': 'object'},
    },
  },
};
