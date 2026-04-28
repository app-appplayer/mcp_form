import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/adapters/form_port_impl.dart';
import 'package:mcp_form/src/adapters/form_template_port_impl.dart';
import 'package:mcp_form/src/core/workflow/transition_rule.dart';
import 'package:mcp_form/src/core/workflow/version_history.dart';
import 'package:test/test.dart';

FormTemplate _makeTemplate({String id = 'tpl-1'}) {
  return FormTemplate(
    templateId: id,
    version: '1.0.0',
    name: 'Test',
    schema: FormSchema(fields: [
      FormSchemaField(name: 'name', type: 'string', required: true),
    ]),
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

void main() {
  group('FormPortImpl', () {
    late FormTemplatePortImpl templatePort;
    late FormPortImpl port;

    setUp(() async {
      templatePort = FormTemplatePortImpl();
      await templatePort.saveTemplate(template: _makeTemplate());
      port = FormPortImpl(templatePort: templatePort);
    });

    // --- createDocument ---

    test('createDocument creates document from template', () async {
      final result = await port.createDocument(
        templateId: 'tpl-1',
        initialData: {'name': 'Alice'},
      );

      expect(result.success, isTrue);
      expect(result.data?.templateId, 'tpl-1');
      expect(result.data?.data['name'], 'Alice');
      expect(result.data?.status, FormDocumentStatus.draft);
      expect(result.data?.version, 1);
    });

    test('createDocument with custom id and author', () async {
      final result = await port.createDocument(
        templateId: 'tpl-1',
        initialData: {},
        documentId: 'my-doc',
        author: 'john',
      );

      expect(result.data?.documentId, 'my-doc');
      expect(result.data?.metadata.author, 'john');
    });

    test('createDocument fails for non-existent template', () async {
      final result = await port.createDocument(
        templateId: 'unknown',
        initialData: {},
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'form.template_not_found');
    });

    // --- getDocument ---

    test('getDocument retrieves created document', () async {
      await port.createDocument(
        templateId: 'tpl-1',
        initialData: {},
        documentId: 'doc-1',
      );

      final result = await port.getDocument(documentId: 'doc-1');
      expect(result.success, isTrue);
      expect(result.data?.documentId, 'doc-1');
    });

    test('getDocument fails for non-existent document', () async {
      final result = await port.getDocument(documentId: 'unknown');

      expect(result.success, isFalse);
      expect(result.error?.code, 'form.document_not_found');
    });

    // --- listDocuments ---

    test('listDocuments returns all documents', () async {
      await port.createDocument(
        templateId: 'tpl-1',
        initialData: {},
        documentId: 'doc-1',
      );
      await port.createDocument(
        templateId: 'tpl-1',
        initialData: {},
        documentId: 'doc-2',
      );

      final result = await port.listDocuments();
      expect(result.data!.length, 2);
    });

    test('listDocuments filters by templateId', () async {
      await templatePort.saveTemplate(
        template: _makeTemplate(id: 'tpl-2'),
      );
      await port.createDocument(
        templateId: 'tpl-1',
        initialData: {},
        documentId: 'doc-1',
      );
      await port.createDocument(
        templateId: 'tpl-2',
        initialData: {},
        documentId: 'doc-2',
      );

      final result = await port.listDocuments(templateId: 'tpl-2');
      expect(result.data!.length, 1);
      expect(result.data!.first.templateId, 'tpl-2');
    });

    test('listDocuments filters by status', () async {
      await port.createDocument(
        templateId: 'tpl-1',
        initialData: {},
        documentId: 'doc-1',
      );

      final result = await port.listDocuments(status: 'draft');
      expect(result.data!.length, 1);

      final noResults = await port.listDocuments(status: 'published');
      expect(noResults.data, isEmpty);
    });

    // --- validate ---

    test('validate returns validation result', () async {
      final createResult = await port.createDocument(
        templateId: 'tpl-1',
        initialData: {'name': 'Alice'},
      );

      final result = await port.validate(document: createResult.data!);
      expect(result.success, isTrue);
      expect(result.data, isNotNull);
    });

    test('validate fails for non-existent template', () async {
      final doc = FormDocument(
        documentId: 'doc-1',
        templateId: 'unknown-tpl',
        templateVersion: '1.0.0',
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026),
        ),
      );

      final result = await port.validate(document: doc);
      expect(result.success, isFalse);
      expect(result.error?.code, 'form.template_not_found');
    });

    // --- patch ---

    test('patch applies operations to document', () async {
      await port.createDocument(
        templateId: 'tpl-1',
        initialData: {'name': 'Alice'},
        documentId: 'doc-1',
      );

      final result = await port.patch(
        documentId: 'doc-1',
        operations: [
          FormPatchOperation(
            op: 'replace',
            path: '/data/name',
            value: 'Bob',
          ),
        ],
        targetVersion: 1,
      );

      expect(result.success, isTrue);
      expect(result.data?.data['name'], 'Bob');
      expect(result.data?.version, 2);
    });

    test('patch fails for non-existent document', () async {
      final result = await port.patch(
        documentId: 'unknown',
        operations: [],
        targetVersion: 1,
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'form.document_not_found');
    });

    test('patch fails on version conflict', () async {
      await port.createDocument(
        templateId: 'tpl-1',
        initialData: {'name': 'Alice'},
        documentId: 'doc-1',
      );

      final result = await port.patch(
        documentId: 'doc-1',
        operations: [
          FormPatchOperation(
            op: 'replace',
            path: '/data/name',
            value: 'Bob',
          ),
        ],
        targetVersion: 99,
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'form.version_conflict');
    });

    // --- getDocumentHistory ---

    test('getDocumentHistory returns version entries', () async {
      await port.createDocument(
        templateId: 'tpl-1',
        initialData: {'name': 'Alice'},
        documentId: 'doc-1',
      );

      // Patch to create a second version
      await port.patch(
        documentId: 'doc-1',
        operations: [
          FormPatchOperation(
            op: 'replace',
            path: '/data/name',
            value: 'Bob',
          ),
        ],
        targetVersion: 1,
      );

      final result = await port.getDocumentHistory(documentId: 'doc-1');
      expect(result.success, isTrue);
      expect(result.data!.length, 2);
    });

    test('getDocumentHistory returns empty for unknown document', () async {
      final result = await port.getDocumentHistory(documentId: 'unknown');
      expect(result.success, isTrue);
      expect(result.data, isEmpty);
    });

    // --- listDocuments with offset and limit ---

    test('listDocuments applies positive offset within range', () async {
      await port.createDocument(
        templateId: 'tpl-1',
        initialData: {},
        documentId: 'doc-a',
      );
      await port.createDocument(
        templateId: 'tpl-1',
        initialData: {},
        documentId: 'doc-b',
      );
      await port.createDocument(
        templateId: 'tpl-1',
        initialData: {},
        documentId: 'doc-c',
      );

      final result = await port.listDocuments(offset: 1);
      expect(result.data!.length, 2);
    });

    test('listDocuments applies limit that truncates results', () async {
      await port.createDocument(
        templateId: 'tpl-1',
        initialData: {},
        documentId: 'doc-a',
      );
      await port.createDocument(
        templateId: 'tpl-1',
        initialData: {},
        documentId: 'doc-b',
      );
      await port.createDocument(
        templateId: 'tpl-1',
        initialData: {},
        documentId: 'doc-c',
      );

      final result = await port.listDocuments(limit: 2);
      expect(result.data!.length, 2);
    });

    test('listDocuments with offset and limit combined', () async {
      await port.createDocument(
        templateId: 'tpl-1',
        initialData: {},
        documentId: 'doc-a',
      );
      await port.createDocument(
        templateId: 'tpl-1',
        initialData: {},
        documentId: 'doc-b',
      );
      await port.createDocument(
        templateId: 'tpl-1',
        initialData: {},
        documentId: 'doc-c',
      );

      final result = await port.listDocuments(offset: 1, limit: 1);
      expect(result.data!.length, 1);
    });

    // --- patch failure from PatchEngine ---

    test('patch fails when patch engine returns error', () async {
      await port.createDocument(
        templateId: 'tpl-1',
        initialData: {'name': 'Alice'},
        documentId: 'doc-1',
      );

      // Apply an invalid patch operation to a read-only path
      final result = await port.patch(
        documentId: 'doc-1',
        operations: [
          FormPatchOperation(
            op: 'replace',
            path: '/documentId',
            value: 'hack',
          ),
        ],
        targetVersion: 1,
      );

      expect(result.success, isFalse);
      expect(result.error?.code, 'form.patch_failed');
    });

    // --- getDocumentHistory with transition ---

    test('getDocumentHistory returns null changeDescription without transition',
        () async {
      await port.createDocument(
        templateId: 'tpl-1',
        initialData: {'name': 'Alice'},
        documentId: 'doc-1',
      );

      final result = await port.getDocumentHistory(documentId: 'doc-1');
      expect(result.success, isTrue);
      expect(result.data!.length, 1);
      // No transition recorded, so changeDescription should be null
      expect(result.data![0].changeDescription, isNull);
    });

    // Coverage: getDocumentHistory with transition present
    test('getDocumentHistory includes changeDescription from transition',
        () async {
      final versionHistory = VersionHistory();
      final portWithHistory = FormPortImpl(
        templatePort: templatePort,
        versionHistory: versionHistory,
      );

      // Create a document
      final createResult = await portWithHistory.createDocument(
        templateId: 'tpl-1',
        initialData: {'name': 'Alice'},
        documentId: 'doc-transition',
      );
      final doc = createResult.data!;

      // Manually record a version with a transition
      versionHistory.recordVersion(
        documentId: 'doc-transition',
        version: 2,
        document: doc,
        transition: TransitionResult(
          document: doc,
          from: FormDocumentStatus.draft,
          to: FormDocumentStatus.review,
          triggeredBy: 'tester',
          timestamp: DateTime.now(),
        ),
      );

      final result =
          await portWithHistory.getDocumentHistory(documentId: 'doc-transition');
      expect(result.success, isTrue);
      expect(result.data!.length, 2);

      // Find the version entry with a transition
      final withTransition =
          result.data!.firstWhere((v) => v.changeDescription != null);
      expect(withTransition.changeDescription, 'draft -> review');
    });
  });
}
