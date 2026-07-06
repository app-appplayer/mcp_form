import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/core/condition/condition_evaluator.dart';
import 'package:mcp_form/src/infra/renderer/render_context.dart';
import 'package:mcp_form/src/infra/renderer/renderers/pdf_renderer.dart';
import 'package:test/test.dart';

/// `FormConditionalBlock.condition` evaluation — the static renderers pick
/// `thenBlock` / `elseBlock` by evaluating the expression against bound data.
void main() {
  group('evaluateCondition — comparisons', () {
    test('string equality', () {
      expect(evaluateCondition('status == "active"', {'status': 'active'}),
          isTrue);
      expect(evaluateCondition('status == "active"', {'status': 'idle'}),
          isFalse);
      expect(evaluateCondition("status != 'x'", {'status': 'y'}), isTrue);
    });

    test('numeric ordering', () {
      expect(evaluateCondition('score >= 80', {'score': 85}), isTrue);
      expect(evaluateCondition('score >= 80', {'score': 75}), isFalse);
      expect(evaluateCondition('n < 10', {'n': 3}), isTrue);
    });

    test('a leading data. prefix resolves to the data root', () {
      expect(evaluateCondition('data.score >= 80', {'score': 90}), isTrue);
    });

    test('nested path and list index', () {
      expect(
          evaluateCondition('user.age > 18', {
            'user': {'age': 21}
          }),
          isTrue);
      expect(
          evaluateCondition('items.0 == "a"', {
            'items': ['a', 'b']
          }),
          isTrue);
    });

    test('"3" string matches numeric field via string form', () {
      expect(evaluateCondition('code == "3"', {'code': 3}), isTrue);
    });
  });

  group('evaluateCondition — logic & truthiness', () {
    test('&& and ||', () {
      expect(evaluateCondition('a == 1 && b == 2', {'a': 1, 'b': 2}), isTrue);
      expect(evaluateCondition('a == 1 && b == 2', {'a': 1, 'b': 9}), isFalse);
      expect(evaluateCondition('a == 1 || b == 2', {'a': 0, 'b': 2}), isTrue);
    });

    test('bare truthiness', () {
      expect(evaluateCondition('active', {'active': true}), isTrue);
      expect(evaluateCondition('active', {'active': false}), isFalse);
      expect(evaluateCondition('name', {'name': 'x'}), isTrue);
      expect(evaluateCondition('name', {'name': ''}), isFalse);
      expect(evaluateCondition('missing', {}), isFalse);
      expect(evaluateCondition('true', {}), isTrue);
    });

    test('empty condition is true (non-destructive default)', () {
      expect(evaluateCondition('', {}), isTrue);
      expect(evaluateCondition('   ', {}), isTrue);
    });

    test('an unknown bare token resolves to a falsy path (false)', () {
      // Not a crash — it parses as a path that is absent from the data.
      expect(evaluateCondition('nope', {}), isFalse);
    });

    test('|| inside a quoted string is not a split point', () {
      expect(evaluateCondition('s == "a||b"', {'s': 'a||b'}), isTrue);
    });
  });

  // Rendering: the chosen branch is what reaches the output.
  RenderContext ctx(FormConditionalBlock block, Map<String, dynamic> data) {
    final layout = FormLayoutPolicy(
      pageSize: const FormPageSize(size: 'A4', width: 210, height: 297),
      margins: const FormMargins(top: 20, right: 20, bottom: 20, left: 20),
      fontPolicy: const FormFontPolicy(
        defaultFont: 'x',
        defaultSize: 12,
        headingSize: 18,
        bodySize: 12,
        minSize: 8,
      ),
    );
    return RenderContext(
      document: FormDocument(
        documentId: 'd',
        templateId: 't',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(author: 'a', createdAt: DateTime(2026)),
        data: data,
        sections: [FormSection(sectionId: 's', index: 0, blocks: [block])],
      ),
      layoutPolicy: layout,
      template: FormTemplate(
        templateId: 't',
        version: '1.0.0',
        name: 'T',
        schema: const FormSchema(),
        layoutPolicy: layout,
      ),
      options: const RenderOptions(compress: false),
    );
  }

  FormConditionalBlock cond() => FormConditionalBlock(
        blockId: 'c',
        index: 0,
        condition: 'score >= 80',
        thenBlock: FormTextBlock(blockId: 't', index: 0, content: 'PASSED'),
        elseBlock: FormTextBlock(blockId: 'e', index: 0, content: 'FAILED'),
      );

  group('PDF conditional branch selection', () {
    test('true → thenBlock only', () async {
      final out = await const PdfRenderer().render(ctx(cond(), {'score': 90}));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      expect(pdf, contains('PASSED'));
      expect(pdf.contains('FAILED'), isFalse);
    });

    test('false → elseBlock only', () async {
      final out = await const PdfRenderer().render(ctx(cond(), {'score': 50}));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      expect(pdf, contains('FAILED'));
      expect(pdf.contains('PASSED'), isFalse);
    });

    test('false with no elseBlock → nothing rendered', () async {
      final block = FormConditionalBlock(
        blockId: 'c',
        index: 0,
        condition: 'score >= 80',
        thenBlock: FormTextBlock(blockId: 't', index: 0, content: 'ONLYTHEN'),
      );
      final out = await const PdfRenderer().render(ctx(block, {'score': 10}));
      final pdf = latin1.decode(out.content as List<int>, allowInvalid: true);
      expect(pdf.contains('ONLYTHEN'), isFalse);
    });
  });
}
