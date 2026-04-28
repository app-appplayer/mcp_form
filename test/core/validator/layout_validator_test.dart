import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/core/validator/layout_validator.dart';
import 'package:test/test.dart';

const _pageSize = FormPageSize(size: 'A4', width: 210, height: 297);
const _margins = FormMargins(top: 20, right: 20, bottom: 20, left: 20);
const _fontPolicy = FormFontPolicy(
  defaultFont: 'sans-serif',
  defaultSize: 12,
  headingSize: 18,
  bodySize: 12,
  minSize: 8,
);

FormLayoutPolicy _makePolicy({int? maxTableRows}) {
  return FormLayoutPolicy(
    pageSize: _pageSize,
    margins: _margins,
    fontPolicy: _fontPolicy,
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
  const validator = LayoutValidator();

  group('LayoutValidator - table overflow', () {
    // TC-171: Table within capacity passes
    test('table within maxTableRows limit produces no issues', () {
      final doc = _makeDoc(sections: [
        FormSection(sectionId: 'sec-1', index: 0, blocks: [
          FormTableBlock(
            blockId: 'tbl-1',
            index: 0,
            columns: [
              const FormTableColumn(id: 'col1', title: 'Name', type: 'string'),
            ],
            rows: [
              FormTableRow(cells: {'col1': 'Alice'}),
              FormTableRow(cells: {'col1': 'Bob'}),
            ],
          ),
        ]),
      ]);
      final issues = validator.validate(
        document: doc,
        layoutPolicy: _makePolicy(maxTableRows: 10),
      );
      final tableIssues =
          issues.where((i) => i.code == 'layout.table_overflow');
      expect(tableIssues, isEmpty);
    });

    // TC-172: Table exceeds maxTableRows
    test('table exceeding maxTableRows produces warning', () {
      final doc = _makeDoc(sections: [
        FormSection(sectionId: 'sec-1', index: 0, blocks: [
          FormTableBlock(
            blockId: 'tbl-1',
            index: 0,
            columns: [
              const FormTableColumn(id: 'col1', title: 'Name', type: 'string'),
            ],
            rows: List.generate(15, (i) => FormTableRow(cells: {'col1': 'Row $i'})),
          ),
        ]),
      ]);
      final issues = validator.validate(
        document: doc,
        layoutPolicy: _makePolicy(maxTableRows: 10),
      );
      final tableIssues =
          issues.where((i) => i.code == 'layout.table_overflow').toList();
      expect(tableIssues.length, 1);
      expect(tableIssues[0].severity, 'warning');
      expect(tableIssues[0].message, contains('15 rows'));
    });

    // TC-173: Table exceeds its own maxRows
    test('table exceeding its own maxRows produces warning', () {
      final doc = _makeDoc(sections: [
        FormSection(sectionId: 'sec-1', index: 0, blocks: [
          FormTableBlock(
            blockId: 'tbl-1',
            index: 0,
            columns: [
              const FormTableColumn(id: 'col1', title: 'Name', type: 'string'),
            ],
            rows: List.generate(8, (i) => FormTableRow(cells: {'col1': 'Row $i'})),
            maxRows: 5,
          ),
        ]),
      ]);
      final issues = validator.validate(
        document: doc,
        layoutPolicy: _makePolicy(),
      );
      final tableIssues =
          issues.where((i) => i.code == 'layout.table_overflow').toList();
      expect(tableIssues.length, 1);
      expect(tableIssues[0].message, contains('maxRows: 5'));
    });
  });

  group('LayoutValidator - image ratio', () {
    // TC-175: Image with acceptable aspect ratio
    test('image with normal aspect ratio produces no issues', () {
      final doc = _makeDoc(sections: [
        FormSection(sectionId: 'sec-1', index: 0, blocks: [
          FormImageBlock(
            blockId: 'img-1',
            index: 0,
            src: 'test.png',
            aspectRatio: 1.5,
          ),
        ]),
      ]);
      final issues = validator.validate(
        document: doc,
        layoutPolicy: _makePolicy(),
      );
      final imageIssues =
          issues.where((i) => i.code == 'layout.image_ratio');
      expect(imageIssues, isEmpty);
    });

    // TC-176: Image with too extreme aspect ratio
    test('image with extreme aspect ratio produces warning', () {
      final doc = _makeDoc(sections: [
        FormSection(sectionId: 'sec-1', index: 0, blocks: [
          FormImageBlock(
            blockId: 'img-1',
            index: 0,
            src: 'test.png',
            aspectRatio: 0.1,
          ),
        ]),
      ]);
      final issues = validator.validate(
        document: doc,
        layoutPolicy: _makePolicy(),
      );
      final imageIssues =
          issues.where((i) => i.code == 'layout.image_ratio').toList();
      expect(imageIssues.length, 1);
      expect(imageIssues[0].severity, 'warning');
    });

    test('image with aspect ratio > 4.0 produces warning', () {
      final doc = _makeDoc(sections: [
        FormSection(sectionId: 'sec-1', index: 0, blocks: [
          FormImageBlock(
            blockId: 'img-1',
            index: 0,
            src: 'test.png',
            aspectRatio: 5.0,
          ),
        ]),
      ]);
      final issues = validator.validate(
        document: doc,
        layoutPolicy: _makePolicy(),
      );
      expect(
        issues.any((i) => i.code == 'layout.image_ratio'),
        isTrue,
      );
    });

    test('image without aspect ratio produces no ratio warning', () {
      final doc = _makeDoc(sections: [
        FormSection(sectionId: 'sec-1', index: 0, blocks: [
          FormImageBlock(
            blockId: 'img-1',
            index: 0,
            src: 'test.png',
          ),
        ]),
      ]);
      final issues = validator.validate(
        document: doc,
        layoutPolicy: _makePolicy(),
      );
      expect(
        issues.any((i) => i.code == 'layout.image_ratio'),
        isFalse,
      );
    });
  });

  group('LayoutValidator - text overflow', () {
    // TC-167: Text within page height passes
    test('short text produces no overflow warning', () {
      final doc = _makeDoc(sections: [
        FormSection(sectionId: 'sec-1', index: 0, blocks: [
          FormTextBlock(
            blockId: 'txt-1',
            index: 0,
            content: 'Short text.',
          ),
        ]),
      ]);
      final issues = validator.validate(
        document: doc,
        layoutPolicy: _makePolicy(),
      );
      final overflows =
          issues.where((i) => i.code == 'layout.overflow');
      expect(overflows, isEmpty);
    });

    // TC-168: Very long text causes overflow
    test('very long text produces overflow warning', () {
      final longText = 'x' * 50000;
      final doc = _makeDoc(sections: [
        FormSection(sectionId: 'sec-1', index: 0, blocks: [
          FormTextBlock(
            blockId: 'txt-1',
            index: 0,
            content: longText,
          ),
        ]),
      ]);
      final issues = validator.validate(
        document: doc,
        layoutPolicy: _makePolicy(),
      );
      final overflows =
          issues.where((i) => i.code == 'layout.overflow').toList();
      expect(overflows.length, 1);
      expect(overflows[0].severity, 'warning');
    });
  });

  group('LayoutValidator - repeatable block', () {
    // TC-181: RepeatableBlock without maxItems
    test('repeatable block with minItems but no maxItems produces warning', () {
      final doc = _makeDoc(sections: [
        FormSection(sectionId: 'sec-1', index: 0, blocks: [
          FormRepeatableBlock(
            blockId: 'rep-1',
            index: 0,
            itemTemplate: [
              FormTextBlock(
                blockId: 'item-tpl',
                index: 0,
                content: 'Item',
              ),
            ],
            minItems: 1,
          ),
        ]),
      ]);
      final issues = validator.validate(
        document: doc,
        layoutPolicy: _makePolicy(),
      );
      final constraintIssues = issues
          .where((i) => i.code == 'layout.constraint_violation')
          .toList();
      expect(constraintIssues.length, 1);
      expect(constraintIssues[0].message, contains('no maxItems'));
    });
  });

  group('LayoutValidator - empty document', () {
    test('empty document produces no issues', () {
      final doc = _makeDoc();
      final issues = validator.validate(
        document: doc,
        layoutPolicy: _makePolicy(),
      );
      expect(issues, isEmpty);
    });
  });
}
