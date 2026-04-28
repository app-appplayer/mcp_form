import 'package:mcp_form/mcp_form.dart';
import 'package:test/test.dart';

void main() {
  group('FieldType', () {
    // TC-016: All 6 FieldType values exist
    test('has all 6 values', () {
      expect(FieldType.values.length, 6);
      expect(
        FieldType.values,
        containsAll([
          FieldType.string,
          FieldType.number,
          FieldType.date,
          FieldType.enumType,
          FieldType.object,
          FieldType.array,
        ]),
      );
    });

    test('fromString parses known types', () {
      expect(FieldType.fromString('string'), FieldType.string);
      expect(FieldType.fromString('number'), FieldType.number);
      expect(FieldType.fromString('date'), FieldType.date);
      expect(FieldType.fromString('enumType'), FieldType.enumType);
      expect(FieldType.fromString('enum'), FieldType.enumType);
      expect(FieldType.fromString('object'), FieldType.object);
      expect(FieldType.fromString('array'), FieldType.array);
    });

    test('fromString returns string for unknown types', () {
      expect(FieldType.fromString('unknown'), FieldType.string);
      expect(FieldType.fromString(''), FieldType.string);
    });
  });
}
