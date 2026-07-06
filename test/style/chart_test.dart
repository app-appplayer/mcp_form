import 'dart:math' as math;

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

FormChartBlock _chart(
  String type, {
  List<dynamic> data = const [],
  String? title,
  FormAxisConfig? yAxis,
}) =>
    FormChartBlock(
      blockId: 'c',
      index: 0,
      chartType: type,
      data: data,
      title: title,
      yAxis: yAxis,
    );

void main() {
  group('normaliseSeries', () {
    test('reads series-shaped entries with points', () {
      final s = normaliseSeries(_chart('bar', data: [
        {
          'label': 'Temp',
          'color': '#FF0000',
          'points': [
            {'x': 'Mon', 'y': 1},
            {'x': 'Tue', 'y': 2},
          ],
        },
      ]));
      expect(s, hasLength(1));
      expect(s.first.label, 'Temp');
      expect(s.first.color.r, closeTo(1.0, 0.001));
      expect(s.first.points.map((p) => p.x), ['Mon', 'Tue']);
      expect(s.first.points.map((p) => p.y), [1.0, 2.0]);
    });

    test('collects bare point entries into one series (pie shape)', () {
      final s = normaliseSeries(_chart('pie', data: [
        {'label': 'A', 'value': 30},
        {'label': 'B', 'value': 70},
      ]));
      expect(s, hasLength(1));
      expect(s.first.points, hasLength(2));
      expect(s.first.points.map((p) => p.x), ['A', 'B']);
      expect(s.first.points.map((p) => p.y), [30.0, 70.0]);
    });

    test('parses numeric strings', () {
      final s = normaliseSeries(_chart('bar', data: [
        {'x': 'A', 'y': '12.5'},
      ]));
      expect(s.first.points.first.y, 12.5);
    });
  });

  group('buildChartGeometry', () {
    test('bar chart emits one rect per datum plus zeroed baseline', () {
      final geo = buildChartGeometry(
        _chart('bar', title: 'T', data: [
          {
            'label': 'Q',
            'points': [
              {'x': 'Jan', 'y': 10},
              {'x': 'Feb', 'y': 20},
            ],
          },
        ]),
        width: 400,
        height: 240,
      );
      expect(geo.rects, hasLength(2));
      // Title + 2 y-ticks + 2 category labels.
      expect(geo.texts.map((t) => t.text), contains('T'));
      expect(geo.texts.map((t) => t.text), contains('Jan'));
      // Taller value → taller bar.
      final jan = geo.rects[0];
      final feb = geo.rects[1];
      expect(feb.h, greaterThan(jan.h));
      // Axes present.
      expect(geo.segments, hasLength(2));
    });

    test('line chart emits a polyline through every point', () {
      final geo = buildChartGeometry(
        _chart('line', data: [
          {
            'label': 'L',
            'points': [
              {'x': 'A', 'y': 1},
              {'x': 'B', 'y': 5},
              {'x': 'C', 'y': 3},
            ],
          },
        ]),
        width: 400,
        height: 240,
      );
      expect(geo.polylines, hasLength(1));
      expect(geo.polylines.first.points, hasLength(3));
      expect(geo.rects, isEmpty);
    });

    test('pie wedges sweep a full turn', () {
      final geo = buildChartGeometry(
        _chart('pie', data: [
          {'label': 'A', 'value': 25},
          {'label': 'B', 'value': 25},
          {'label': 'C', 'value': 50},
        ]),
        width: 300,
        height: 300,
      );
      expect(geo.wedges, hasLength(3));
      final total = geo.wedges.fold<double>(0, (a, w) => a + w.sweepRad);
      expect(total, closeTo(2 * math.pi, 0.0001));
      // Largest value → largest sweep.
      expect(geo.wedges[2].sweepRad, greaterThan(geo.wedges[0].sweepRad));
    });

    test('multi-series bar adds a legend swatch per series', () {
      final geo = buildChartGeometry(
        _chart('bar', data: [
          {
            'label': 'S1',
            'points': [
              {'x': 'A', 'y': 1},
            ],
          },
          {
            'label': 'S2',
            'points': [
              {'x': 'A', 'y': 2},
            ],
          },
        ]),
        width: 400,
        height: 240,
      );
      // 2 bars + 2 legend swatches.
      expect(geo.rects, hasLength(4));
      expect(geo.texts.map((t) => t.text), containsAll(['S1', 'S2']));
    });

    test('empty data yields a No data label', () {
      final geo = buildChartGeometry(_chart('bar'), width: 200, height: 120);
      expect(geo.rects, isEmpty);
      expect(geo.wedges, isEmpty);
      expect(geo.texts.map((t) => t.text), contains('No data'));
    });

    test('yAxis max fixes the value scale', () {
      final geo = buildChartGeometry(
        _chart('bar',
            yAxis: const FormAxisConfig(max: 100),
            data: [
              {
                'label': 'Q',
                'points': [
                  {'x': 'A', 'y': 50},
                ],
              },
            ]),
        width: 400,
        height: 240,
      );
      // A value of 50 against a max of 100 fills roughly half the plot height.
      final plotH = geo.segments
          .firstWhere((s) => s.x1 == s.x2) // y-axis
          .let((s) => (s.y2 - s.y1).abs());
      expect(geo.rects.first.h, closeTo(plotH / 2, plotH * 0.15));
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
