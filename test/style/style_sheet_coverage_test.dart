import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

void main() {
  group('FormStyleSheet.toMap', () {
    test('serialises theme and non-empty styles map (lines 93-96)', () {
      // Build a stylesheet with a named style so styles.isNotEmpty is true.
      final ss = FormStyleSheet.fromMap({
        'theme': {
          'colors': {'accent': '#0000FF'},
          'bodyFont': 'serif',
        },
        'styles': {
          'body': {'italic': true},
          'header': {'bold': true, 'fontSize': 16},
        },
      });

      final m = ss.toMap(); // covers lines 93-96

      expect(m['theme'], isA<Map<String, dynamic>>());
      expect(m['styles'], isA<Map<String, dynamic>>());
      final styles = m['styles'] as Map<String, dynamic>;
      expect(styles.containsKey('body'), isTrue);
      expect(styles.containsKey('header'), isTrue);
    });

    test('toMap with empty styles omits the styles key (exercises line 95 branch false)', () {
      final ss = FormStyleSheet(
        theme: FormTheme.fromMap({'colors': {'primary': '#FF0000'}}),
      );
      final m = ss.toMap();
      expect(m.containsKey('theme'), isTrue);
      expect(m.containsKey('styles'), isFalse);
    });
  });
}
