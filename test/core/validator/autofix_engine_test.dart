import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/core/validator/autofix_engine.dart';
import 'package:test/test.dart';

FormDocument _makeDoc(Map<String, dynamic> data) {
  return FormDocument(
    documentId: 'doc-1',
    templateId: 'tpl-1',
    templateVersion: '1.0.0',
    metadata: FormDocumentMetadata(
      author: 'tester',
      createdAt: DateTime(2026),
    ),
    data: data,
  );
}

void main() {
  const engine = AutoFixEngine();

  group('AutoFixEngine - set_default strategy', () {
    // TC-182: Set default for missing required string field
    test('sets empty string default for missing required string field', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'title', type: 'string', required: true),
      ]);
      final issues = [
        FormValidationIssue(
          code: 'schema.required_missing',
          message: 'Required field "title" is missing',
          path: '/data/title',
          severity: 'error',
        ),
      ];
      final result = engine.applyFixes(
        document: _makeDoc({}),
        issues: issues,
        schema: schema,
      );

      expect(result.fixes.length, 1);
      expect(result.fixes[0].action, 'set_default');
      expect(result.fixes[0].path, '/data/title');
      expect(result.document.data['title'], '');
    });

    // TC-183: Set default for missing required number field
    test('sets 0 default for missing required number field', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'count', type: 'number', required: true),
      ]);
      final issues = [
        FormValidationIssue(
          code: 'schema.required_missing',
          message: 'Required field "count" is missing',
          path: '/data/count',
          severity: 'error',
        ),
      ];
      final result = engine.applyFixes(
        document: _makeDoc({}),
        issues: issues,
        schema: schema,
      );

      expect(result.fixes.length, 1);
      expect(result.document.data['count'], 0);
    });

    // TC-184: Set default for missing required date field
    test('sets ISO date default for missing required date field', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'dueDate', type: 'date', required: true),
      ]);
      final issues = [
        FormValidationIssue(
          code: 'schema.required_missing',
          message: 'Required field "dueDate" is missing',
          path: '/data/dueDate',
          severity: 'error',
        ),
      ];
      final result = engine.applyFixes(
        document: _makeDoc({}),
        issues: issues,
        schema: schema,
      );

      expect(result.fixes.length, 1);
      expect(result.document.data['dueDate'], isA<String>());
      expect(
        DateTime.tryParse(result.document.data['dueDate'] as String),
        isNotNull,
      );
    });

    test('skips unknown field types for default', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'data', type: 'object', required: true),
      ]);
      final issues = [
        FormValidationIssue(
          code: 'schema.required_missing',
          message: 'Required field "data" is missing',
          path: '/data/data',
          severity: 'error',
        ),
      ];
      final result = engine.applyFixes(
        document: _makeDoc({}),
        issues: issues,
        schema: schema,
      );

      expect(result.fixes, isEmpty);
    });
  });

  group('AutoFixEngine - truncate strategy', () {
    // TC-185: Truncate string exceeding maxLength
    test('truncates string exceeding maxLength', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'title', type: 'string', maxValue: 10),
      ]);
      final issues = [
        FormValidationIssue(
          code: 'schema.constraint_violated',
          message: 'Field "title" exceeds maximum length 10 (got 20)',
          path: '/data/title',
          severity: 'error',
        ),
      ];
      final result = engine.applyFixes(
        document: _makeDoc({'title': 'This is a very long text'}),
        issues: issues,
        schema: schema,
      );

      expect(result.fixes.length, 1);
      expect(result.fixes[0].action, 'truncate');
      expect(
        (result.document.data['title'] as String).length,
        10,
      );
    });

    test('does not truncate when issue is not about length', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'email', type: 'string'),
      ]);
      final issues = [
        FormValidationIssue(
          code: 'schema.constraint_violated',
          message: 'Field "email" does not match pattern',
          path: '/data/email',
          severity: 'error',
        ),
      ];
      final result = engine.applyFixes(
        document: _makeDoc({'email': 'bad'}),
        issues: issues,
        schema: schema,
      );

      expect(result.fixes, isEmpty);
    });
  });

  group('AutoFixEngine - no fixes needed', () {
    test('returns original document when no fixes applied', () {
      const schema = FormSchema();
      final doc = _makeDoc({'name': 'Alice'});
      final result = engine.applyFixes(
        document: doc,
        issues: [],
        schema: schema,
      );

      expect(result.fixes, isEmpty);
      expect(identical(result.document, doc), isTrue);
    });

    test('returns original document for unfixable issues', () {
      const schema = FormSchema();
      final doc = _makeDoc({'name': 'Alice'});
      final result = engine.applyFixes(
        document: doc,
        issues: [
          FormValidationIssue(
            code: 'layout.overflow',
            message: 'Content overflows',
            path: '/sections/0/blocks/0',
            severity: 'warning',
          ),
        ],
        schema: schema,
      );

      expect(result.fixes, isEmpty);
      expect(identical(result.document, doc), isTrue);
    });
  });

  group('AutoFixEngine - multiple fixes', () {
    test('applies multiple fixes in order', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'name', type: 'string', required: true),
        FormSchemaField(name: 'bio', type: 'string', maxValue: 5),
      ]);
      final issues = [
        FormValidationIssue(
          code: 'schema.required_missing',
          message: 'Required field "name" is missing',
          path: '/data/name',
          severity: 'error',
        ),
        FormValidationIssue(
          code: 'schema.constraint_violated',
          message: 'Field "bio" exceeds maximum length 5 (got 20)',
          path: '/data/bio',
          severity: 'error',
        ),
      ];
      final result = engine.applyFixes(
        document: _makeDoc({'bio': 'This is too long text'}),
        issues: issues,
        schema: schema,
      );

      expect(result.fixes.length, 2);
      expect(result.document.data['name'], '');
      expect((result.document.data['bio'] as String).length, 5);
    });
  });

  group('AutoFixEngine - path extraction', () {
    test('handles path without data prefix gracefully', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'title', type: 'string', required: true),
      ]);
      final issues = [
        FormValidationIssue(
          code: 'schema.required_missing',
          message: 'Required field "title" is missing',
          path: '/sections/0/blocks/0',
          severity: 'error',
        ),
      ];
      final result = engine.applyFixes(
        document: _makeDoc({}),
        issues: issues,
        schema: schema,
      );

      expect(result.fixes, isEmpty);
    });
  });

  group('AutoFixEngine - field not in schema', () {
    // Coverage: _trySetDefault returns null when field is not in schema
    test('set_default skips when field name not in schema', () {
      // Schema has 'name' but issue path refers to 'unknown'
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'name', type: 'string', required: true),
      ]);
      final issues = [
        FormValidationIssue(
          code: 'schema.required_missing',
          message: 'Required field "unknown" is missing',
          path: '/data/unknown',
          severity: 'error',
        ),
      ];
      final result = engine.applyFixes(
        document: _makeDoc({}),
        issues: issues,
        schema: schema,
      );

      expect(result.fixes, isEmpty);
    });

    // Coverage: _tryTruncate returns null when field is not in schema
    test('truncate skips when field name not in schema', () {
      final schema = FormSchema(fields: [
        FormSchemaField(name: 'name', type: 'string', maxValue: 10),
      ]);
      final issues = [
        FormValidationIssue(
          code: 'schema.constraint_violated',
          message:
              'Field "unknown" exceeds maximum length 10 (got 20)',
          path: '/data/unknown',
          severity: 'error',
        ),
      ];
      final result = engine.applyFixes(
        document: _makeDoc({'unknown': 'This is very long text indeed'}),
        issues: issues,
        schema: schema,
      );

      expect(result.fixes, isEmpty);
    });
  });
}
