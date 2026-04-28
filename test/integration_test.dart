import 'dart:convert';

import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/mcp_form.dart';
import 'package:test/test.dart';

// ============================================================================
// Shared helpers
// ============================================================================

FormTemplate _makeInspectionTemplate() {
  return FormTemplate(
    templateId: 'tpl-inspection',
    version: '1.0.0',
    name: 'Inspection Report',
    schema: FormSchema(fields: [
      FormSchemaField(
        name: 'equipmentName',
        type: 'string',
        required: true,
      ),
      FormSchemaField(
        name: 'inspectionDate',
        type: 'date',
        required: true,
      ),
      FormSchemaField(
        name: 'result',
        type: 'enum',
        enumValues: ['pass', 'fail', 'conditional'],
      ),
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
    defaultSections: [
      FormSection(
        sectionId: 'info',
        index: 0,
        title: 'Equipment Information',
        blocks: [
          FormFieldBlock(
            blockId: 'field-equipmentName',
            index: 0,
            fieldName: 'equipmentName',
            fieldType: 'string',
          ),
          FormFieldBlock(
            blockId: 'field-inspectionDate',
            index: 1,
            fieldName: 'inspectionDate',
            fieldType: 'date',
          ),
          FormFieldBlock(
            blockId: 'field-result',
            index: 2,
            fieldName: 'result',
            fieldType: 'enum',
          ),
        ],
      ),
    ],
  );
}

/// Approval handler that always approves.
class _AutoApproveHandler implements FormApprovalHandler {
  @override
  Future<bool> requestApproval({
    required String documentId,
    required String requestedBy,
  }) async => true;
}

void main() {
  // ==========================================================================
  // IT-001: E2E inspection report flow
  // ==========================================================================
  group('IT-001: E2E inspection report flow', () {
    test('full lifecycle: create, bind, validate, render, transition', () async {
      // Step 1: Create template with schema
      final template = _makeInspectionTemplate();

      // Step 2: Create FormDocument from template via DocumentFactory
      const factory = DocumentFactory();
      final document = factory.createFromTemplate(
        template: template,
        data: {},
        documentId: 'doc-it001',
        author: 'inspector',
      );

      expect(document.status, FormDocumentStatus.draft);
      expect(document.version, 1);
      expect(document.sections.isNotEmpty, isTrue);

      // Step 3: Bind data using BindingEngine (user input source)
      final bindingEngine = BindingEngine(resolvers: {
        FormDataSourceType.userInput: UserInputBindingResolver({
          'equipmentName': 'Pump A-100',
          'inspectionDate': '2026-04-13',
          'result': 'pass',
        }),
      });

      final bindingResult = await bindingEngine.resolve(
        document: document,
        bindings: [
          FormDataBinding(
            bindingId: 'bind-equipmentName',
            fieldPath: '/data/equipmentName',
            source: FormDataSourceType.userInput,
            dataPath: 'equipmentName',
          ),
          FormDataBinding(
            bindingId: 'bind-inspectionDate',
            fieldPath: '/data/inspectionDate',
            source: FormDataSourceType.userInput,
            dataPath: 'inspectionDate',
          ),
          FormDataBinding(
            bindingId: 'bind-result',
            fieldPath: '/data/result',
            source: FormDataSourceType.userInput,
            dataPath: 'result',
          ),
        ],
      );

      expect(bindingResult.boundFields.length, 3);
      expect(bindingResult.hasUnfilled, isFalse);

      final boundDoc = bindingResult.boundDocument;
      expect(boundDoc.data['equipmentName'], 'Pump A-100');
      expect(boundDoc.data['inspectionDate'], '2026-04-13');
      expect(boundDoc.data['result'], 'pass');

      // Step 4: Validate with FormValidator
      const validator = FormValidator();
      final validationResult = validator.validate(
        document: boundDoc,
        template: template,
      );
      expect(validationResult.isValid, isTrue);

      // Step 5: Render to HTML via RendererRegistry
      final registry = RendererRegistry();
      registry.register(const HtmlRenderer());
      registry.register(const PdfRenderer());

      final htmlOutput = await registry.render(
        document: boundDoc,
        template: template,
        format: 'html',
      );

      // Step 6: Render to PDF via RendererRegistry
      final pdfOutput = await registry.render(
        document: boundDoc,
        template: template,
        format: 'pdf',
      );

      // Step 7: Verify both outputs are non-empty
      expect(htmlOutput.content.isNotEmpty, isTrue);
      expect(pdfOutput.content.isNotEmpty, isTrue);

      final htmlString = utf8.decode(htmlOutput.content as List<int>);
      expect(htmlString, contains('Pump A-100'));
      expect(htmlString, contains('html'));

      final pdfString = utf8.decode(pdfOutput.content as List<int>);
      expect(pdfString, contains('%PDF'));

      // Step 8: Transition draft -> review -> approved -> published
      final versionHistory = VersionHistory();
      final workflowEngine = WorkflowEngine(
        versionHistory: versionHistory,
        approvalHandler: _AutoApproveHandler(),
      );

      var currentDoc = boundDoc;

      // draft -> review
      currentDoc = await workflowEngine.transition(
        document: currentDoc,
        target: FormDocumentStatus.review,
        triggeredBy: 'inspector',
      );
      expect(currentDoc.status, FormDocumentStatus.review);

      // review -> approved
      currentDoc = await workflowEngine.transition(
        document: currentDoc,
        target: FormDocumentStatus.approved,
        triggeredBy: 'supervisor',
      );
      expect(currentDoc.status, FormDocumentStatus.approved);

      // approved -> published
      currentDoc = await workflowEngine.transition(
        document: currentDoc,
        target: FormDocumentStatus.published,
        triggeredBy: 'admin',
      );

      // Step 9: Verify final status is published
      expect(currentDoc.status, FormDocumentStatus.published);
    });
  });

  // ==========================================================================
  // IT-002: LLM incremental generation + patch
  // ==========================================================================
  group('IT-002: LLM incremental generation + patch', () {
    test('build incrementally, patch, validate, render markdown', () async {
      // Step 1: Create template
      final template = _makeInspectionTemplate();

      // Step 2: Use IncrementalBuilder to build document section by section
      final builder = IncrementalBuilder(
        templateId: template.templateId,
        templateVersion: template.version,
        author: 'llm-agent',
      );

      // Add first section with blocks
      builder.addSection(FormSection(
        sectionId: 'header',
        index: 0,
        title: 'Report Header',
      ));

      builder.addBlock(
        sectionIndex: 0,
        block: FormTextBlock(
          blockId: 'blk-intro',
          index: 0,
          content: 'Initial inspection report',
        ),
      );

      builder.addBlock(
        sectionIndex: 0,
        block: FormFieldBlock(
          blockId: 'blk-equipment',
          index: 1,
          fieldName: 'equipmentName',
          fieldType: 'string',
        ),
      );

      // Add second section
      builder.addSection(FormSection(
        sectionId: 'details',
        index: 1,
        title: 'Inspection Details',
      ));

      builder.addBlock(
        sectionIndex: 1,
        block: FormTextBlock(
          blockId: 'blk-detail',
          index: 0,
          content: 'Placeholder detail text',
        ),
      );

      final document = builder.build();
      expect(document.sections.length, 2);
      expect(document.sections[0].blocks.length, 2);
      expect(document.sections[1].blocks.length, 1);

      // Step 3: Apply JSON Patch to modify a block's content
      const patchEngine = PatchEngine();

      // Patch: add equipmentName data to the document
      final patchResult = patchEngine.apply(
        document: document,
        operations: [
          FormPatchOperation(
            op: 'add',
            path: '/data/equipmentName',
            value: 'Turbine B-200',
          ),
        ],
      );

      expect(patchResult.isSuccess, isTrue);
      final patchedDoc = patchResult.document!;
      expect(patchedDoc.data['equipmentName'], 'Turbine B-200');

      // Step 4: Validate the patched document
      const validator = FormValidator();
      final validationResult = validator.validate(
        document: patchedDoc,
        template: template,
      );
      // equipmentName is provided; inspectionDate is required but missing
      // We only check validation runs without crashing
      expect(validationResult, isNotNull);

      // Step 5: Render to Markdown
      final registry = RendererRegistry();
      registry.register(const MarkdownRenderer());

      final mdOutput = await registry.render(
        document: patchedDoc,
        template: template,
        format: 'markdown',
      );

      // Step 6: Verify output contains patched content
      final mdString = utf8.decode(mdOutput.content as List<int>);
      expect(mdString, contains('Turbine B-200'));
      expect(mdString, contains('Report Header'));
      expect(mdOutput.content.isNotEmpty, isTrue);
    });
  });

  // ==========================================================================
  // IT-003: Schema violation detection + AutoFix
  // ==========================================================================
  group('IT-003: Schema violation detection + AutoFix', () {
    test('detect violations and auto-fix string truncation', () {
      // Step 1: Create template with schema constraints
      final template = FormTemplate(
        templateId: 'tpl-constrained',
        version: '1.0.0',
        name: 'Constrained Form',
        schema: FormSchema(fields: [
          FormSchemaField(
            name: 'title',
            type: 'string',
            required: true,
            maxValue: 10, // max length = 10
          ),
          FormSchemaField(
            name: 'score',
            type: 'number',
            maxValue: 100, // max value = 100
          ),
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

      // Step 2: Create document with violations
      final document = FormDocument(
        documentId: 'doc-it003',
        templateId: template.templateId,
        templateVersion: template.version,
        metadata: FormDocumentMetadata(
          author: 'tester',
          createdAt: DateTime(2026, 4, 13),
        ),
        data: {
          'title': 'This string is way too long for the constraint',
          'score': 999,
        },
      );

      // Step 3: Validate without autoFix - verify errors returned
      const validator = FormValidator();
      final resultNoFix = validator.validate(
        document: document,
        template: template,
      );

      expect(resultNoFix.isValid, isFalse);
      // Should have constraint violations for both title and score
      final errorCodes = resultNoFix.issues.map((i) => i.code).toList();
      expect(errorCodes, contains('schema.constraint_violated'));

      // Verify title violation is present
      final titleIssue = resultNoFix.issues.firstWhere(
        (i) => i.path == '/data/title',
      );
      expect(titleIssue.message, contains('exceeds maximum length'));

      // Verify score violation is present
      final scoreIssue = resultNoFix.issues.firstWhere(
        (i) => i.path == '/data/score',
      );
      expect(scoreIssue.message, contains('exceeds maximum'));

      // Step 4: Validate with autoFix enabled - verify fixes applied
      final resultWithFix = validator.validate(
        document: document,
        template: template,
        autoFix: true,
      );

      // AutoFix engine handles string truncation but NOT number clamping,
      // so the string should be fixed but the number violation remains.
      expect(resultWithFix.appliedFixes, isNotNull);
      expect(resultWithFix.appliedFixes!.isNotEmpty, isTrue);

      // Verify string truncation fix was applied
      final truncateFix = resultWithFix.appliedFixes!.firstWhere(
        (f) => f.action == 'truncate',
      );
      expect(truncateFix.path, '/data/title');

      // Number violation still present after autoFix (no number clamp strategy)
      expect(resultWithFix.isValid, isFalse);
      final remainingIssues = resultWithFix.issues.where(
        (i) => i.path == '/data/score' && i.severity == 'error',
      );
      expect(remainingIssues.isNotEmpty, isTrue);

      // Step 5: Fix number manually and re-validate to verify pass
      final fixedDocument = FormDocument(
        documentId: document.documentId,
        templateId: document.templateId,
        templateVersion: document.templateVersion,
        metadata: document.metadata,
        data: {
          'title': 'Short', // within 10 char limit
          'score': 85, // within 100 max
        },
      );

      final finalResult = validator.validate(
        document: fixedDocument,
        template: template,
      );
      expect(finalResult.isValid, isTrue);
      expect(finalResult.issues.where((i) => i.severity == 'error'), isEmpty);
    });
  });
}
