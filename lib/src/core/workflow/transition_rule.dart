import 'package:mcp_bundle/mcp_bundle.dart';

/// Rule defining a valid state transition.
class TransitionRule {
  const TransitionRule({
    required this.from,
    required this.to,
    this.requiresApproval = false,
    this.precondition,
  });

  final FormDocumentStatus from;
  final FormDocumentStatus to;
  final bool requiresApproval;

  /// Optional precondition validator. Returns an error message
  /// if the precondition is not met, null if OK.
  final String? Function(FormDocument document)? precondition;
}

/// Result of a state transition.
class TransitionResult {
  const TransitionResult({
    required this.document,
    required this.from,
    required this.to,
    required this.triggeredBy,
    this.comment,
    required this.timestamp,
  });

  final FormDocument document;
  final FormDocumentStatus from;
  final FormDocumentStatus to;
  final String triggeredBy;
  final String? comment;
  final DateTime timestamp;
}
