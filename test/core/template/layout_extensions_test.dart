import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/mcp_form.dart';
import 'package:test/test.dart';

void main() {
  group('FormLayoutPolicyDimensions', () {
    const standardFontPolicy = FormFontPolicyDefaults.standard;

    // TC-035: contentWidth for A4 portrait with 20mm margins
    test('contentWidth for A4 portrait with 20mm margins', () {
      final layout = FormLayoutPolicy(
        pageSize: FormPageSizeDefaults.a4,
        margins: FormMarginsFactory.all(20.0),
        fontPolicy: standardFontPolicy,
      );

      expect(layout.contentWidth, 170.0);
    });

    // TC-036: contentHeight for A4 portrait with 20mm margins
    test('contentHeight for A4 portrait with 20mm margins', () {
      final layout = FormLayoutPolicy(
        pageSize: FormPageSizeDefaults.a4,
        margins: FormMarginsFactory.all(20.0),
        fontPolicy: standardFontPolicy,
      );

      expect(layout.contentHeight, 257.0);
    });

    // TC-038: Landscape orientation swaps width and height
    test('landscape orientation swaps width and height', () {
      final layout = FormLayoutPolicy(
        pageSize: const FormPageSize(
          size: 'A4',
          width: 210,
          height: 297,
          orientation: 'landscape',
        ),
        margins: FormMarginsFactory.all(20.0),
        fontPolicy: standardFontPolicy,
      );

      expect(layout.effectivePageWidth, 297.0);
      expect(layout.effectivePageHeight, 210.0);
    });

    // TC-034: effectiveOrientation defaults to portrait
    test('defaults to portrait orientation', () {
      final layout = FormLayoutPolicy(
        pageSize: FormPageSizeDefaults.a4,
        margins: FormMarginsFactory.all(20.0),
        fontPolicy: standardFontPolicy,
      );

      expect(layout.isLandscape, isFalse);
      expect(layout.effectivePageWidth, 210.0);
      expect(layout.effectivePageHeight, 297.0);
    });

    // TC-039: columnWidth calculation
    test('columnWidth calculation', () {
      final layout = FormLayoutPolicy(
        pageSize: FormPageSizeDefaults.a4,
        margins: FormMarginsFactory.all(20.0),
        fontPolicy: standardFontPolicy,
      );

      expect(layout.columnWidth, closeTo(14.17, 0.01));
    });
  });

  group('FormFontPolicyScale', () {
    const fontPolicy = FormFontPolicyDefaults.standard;

    // TC-042: headingSizeForLevel scale calculation
    test('heading size scales correctly for levels 1-6', () {
      expect(fontPolicy.headingSizeForLevel(1), 21.0); // 14 * 1.5
      expect(fontPolicy.headingSizeForLevel(2), 17.5); // 14 * 1.25
      expect(fontPolicy.headingSizeForLevel(3), 14.0); // 14 * 1.0
      expect(fontPolicy.headingSizeForLevel(4), 12.25); // 14 * 0.875
      expect(fontPolicy.headingSizeForLevel(5), 10.5); // 14 * 0.75
      expect(fontPolicy.headingSizeForLevel(6), 8.75); // 14 * 0.625
    });

    // TC-043: Level clamped outside 1-6
    test('levels outside 1-6 are clamped', () {
      expect(fontPolicy.headingSizeForLevel(0), 21.0); // clamped to 1
      expect(fontPolicy.headingSizeForLevel(-1), 21.0); // clamped to 1
      expect(fontPolicy.headingSizeForLevel(7), 8.75); // clamped to 6
      expect(fontPolicy.headingSizeForLevel(100), 8.75); // clamped to 6
    });
  });
}
