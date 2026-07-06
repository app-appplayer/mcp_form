import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

FormChartBlock _chart(
  String type, {
  List<dynamic> data = const [],
  String? title,
}) =>
    FormChartBlock(
      blockId: 'c',
      index: 0,
      chartType: type,
      data: data,
      title: title,
    );

void main() {
  group('_buildPie: zero-total data shows "No data" label (line 202)', () {
    test('pie chart with all-zero y values emits a No-data label', () {
      // total = sum of abs(y) = 0 → total <= 0 is true → line 202.
      final geo = buildChartGeometry(
        _chart('pie', data: [
          {'label': 'A', 'y': 0},
          {'label': 'B', 'y': 0},
        ]),
        width: 200,
        height: 120,
      );
      expect(geo.texts.any((t) => t.text == 'No data'), isTrue);
    });
  });

  group('_fmt: non-integer values use toStringAsFixed(1) (line 348)', () {
    test('bar chart with a fractional max-y label shows one decimal place', () {
      // maxY = 1.5 → _fmt(1.5): 1.5 != 1.5.roundToDouble() (2.0) → line 348.
      final geo = buildChartGeometry(
        _chart('bar', data: [
          {'x': 'A', 'y': 1.5},
        ]),
        width: 200,
        height: 120,
      );
      // At least one axis label should contain a decimal point.
      expect(geo.texts.any((t) => t.text.contains('.')), isTrue);
    });

    test('line chart with decimal y values also exercises _fmt line 348', () {
      final geo = buildChartGeometry(
        _chart('line', data: [
          {'x': 'A', 'y': 2.7},
          {'x': 'B', 'y': 1.3},
        ]),
        width: 200,
        height: 120,
      );
      expect(geo.texts.any((t) => t.text.contains('.')), isTrue);
    });
  });
}
