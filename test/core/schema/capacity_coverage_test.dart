import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/core/schema/capacity.dart';
import 'package:test/test.dart';

/// Coverage tests for capacity.dart branches not reached by the primary suite:
///   - FormRepeatableBlock walk — lines 86-89
///   - FormConditionalBlock walk (with and without elseBlock) — lines 90-92
void main() {
  FormLayoutPolicy defaultLayout() => FormLayoutPolicy(
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

  FormTemplate makeTemplate(List<FormBlock> blocks) => FormTemplate(
        templateId: 't',
        version: '1.0.0',
        name: 'T',
        schema: const FormSchema(),
        layoutPolicy: defaultLayout(),
        defaultSections: [
          FormSection(sectionId: 's', index: 0, blocks: blocks),
        ],
      );

  group('estimateFieldCapacities — FormRepeatableBlock', () {
    test('walks item template and estimates capacity for fixed-height fields',
        () {
      final repeatable = FormRepeatableBlock(
        blockId: 'r1',
        index: 0,
        itemTemplate: [
          FormFieldBlock(
            blockId: 'f1',
            index: 0,
            fieldName: 'itemTitle',
            fieldType: 'string',
            style: {'height': 40},
          ),
          // Unbounded field — should be excluded from capacity map.
          FormFieldBlock(
            blockId: 'f2',
            index: 1,
            fieldName: 'itemUnbounded',
            fieldType: 'string',
          ),
        ],
      );

      final caps = estimateFieldCapacities(makeTemplate([repeatable]));
      expect(caps.containsKey('itemTitle'), isTrue);
      expect(caps['itemTitle']!.maxChars, greaterThan(0));
      expect(caps.containsKey('itemUnbounded'), isFalse);
    });
  });

  group('estimateFieldCapacities — FormConditionalBlock', () {
    test('walks thenBlock and elseBlock when elseBlock is present', () {
      final conditional = FormConditionalBlock(
        blockId: 'c1',
        index: 0,
        condition: 'active',
        thenBlock: FormFieldBlock(
          blockId: 'then1',
          index: 0,
          fieldName: 'thenField',
          fieldType: 'string',
          style: {'height': 50},
        ),
        elseBlock: FormFieldBlock(
          blockId: 'else1',
          index: 1,
          fieldName: 'elseField',
          fieldType: 'string',
          style: {'height': 50},
        ),
      );

      final caps = estimateFieldCapacities(makeTemplate([conditional]));
      expect(caps.containsKey('thenField'), isTrue);
      expect(caps['thenField']!.maxChars, greaterThan(0));
      expect(caps.containsKey('elseField'), isTrue);
      expect(caps['elseField']!.maxChars, greaterThan(0));
    });

    test('walks thenBlock only when elseBlock is absent', () {
      final conditional = FormConditionalBlock(
        blockId: 'c2',
        index: 0,
        condition: 'active',
        thenBlock: FormFieldBlock(
          blockId: 'then2',
          index: 0,
          fieldName: 'thenOnly',
          fieldType: 'string',
          style: {'height': 50},
        ),
      );

      final caps = estimateFieldCapacities(makeTemplate([conditional]));
      expect(caps.containsKey('thenOnly'), isTrue);
      expect(caps.containsKey('elseField'), isFalse);
    });
  });
}
