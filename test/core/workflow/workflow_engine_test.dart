import 'package:mcp_bundle/mcp_bundle.dart';
import 'package:mcp_form/src/core/workflow/transition_rule.dart';
import 'package:mcp_form/src/core/workflow/version_history.dart';
import 'package:mcp_form/src/core/workflow/workflow_engine.dart';
import 'package:test/test.dart';

FormDocument _makeDoc({
  FormDocumentStatus status = FormDocumentStatus.draft,
  int version = 1,
}) {
  return FormDocument(
    documentId: 'doc-1',
    templateId: 'tpl-1',
    templateVersion: '1.0.0',
    metadata: FormDocumentMetadata(
      author: 'tester',
      createdAt: DateTime(2026),
    ),
    status: status,
    version: version,
  );
}

class MockFormApprovalHandler implements FormApprovalHandler {
  MockFormApprovalHandler({this.approve = true});

  final bool approve;

  @override
  Future<bool> requestApproval({
    required String documentId,
    required String requestedBy,
  }) async => approve;
}

class MockFormEventHandler implements FormEventHandler {
  final List<Map<String, dynamic>> events = [];

  @override
  Future<void> publish({
    required String topic,
    required Map<String, dynamic> payload,
  }) async {
    events.add({'topic': topic, ...payload});
  }
}

void main() {
  group('WorkflowEngine - transitions', () {
    // TC-252: draft → review
    test('draft to review succeeds', () async {
      final engine = WorkflowEngine(versionHistory: VersionHistory());
      final result = await engine.transition(
        document: _makeDoc(),
        target: FormDocumentStatus.review,
        triggeredBy: 'user1',
      );

      expect(result.status, FormDocumentStatus.review);
      expect(result.version, 2);
    });

    // TC-253: review → approved (with approval)
    test('review to approved succeeds with approval', () async {
      final engine = WorkflowEngine(
        approvalHandler: MockFormApprovalHandler(),
        versionHistory: VersionHistory(),
      );
      final result = await engine.transition(
        document: _makeDoc(status: FormDocumentStatus.review),
        target: FormDocumentStatus.approved,
        triggeredBy: 'user1',
      );

      expect(result.status, FormDocumentStatus.approved);
    });

    // TC-254: review → draft
    test('review to draft succeeds', () async {
      final engine = WorkflowEngine(versionHistory: VersionHistory());
      final result = await engine.transition(
        document: _makeDoc(status: FormDocumentStatus.review),
        target: FormDocumentStatus.draft,
        triggeredBy: 'user1',
      );

      expect(result.status, FormDocumentStatus.draft);
    });

    // TC-255: approved → published
    test('approved to published succeeds', () async {
      final engine = WorkflowEngine(versionHistory: VersionHistory());
      final result = await engine.transition(
        document: _makeDoc(status: FormDocumentStatus.approved),
        target: FormDocumentStatus.published,
        triggeredBy: 'user1',
      );

      expect(result.status, FormDocumentStatus.published);
    });
  });

  group('WorkflowEngine - invalid transitions', () {
    // TC-256: draft → published
    test('draft to published fails', () async {
      final engine = WorkflowEngine(versionHistory: VersionHistory());

      expect(
        () => engine.transition(
          document: _makeDoc(),
          target: FormDocumentStatus.published,
          triggeredBy: 'user1',
        ),
        throwsA(isA<FormError>().having(
          (e) => e.code,
          'code',
          'workflow.invalid_transition',
        )),
      );
    });

    // TC-257: published → draft
    test('published to draft fails', () async {
      final engine = WorkflowEngine(versionHistory: VersionHistory());

      expect(
        () => engine.transition(
          document: _makeDoc(status: FormDocumentStatus.published),
          target: FormDocumentStatus.draft,
          triggeredBy: 'user1',
        ),
        throwsA(isA<FormError>().having(
          (e) => e.code,
          'code',
          'workflow.invalid_transition',
        )),
      );
    });
  });

  group('WorkflowEngine - approval', () {
    // TC-258: Approval denied
    test('throws when approval denied', () async {
      final engine = WorkflowEngine(
        approvalHandler: MockFormApprovalHandler(approve: false),
        versionHistory: VersionHistory(),
      );

      expect(
        () => engine.transition(
          document: _makeDoc(status: FormDocumentStatus.review),
          target: FormDocumentStatus.approved,
          triggeredBy: 'user1',
        ),
        throwsA(isA<FormError>().having(
          (e) => e.code,
          'code',
          'workflow.approval_denied',
        )),
      );
    });

    // TC-259: No FormApprovalHandler auto-approves
    test('auto-approves when no FormApprovalHandler configured', () async {
      final engine = WorkflowEngine(versionHistory: VersionHistory());
      final result = await engine.transition(
        document: _makeDoc(status: FormDocumentStatus.review),
        target: FormDocumentStatus.approved,
        triggeredBy: 'user1',
      );

      expect(result.status, FormDocumentStatus.approved);
    });
  });

  group('WorkflowEngine - version history', () {
    // TC-260: Transition records version
    test('transition records version in history', () async {
      final history = VersionHistory();
      final engine = WorkflowEngine(versionHistory: history);

      await engine.transition(
        document: _makeDoc(),
        target: FormDocumentStatus.review,
        triggeredBy: 'user1',
      );

      final entries = history.listVersions('doc-1');
      expect(entries.length, 1);
      expect(entries[0].version, 2);
      expect(entries[0].transition, isNotNull);
    });
  });

  group('WorkflowEngine - event publishing', () {
    // TC-261: No FormEventHandler doesn't throw
    test('works without FormEventHandler', () async {
      final engine = WorkflowEngine(versionHistory: VersionHistory());
      final result = await engine.transition(
        document: _makeDoc(),
        target: FormDocumentStatus.review,
        triggeredBy: 'user1',
      );

      expect(result.status, FormDocumentStatus.review);
    });

    // TC-263: Event payload
    test('publishes event with correct payload', () async {
      final eventPort = MockFormEventHandler();
      final engine = WorkflowEngine(
        eventHandler: eventPort,
        versionHistory: VersionHistory(),
      );

      await engine.transition(
        document: _makeDoc(),
        target: FormDocumentStatus.review,
        triggeredBy: 'user1',
        comment: 'Ready for review',
      );

      expect(eventPort.events.length, 1);
      expect(eventPort.events[0]['topic'], 'workflow.state_changed');
      expect(eventPort.events[0]['documentId'], 'doc-1');
      expect(eventPort.events[0]['from'], 'draft');
      expect(eventPort.events[0]['to'], 'review');
      expect(eventPort.events[0]['triggeredBy'], 'user1');
      expect(eventPort.events[0]['comment'], 'Ready for review');
    });
  });

  group('WorkflowEngine - queries', () {
    // TC-264-265: canTransition
    test('canTransition returns true for valid transitions', () {
      final engine = WorkflowEngine(versionHistory: VersionHistory());
      expect(
        engine.canTransition(
          FormDocumentStatus.draft,
          FormDocumentStatus.review,
        ),
        isTrue,
      );
    });

    test('canTransition returns false for invalid transitions', () {
      final engine = WorkflowEngine(versionHistory: VersionHistory());
      expect(
        engine.canTransition(
          FormDocumentStatus.draft,
          FormDocumentStatus.published,
        ),
        isFalse,
      );
    });

    // TC-266-268: validTargets
    test('validTargets from draft is [review]', () {
      final engine = WorkflowEngine(versionHistory: VersionHistory());
      expect(
        engine.validTargets(FormDocumentStatus.draft),
        [FormDocumentStatus.review],
      );
    });

    test('validTargets from review is [approved, draft]', () {
      final engine = WorkflowEngine(versionHistory: VersionHistory());
      expect(
        engine.validTargets(FormDocumentStatus.review),
        [FormDocumentStatus.approved, FormDocumentStatus.draft],
      );
    });

    test('validTargets from published is empty', () {
      final engine = WorkflowEngine(versionHistory: VersionHistory());
      expect(
        engine.validTargets(FormDocumentStatus.published),
        isEmpty,
      );
    });
  });

  group('WorkflowEngine - precondition', () {
    test('throws when precondition fails', () async {
      final customRules = [
        TransitionRule(
          from: FormDocumentStatus.draft,
          to: FormDocumentStatus.review,
          precondition: (doc) {
            if (doc.sections.isEmpty) {
              return 'Document must have at least one section';
            }
            return null;
          },
        ),
      ];

      final engine = WorkflowEngine(
        versionHistory: VersionHistory(),
        customRules: customRules,
      );

      expect(
        () => engine.transition(
          document: _makeDoc(),
          target: FormDocumentStatus.review,
          triggeredBy: 'user1',
        ),
        throwsA(isA<FormError>().having(
          (e) => e.code,
          'code',
          'workflow.precondition_failed',
        )),
      );
    });

    test('succeeds when precondition passes', () async {
      final customRules = [
        TransitionRule(
          from: FormDocumentStatus.draft,
          to: FormDocumentStatus.review,
          precondition: (doc) => null,
        ),
      ];

      final engine = WorkflowEngine(
        versionHistory: VersionHistory(),
        customRules: customRules,
      );

      final result = await engine.transition(
        document: _makeDoc(),
        target: FormDocumentStatus.review,
        triggeredBy: 'user1',
      );

      expect(result.status, FormDocumentStatus.review);
    });
  });
}
