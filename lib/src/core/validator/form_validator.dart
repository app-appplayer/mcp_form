import 'package:mcp_bundle/mcp_bundle.dart';

import 'autofix_engine.dart';
import 'layout_validator.dart';
import 'schema_validator.dart';

/// Facade that orchestrates schema validation, layout validation,
/// and optional auto-fix for a [FormDocument].
///
/// Combines [SchemaValidator] (data correctness) and [LayoutValidator]
/// (spatial constraints) into a single validation result.
class FormValidator {
  const FormValidator({
    SchemaValidator schemaValidator = const SchemaValidator(),
    LayoutValidator layoutValidator = const LayoutValidator(),
    AutoFixEngine autoFixEngine = const AutoFixEngine(),
  })  : _schemaValidator = schemaValidator,
        _layoutValidator = layoutValidator,
        _autoFixEngine = autoFixEngine;

  final SchemaValidator _schemaValidator;
  final LayoutValidator _layoutValidator;
  final AutoFixEngine _autoFixEngine;

  /// Validate a [document] against its [template].
  ///
  /// Performs both schema and layout validation. If [autoFix] is true,
  /// attempts to automatically correct fixable issues.
  ///
  /// Returns a [FormValidationResult] with combined errors and any
  /// applied fixes.
  FormValidationResult validate({
    required FormDocument document,
    required FormTemplate template,
    bool autoFix = false,
  }) {
    // Schema validation
    final schemaIssues = _schemaValidator.validate(
      document: document,
      schema: template.schema,
    );

    // Layout validation
    final layoutIssues = _layoutValidator.validate(
      document: document,
      layoutPolicy: template.layoutPolicy,
    );

    final allIssues = [...schemaIssues, ...layoutIssues];

    // Auto-fix if requested
    List<FormAutoFixAction>? appliedFixes;
    if (autoFix && allIssues.isNotEmpty) {
      final fixResult = _autoFixEngine.applyFixes(
        document: document,
        issues: allIssues,
        schema: template.schema,
      );
      appliedFixes = fixResult.fixes;

      // Re-validate after fixes to get updated issue list
      if (fixResult.fixes.isNotEmpty) {
        final revalidatedSchema = _schemaValidator.validate(
          document: fixResult.document,
          schema: template.schema,
        );
        final revalidatedLayout = _layoutValidator.validate(
          document: fixResult.document,
          layoutPolicy: template.layoutPolicy,
        );
        final remainingIssues = [...revalidatedSchema, ...revalidatedLayout];
        return FormValidationResult(
          isValid: remainingIssues
              .where((i) => i.severity == 'error')
              .isEmpty,
          issues: remainingIssues,
          appliedFixes: appliedFixes,
        );
      }
    }

    final hasErrors =
        allIssues.any((i) => i.severity == 'error');

    return FormValidationResult(
      isValid: !hasErrors,
      issues: allIssues,
      appliedFixes: appliedFixes,
    );
  }
}
