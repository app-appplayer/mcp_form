import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/core/schema/capacity.dart';
import 'package:mcp_form/src/core/schema/json_schema_export.dart';
import 'package:test/test.dart';

/// C2 — capacity feed-forward: estimate how much text a fixed box holds, and
/// fold it into the JSON Schema as `maxLength` so the LLM writes to fit.
void main() {
  group('estimateCapacity', () {
    test('more height → more lines; more width → more chars per line', () {
      final small = estimateCapacity(
          widthPt: 100, heightPt: 40, fontSizePt: 12);
      final taller = estimateCapacity(
          widthPt: 100, heightPt: 120, fontSizePt: 12);
      final wider = estimateCapacity(
          widthPt: 300, heightPt: 40, fontSizePt: 12);
      expect(taller.lines, greaterThan(small.lines));
      expect(wider.charsPerLine, greaterThan(small.charsPerLine));
      expect(small.maxChars, small.lines * small.charsPerLine);
    });

    test('zero height → no capacity', () {
      final c = estimateCapacity(widthPt: 100, heightPt: 0, fontSizePt: 12);
      expect(c.lines, 0);
      expect(c.maxChars, 0);
    });
  });

  FormTemplate template(List<FormBlock> blocks) {
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
    return FormTemplate(
      templateId: 't',
      version: '1.0.0',
      name: 'T',
      schema: const FormSchema(),
      layoutPolicy: layout,
      defaultSections: [FormSection(sectionId: 's', index: 0, blocks: blocks)],
    );
  }

  group('estimateFieldCapacities', () {
    test('only fixed-height field boxes get a capacity', () {
      final t = template([
        FormFieldBlock(
            blockId: 'a',
            index: 0,
            fieldName: 'summary',
            fieldType: 'string',
            style: {'height': 60}),
        FormFieldBlock(
            blockId: 'b',
            index: 1,
            fieldName: 'unbounded',
            fieldType: 'string'),
      ]);
      final caps = estimateFieldCapacities(t);
      expect(caps.containsKey('summary'), isTrue);
      expect(caps.containsKey('unbounded'), isFalse);
      expect(caps['summary']!.maxChars, greaterThan(0));
    });

    test('a narrower colSpan yields fewer chars per line', () {
      final wide = estimateFieldCapacities(template([
        FormFieldBlock(
            blockId: 'a',
            index: 0,
            fieldName: 'f',
            fieldType: 'string',
            style: {'height': 60, 'colSpan': 12}),
      ]))['f']!;
      final narrow = estimateFieldCapacities(template([
        FormFieldBlock(
            blockId: 'a',
            index: 0,
            fieldName: 'f',
            fieldType: 'string',
            style: {'height': 60, 'colSpan': 4}),
      ]))['f']!;
      expect(narrow.charsPerLine, lessThan(wide.charsPerLine));
    });
  });

  group('capacity folded into JSON Schema', () {
    test('string field gets maxLength + a fits-note from its box', () {
      final t = FormTemplate(
        templateId: 't',
        version: '1.0.0',
        name: 'Report',
        schema: FormSchema(fields: [
          FormSchemaField(name: 'summary', type: 'string', label: 'Summary'),
        ]),
        layoutPolicy: FormLayoutPolicy(
          pageSize: const FormPageSize(size: 'A4', width: 210, height: 297),
          margins: const FormMargins(top: 20, right: 20, bottom: 20, left: 20),
          fontPolicy: const FormFontPolicy(
              defaultFont: 'x',
              defaultSize: 12,
              headingSize: 18,
              bodySize: 12,
              minSize: 8),
        ),
        defaultSections: [
          FormSection(sectionId: 's', index: 0, blocks: [
            FormFieldBlock(
                blockId: 'a',
                index: 0,
                fieldName: 'summary',
                fieldType: 'string',
                style: {'height': 60}),
          ]),
        ],
      );
      final js = templateToJsonSchema(t);
      final summary = (js['properties'] as Map)['summary'] as Map;
      expect(summary['maxLength'], isNotNull);
      expect(summary['maxLength'], greaterThan(0));
      expect(summary['description'], contains('fits about'));
    });

    test('withCapacity: false omits maxLength', () {
      final t = FormTemplate(
        templateId: 't',
        version: '1.0.0',
        name: 'R',
        schema: FormSchema(
            fields: [FormSchemaField(name: 'summary', type: 'string')]),
        layoutPolicy: FormLayoutPolicy(
          pageSize: const FormPageSize(size: 'A4', width: 210, height: 297),
          margins: const FormMargins(top: 20, right: 20, bottom: 20, left: 20),
          fontPolicy: const FormFontPolicy(
              defaultFont: 'x',
              defaultSize: 12,
              headingSize: 18,
              bodySize: 12,
              minSize: 8),
        ),
        defaultSections: [
          FormSection(sectionId: 's', index: 0, blocks: [
            FormFieldBlock(
                blockId: 'a',
                index: 0,
                fieldName: 'summary',
                fieldType: 'string',
                style: {'height': 60}),
          ]),
        ],
      );
      final js = templateToJsonSchema(t, withCapacity: false);
      expect(((js['properties'] as Map)['summary'] as Map).containsKey('maxLength'),
          isFalse);
    });
  });
}
