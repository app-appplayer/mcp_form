import 'package:mcp_form/mcp_form.dart';
import 'package:test/test.dart';

void main() {
  group('FormPageSizeDefaults', () {
    // TC-044: Predefined page sizes have correct dimensions
    test('A4 is 210x297 mm', () {
      expect(FormPageSizeDefaults.a4.width, 210);
      expect(FormPageSizeDefaults.a4.height, 297);
      expect(FormPageSizeDefaults.a4.size, 'A4');
    });

    test('A3 is 297x420 mm', () {
      expect(FormPageSizeDefaults.a3.width, 297);
      expect(FormPageSizeDefaults.a3.height, 420);
    });

    test('A5 is 148x210 mm', () {
      expect(FormPageSizeDefaults.a5.width, 148);
      expect(FormPageSizeDefaults.a5.height, 210);
    });

    test('Letter is 215.9x279.4 mm', () {
      expect(FormPageSizeDefaults.letter.width, 215.9);
      expect(FormPageSizeDefaults.letter.height, 279.4);
    });

    test('Legal is 215.9x355.6 mm', () {
      expect(FormPageSizeDefaults.legal.width, 215.9);
      expect(FormPageSizeDefaults.legal.height, 355.6);
    });

    test('Tabloid is 279.4x431.8 mm', () {
      expect(FormPageSizeDefaults.tabloid.width, 279.4);
      expect(FormPageSizeDefaults.tabloid.height, 431.8);
    });

    // TC-045: PageSize.fromName lookup
    test('fromName looks up predefined sizes case-insensitively', () {
      expect(FormPageSizeDefaults.fromName('a4')?.size, 'A4');
      expect(FormPageSizeDefaults.fromName('A4')?.size, 'A4');
      expect(FormPageSizeDefaults.fromName('letter')?.size, 'Letter');
      expect(FormPageSizeDefaults.fromName('Letter')?.size, 'Letter');
    });

    test('fromName returns null for unknown names', () {
      expect(FormPageSizeDefaults.fromName('unknown'), isNull);
      expect(FormPageSizeDefaults.fromName(''), isNull);
    });
  });

  group('FormMarginsFactory', () {
    test('all creates equal margins', () {
      final margins = FormMarginsFactory.all(20.0);
      expect(margins.top, 20.0);
      expect(margins.right, 20.0);
      expect(margins.bottom, 20.0);
      expect(margins.left, 20.0);
    });

    test('symmetric creates mirrored margins', () {
      final margins = FormMarginsFactory.symmetric(
        vertical: 25.0,
        horizontal: 20.0,
      );
      expect(margins.top, 25.0);
      expect(margins.bottom, 25.0);
      expect(margins.right, 20.0);
      expect(margins.left, 20.0);
    });

    test('zero has all sides at 0', () {
      expect(FormMarginsFactory.zero.top, 0);
      expect(FormMarginsFactory.zero.right, 0);
      expect(FormMarginsFactory.zero.bottom, 0);
      expect(FormMarginsFactory.zero.left, 0);
    });
  });

  group('FormFontPolicyDefaults', () {
    test('standard has expected values', () {
      const fp = FormFontPolicyDefaults.standard;
      expect(fp.defaultFont, 'NotoSans');
      expect(fp.defaultSize, 10);
      expect(fp.headingSize, 14);
      expect(fp.bodySize, 10);
      expect(fp.minSize, 6);
    });
  });
}
