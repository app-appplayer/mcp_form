import 'dart:async';

import 'package:mcp_bundle/mcp_bundle.dart';

import 'transition_rule.dart';
import 'version_history.dart';

/// Simplified approval handler for form workflow transitions.
abstract class FormApprovalHandler {
  Future<bool> requestApproval({
    required String documentId,
    required String requestedBy,
  });
}

/// Simplified event handler for form workflow events.
abstract class FormEventHandler {
  Future<void> publish({
    required String topic,
    required Map<String, dynamic> payload,
  });
}

/// Manages document state transitions with approval and
/// version history support.
///
/// Default transition rules:
/// - draft -> review
/// - review -> approved (requires approval)
/// - review -> draft
/// - approved -> published
class WorkflowEngine {
  WorkflowEngine({
    FormApprovalHandler? approvalHandler,
    FormEventHandler? eventHandler,
    required this.versionHistory,
    List<TransitionRule>? customRules,
  })  : _approvalHandler = approvalHandler,
        _eventHandler = eventHandler,
        _rules = customRules ?? defaultRules;

  final FormApprovalHandler? _approvalHandler;
  final FormEventHandler? _eventHandler;
  final VersionHistory versionHistory;
  final List<TransitionRule> _rules;

  /// Default state transition rules.
  static List<TransitionRule> get defaultRules => [
        const TransitionRule(
          from: FormDocumentStatus.draft,
          to: FormDocumentStatus.review,
        ),
        const TransitionRule(
          from: FormDocumentStatus.review,
          to: FormDocumentStatus.approved,
          requiresApproval: true,
        ),
        const TransitionRule(
          from: FormDocumentStatus.review,
          to: FormDocumentStatus.draft,
        ),
        const TransitionRule(
          from: FormDocumentStatus.approved,
          to: FormDocumentStatus.published,
        ),
      ];

  /// Perform a state transition on a document.
  ///
  /// Throws [FormError] if the transition is invalid, approval is denied,
  /// or a precondition fails.
  Future<FormDocument> transition({
    required FormDocument document,
    required FormDocumentStatus target,
    required String triggeredBy,
    String? comment,
  }) async {
    final rule = _findRule(document.status, target);
    if (rule == null) {
      throw FormError(
        code: 'workflow.invalid_transition',
        message:
            'Cannot transition from ${document.status.name} '
            'to ${target.name}',
        path: '/status',
      );
    }

    // Check precondition
    if (rule.precondition != null) {
      final error = rule.precondition!(document);
      if (error != null) {
        throw FormError(
          code: 'workflow.precondition_failed',
          message: error,
          path: '/status',
        );
      }
    }

    // Request approval if required
    if (rule.requiresApproval && _approvalHandler != null) {
      final approved = await _approvalHandler!.requestApproval(
        documentId: document.documentId,
        requestedBy: triggeredBy,
      );
      if (!approved) {
        throw FormError(
          code: 'workflow.approval_denied',
          message: 'Approval denied for transition to ${target.name}',
          path: '/status',
        );
      }
    }

    final now = DateTime.now();
    final newVersion = document.version + 1;

    final updatedDocument = FormDocument(
      documentId: document.documentId,
      templateId: document.templateId,
      templateVersion: document.templateVersion,
      metadata: FormDocumentMetadata(
        author: document.metadata.author,
        createdAt: document.metadata.createdAt,
        modifiedAt: now,
        publishedAt: document.metadata.publishedAt,
        dataSource: document.metadata.dataSource,
        engineVersion: document.metadata.engineVersion,
      ),
      status: target,
      version: newVersion,
      sections: document.sections,
      data: document.data,
      bindings: document.bindings,
      validationIssues: document.validationIssues,
    );

    final transitionResult = TransitionResult(
      document: updatedDocument,
      from: document.status,
      to: target,
      triggeredBy: triggeredBy,
      comment: comment,
      timestamp: now,
    );

    // Record version
    versionHistory.recordVersion(
      documentId: document.documentId,
      version: newVersion,
      document: updatedDocument,
      transition: transitionResult,
    );

    // Publish event (fire-and-forget: failures do not block transition)
    if (_eventHandler != null) {
      final payload = <String, dynamic>{
        'documentId': document.documentId,
        'templateId': document.templateId,
        'from': document.status.name,
        'to': target.name,
        'version': newVersion,
        'triggeredBy': triggeredBy,
        'timestamp': now.toIso8601String(),
      };
      if (comment != null) {
        payload['comment'] = comment;
      }
      final future = _eventHandler!.publish(
        topic: 'workflow.state_changed',
        payload: payload,
      );
      unawaited(future.catchError((_) {}));
    }

    return updatedDocument;
  }

  /// Check whether a transition is valid.
  bool canTransition(FormDocumentStatus from, FormDocumentStatus to) {
    return _findRule(from, to) != null;
  }

  /// Get valid target states from the current state.
  List<FormDocumentStatus> validTargets(FormDocumentStatus current) {
    return _rules
        .where((r) => r.from == current)
        .map((r) => r.to)
        .toList();
  }

  TransitionRule? _findRule(
    FormDocumentStatus from,
    FormDocumentStatus to,
  ) {
    for (final rule in _rules) {
      if (rule.from == from && rule.to == to) return rule;
    }
    return null;
  }
}
