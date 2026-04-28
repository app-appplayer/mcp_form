import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/infra/renderer/layout_enforcer.dart';
import 'package:test/test.dart';

const _enforcer = LayoutEnforcer();

FormLayoutPolicy _makePolicy({int? maxTableRows}) {
  return FormLayoutPolicy(
    pageSize: const FormPageSize(size: 'A4', width: 210, height: 297),
    margins: const FormMargins(top: 20, right: 20, bottom: 20, left: 20),
    fontPolicy: const FormFontPolicy(
      defaultFont: 'sans-serif',
      defaultSize: 12,
      headingSize: 18,
      bodySize: 12,
      minSize: 8,
    ),
    maxTableRows: maxTableRows,
  );
}

FormDocument _makeDoc({List<FormSection> sections = const []}) {
  return FormDocument(
    documentId: 'doc-1',
    templateId: 'tpl-1',
    templateVersion: '1.0.0',
    metadata: FormDocumentMetadata(
      author: 'tester',
      createdAt: DateTime(2026),
    ),
    sections: sections,
  );
}

void main() {
  group('LayoutEnforcer', () {
    test('returns empty warnings for empty document', () {
      final warnings = _enforcer.preValidate(
        document: _makeDoc(),
        layoutPolicy: _makePolicy(),
      );

      expect(warnings, isEmpty);
    });

    test('returns empty warnings when no constraints are violated', () {
      final warnings = _enforcer.preValidate(
        document: _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(blockId: 'txt', index: 0, content: 'Short text'),
          ]),
        ]),
        layoutPolicy: _makePolicy(),
      );

      expect(warnings, isEmpty);
    });

    test('warns on table overflow when rows exceed maxTableRows', () {
      final rows = List.generate(
        15,
        (i) => FormTableRow(cells: {'col': 'row$i'}),
      );

      final warnings = _enforcer.preValidate(
        document: _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTableBlock(
              blockId: 'tbl',
              index: 0,
              columns: [
                const FormTableColumn(
                  id: 'col',
                  title: 'Column',
                  type: 'string',
                ),
              ],
              rows: rows,
            ),
          ]),
        ]),
        layoutPolicy: _makePolicy(maxTableRows: 10),
      );

      expect(warnings, hasLength(1));
      expect(warnings.first, contains('layout.table_overflow'));
      expect(warnings.first, contains('15 rows'));
      expect(warnings.first, contains('max: 10'));
    });

    test('no table warning when maxTableRows is null', () {
      final rows = List.generate(
        100,
        (i) => FormTableRow(cells: {'col': 'row$i'}),
      );

      final warnings = _enforcer.preValidate(
        document: _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTableBlock(
              blockId: 'tbl',
              index: 0,
              columns: [
                const FormTableColumn(
                  id: 'col',
                  title: 'Column',
                  type: 'string',
                ),
              ],
              rows: rows,
            ),
          ]),
        ]),
        layoutPolicy: _makePolicy(),
      );

      expect(warnings, isEmpty);
    });

    test('no table warning when rows are within limit', () {
      final rows = List.generate(
        5,
        (i) => FormTableRow(cells: {'col': 'row$i'}),
      );

      final warnings = _enforcer.preValidate(
        document: _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTableBlock(
              blockId: 'tbl',
              index: 0,
              columns: [
                const FormTableColumn(
                  id: 'col',
                  title: 'Column',
                  type: 'string',
                ),
              ],
              rows: rows,
            ),
          ]),
        ]),
        layoutPolicy: _makePolicy(maxTableRows: 10),
      );

      expect(warnings, isEmpty);
    });

    test('warns on text overflow when content exceeds page height', () {
      // Create a very long text that would overflow the page.
      // A4 content height = 297 - 20 - 20 = 257mm.
      // With bodySize=12pt, line height ~ 12 * 0.3528 * 1.4 ~ 5.93mm
      // Content width = 210 - 20 - 20 = 170mm
      // avgCharWidth = 12 * 0.6 * 0.3528 ~ 2.54mm
      // charsPerLine = floor(170 / 2.54) = 66
      // Need enough lines: 257 / 5.93 ~ 44 lines
      // So ~44 * 66 ~ 2904 chars would overflow.
      final longText = 'A' * 5000;

      final warnings = _enforcer.preValidate(
        document: _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(blockId: 'txt', index: 0, content: longText),
          ]),
        ]),
        layoutPolicy: _makePolicy(),
      );

      expect(warnings, hasLength(1));
      expect(warnings.first, contains('layout.text_overflow'));
      expect(warnings.first, contains('may overflow page'));
    });

    test('no text overflow warning for short text', () {
      final warnings = _enforcer.preValidate(
        document: _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(
              blockId: 'txt',
              index: 0,
              content: 'Short paragraph.',
            ),
          ]),
        ]),
        layoutPolicy: _makePolicy(),
      );

      expect(warnings, isEmpty);
    });

    test('handles multiple sections and blocks with combined warnings', () {
      final manyRows = List.generate(
        20,
        (i) => FormTableRow(cells: {'col': 'row$i'}),
      );
      final longText = 'B' * 5000;

      final warnings = _enforcer.preValidate(
        document: _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTableBlock(
              blockId: 'tbl',
              index: 0,
              columns: [
                const FormTableColumn(
                  id: 'col',
                  title: 'Column',
                  type: 'string',
                ),
              ],
              rows: manyRows,
            ),
          ]),
          FormSection(sectionId: 's2', index: 1, blocks: [
            FormTextBlock(blockId: 'txt', index: 0, content: longText),
          ]),
        ]),
        layoutPolicy: _makePolicy(maxTableRows: 10),
      );

      expect(warnings, hasLength(2));
      expect(
        warnings.first,
        contains('layout.table_overflow'),
      );
      expect(
        warnings.last,
        contains('layout.text_overflow'),
      );
    });

    test('warning includes correct block path', () {
      final manyRows = List.generate(
        15,
        (i) => FormTableRow(cells: {'col': 'row$i'}),
      );

      final warnings = _enforcer.preValidate(
        document: _makeDoc(sections: [
          const FormSection(sectionId: 's0', index: 0),
          FormSection(sectionId: 's1', index: 1, blocks: [
            FormTextBlock(blockId: 'txt', index: 0, content: 'Hello'),
            FormTableBlock(
              blockId: 'tbl',
              index: 1,
              columns: [
                const FormTableColumn(
                  id: 'col',
                  title: 'Column',
                  type: 'string',
                ),
              ],
              rows: manyRows,
            ),
          ]),
        ]),
        layoutPolicy: _makePolicy(maxTableRows: 10),
      );

      expect(warnings, hasLength(1));
      // Table is at section index 1, block index 1
      expect(warnings.first, contains('/sections/1/blocks/1'));
    });

    test('handles zero font size gracefully in text height estimation', () {
      // When bodySize is 0, avgCharWidthMm is 0, so _estimateTextHeight
      // returns 0, meaning no overflow.
      final policy = FormLayoutPolicy(
        pageSize: const FormPageSize(size: 'A4', width: 210, height: 297),
        margins: const FormMargins(top: 20, right: 20, bottom: 20, left: 20),
        fontPolicy: const FormFontPolicy(
          defaultFont: 'sans-serif',
          defaultSize: 12,
          headingSize: 18,
          bodySize: 0,
          minSize: 8,
        ),
      );

      final warnings = _enforcer.preValidate(
        document: _makeDoc(sections: [
          FormSection(sectionId: 's1', index: 0, blocks: [
            FormTextBlock(blockId: 'txt', index: 0, content: 'A' * 5000),
          ]),
        ]),
        layoutPolicy: policy,
      );

      // No overflow because estimated height is 0
      expect(warnings, isEmpty);
    });
  });
}
