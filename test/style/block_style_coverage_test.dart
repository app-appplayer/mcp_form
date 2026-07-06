import 'package:mcp_form/src/style/style.dart';
import 'package:test/test.dart';

void main() {
  test('BlockOverflow.token', () {
    expect(BlockOverflow.shrinkToFit.token, 'shrink');
    expect(BlockOverflow.grow.token, 'grow');
    expect(BlockOverflow.clip.token, 'clip');
  });

  test('BlockBorder copyWith / toMap / == / hashCode', () {
    const b = BlockBorder(width: 2, color: '#f00', radius: 3);
    final c = b.copyWith(color: '#0f0');
    expect(c.color, '#0f0');
    expect(c.width, 2);
    expect(b.toMap(), {'width': 2.0, 'color': '#f00', 'radius': 3.0});
    expect(b == const BlockBorder(width: 2, color: '#f00', radius: 3), isTrue);
    expect(b.hashCode,
        const BlockBorder(width: 2, color: '#f00', radius: 3).hashCode);
  });

  test('BlockBorder.copyWith with null color evaluates this.color (line 99)', () {
    // copyWith(color: null) is the only path that evaluates the right-hand side
    // of "color ?? this.color" (line 99).  Calling it with a non-null color
    // short-circuits that sub-expression and leaves line 99 uncovered.
    const b = BlockBorder(width: 2, color: '#f00', radius: 3);
    final c = b.copyWith(width: 1.0); // color=null → this.color is evaluated
    expect(c.color, '#f00');
    expect(c.width, 1.0);
    expect(c.radius, 3.0);
  });

  test('BlockStyle.toMap serializes all populated fields', () {
    const style = BlockStyle(
      styleRef: 'ref',
      align: FormTextAlign.center,
      text: TextRunStyle(bold: true),
      background: '#eee',
      lineHeight: 1.5,
      spaceBefore: 2,
      spaceAfter: 3,
      indent: 4,
      height: 20,
      overflow: BlockOverflow.shrinkToFit,
      border: BlockBorder(width: 1),
      padding: 5,
      listStyle: 'disc',
      numberFormat: 'decimal',
    );
    final m = style.toMap();
    expect(m['styleRef'], 'ref');
    expect(m['align'], 'center');
    expect(m['background'], '#eee');
    expect(m['overflow'], 'shrink');
    expect(m['border'], isA<Map<String, dynamic>>());
    expect(m['listStyle'], 'disc');
    expect(m['numberFormat'], 'decimal');
  });
}
