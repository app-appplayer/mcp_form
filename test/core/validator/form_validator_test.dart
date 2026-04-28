import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/core/validator/form_validator.dart';
import 'package:test/test.dart';

FormTemplate _makeTemplate({FormSchema? schema}) {
  return FormTemplate(
    templateId: 'tpl-1',
    version: '1.0.0',
    name: 'Test Template',
    schema: schema ?? const FormSchema(),
    layoutPolicy: const FormLayoutPolicy(
      pageSize: FormPageSize(size: 'A4', width: 210, height: 297),
      margins: FormMargins(top: 20, right: 20, bottom: 20, left: 20),
      fontPolicy: FormFontPolicy(
        defaultFont: 'sans-serif',
        defaultSize: 12,
        headingSize: 18,
        bodySize: 12,
        minSize: 8,
      ),
    ),
  );
}

FormDocument _makeDoc({
  Map<String, dynamic> data = const {},
  List<FormSection> sections = const [],
}) {
  return FormDocument(
    documentId: 'doc-1',
    templateId: 'tpl-1',
    templateVersion: '1.0.0',
    metadata: FormDocumentMetadata(
      author: 'tester',
      createdAt: DateTime(2026),
    ),
    data: data,
    sections: sections,
  );
}

void main() {
  const validator = FormValidator();

  group('FormValidator - valid document', () {
    test('valid document returns isValid=true with no issues', () {
      final template = _makeTemplate(
        schema: FormSchema(fields: [
          FormSchemaField(name: 'name', type: 'string'),
        ]),
      );
      final result = validator.validate(
        document: _makeDoc(data: {'name': 'Alice'}),
        template: template,
      );

      expect(result.isValid, isTrue);
      expect(result.issues, isEmpty);
    });
  });

  group('FormValidator - schema errors', () {
    test('reports schema validation errors', () {
      final template = _makeTemplate(
        schema: FormSchema(fields: [
          FormSchemaField(name: 'name', type: 'string', required: true),
        ]),
      );
      final result = validator.validate(
        document: _makeDoc(),
        template: template,
      );

      expect(result.isValid, isFalse);
      expect(result.issues.length, 1);
      expect(result.issues[0].code, 'schema.required_missing');
    });
  });

  group('FormValidator - layout warnings', () {
    test('includes layout warnings in result', () {
      final template = _makeTemplate();
      final result = validator.validate(
        document: _makeDoc(sections: [
          FormSection(sectionId: 'sec-1', index: 0, blocks: [
            FormImageBlock(
              blockId: 'img-1',
              index: 0,
              src: 'test.png',
              aspectRatio: 0.1,
            ),
          ]),
        ]),
        template: template,
      );

      // Layout warnings don't make isValid false
      expect(result.isValid, isTrue);
      expect(result.issues.any((i) => i.code == 'layout.image_ratio'), isTrue);
    });
  });

  group('FormValidator - combined validation', () {
    test('combines schema errors and layout warnings', () {
      final template = _makeTemplate(
        schema: FormSchema(fields: [
          FormSchemaField(name: 'name', type: 'string', required: true),
        ]),
      );
      final result = validator.validate(
        document: _makeDoc(sections: [
          FormSection(sectionId: 'sec-1', index: 0, blocks: [
            FormImageBlock(
              blockId: 'img-1',
              index: 0,
              src: 'test.png',
              aspectRatio: 0.1,
            ),
          ]),
        ]),
        template: template,
      );

      expect(result.isValid, isFalse);
      expect(result.issues.length, 2);
    });
  });

  group('FormValidator - autoFix', () {
    test('applies auto-fix and re-validates', () {
      final template = _makeTemplate(
        schema: FormSchema(fields: [
          FormSchemaField(name: 'title', type: 'string', required: true),
        ]),
      );
      final result = validator.validate(
        document: _makeDoc(),
        template: template,
        autoFix: true,
      );

      // After auto-fix sets default empty string,
      // re-validation still reports required_missing because empty string
      // is also caught by required check.
      expect(result.appliedFixes, isNotNull);
      expect(result.appliedFixes!.length, 1);
      expect(result.appliedFixes![0].action, 'set_default');
    });

    test('auto-fix truncates oversized string', () {
      final template = _makeTemplate(
        schema: FormSchema(fields: [
          FormSchemaField(name: 'bio', type: 'string', maxValue: 5),
        ]),
      );
      final result = validator.validate(
        document: _makeDoc(data: {'bio': 'This is too long'}),
        template: template,
        autoFix: true,
      );

      expect(result.appliedFixes, isNotNull);
      expect(result.appliedFixes!.any((f) => f.action == 'truncate'), isTrue);
      // After truncation and re-validation, should be valid
      expect(result.isValid, isTrue);
    });

    test('does not apply fixes when autoFix is false', () {
      final template = _makeTemplate(
        schema: FormSchema(fields: [
          FormSchemaField(name: 'bio', type: 'string', maxValue: 5),
        ]),
      );
      final result = validator.validate(
        document: _makeDoc(data: {'bio': 'This is too long'}),
        template: template,
      );

      expect(result.appliedFixes, isNull);
      expect(result.isValid, isFalse);
    });
  });

  group('FormValidator - null severity handling', () {
    test('treats null severity as error', () {
      // Documents with issues where severity is null should be invalid
      final template = _makeTemplate(
        schema: FormSchema(fields: [
          FormSchemaField(name: 'x', type: 'number'),
        ]),
      );
      final result = validator.validate(
        document: _makeDoc(data: {'x': 'not-a-number'}),
        template: template,
      );

      expect(result.isValid, isFalse);
    });
  });
}
