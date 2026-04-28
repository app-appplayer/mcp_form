import 'package:mcp_bundle/mcp_bundle.dart';

import '../core/document/document_factory.dart';
import '../core/patch/patch_engine.dart';
import '../core/validator/form_validator.dart';
import '../core/workflow/version_history.dart';

/// In-memory implementation of [FormPort].
///
/// Delegates to [DocumentFactory], [FormValidator], [PatchEngine],
/// and [VersionHistory] for the actual business logic.
class FormPortImpl implements FormPort {
  FormPortImpl({
    required FormTemplatePort templatePort,
    DocumentFactory documentFactory = const DocumentFactory(),
    FormValidator validator = const FormValidator(),
    PatchEngine patchEngine = const PatchEngine(),
    VersionHistory? versionHistory,
  })  : _templatePort = templatePort,
        _documentFactory = documentFactory,
        _validator = validator,
        _patchEngine = patchEngine,
        _versionHistory = versionHistory ?? VersionHistory();

  final FormTemplatePort _templatePort;
  final DocumentFactory _documentFactory;
  final FormValidator _validator;
  final PatchEngine _patchEngine;
  final VersionHistory _versionHistory;
  final Map<String, FormDocument> _documents = {};

  @override
  Future<FormResult<FormDocument>> createDocument({
    required String templateId,
    required Map<String, dynamic> initialData,
    String? documentId,
    String? author,
  }) async {
    final templateResult = await _templatePort.getTemplate(
      templateId: templateId,
    );
    if (!templateResult.success || templateResult.data == null) {
      return FormResult.fail(FormError(
        code: 'form.template_not_found',
        message: 'Template "$templateId" not found',
      ));
    }

    final template = templateResult.data!;
    final document = _documentFactory.createFromTemplate(
      template: template,
      data: initialData,
      documentId: documentId,
      author: author,
    );

    _documents[document.documentId] = document;

    // Record initial version
    _versionHistory.recordVersion(
      documentId: document.documentId,
      version: document.version,
      document: document,
    );

    return FormResult.ok(document);
  }

  @override
  Future<FormResult<FormValidationResult>> validate({
    required FormDocument document,
    bool autoFix = false,
  }) async {
    final templateResult = await _templatePort.getTemplate(
      templateId: document.templateId,
      version: document.templateVersion,
    );
    if (!templateResult.success || templateResult.data == null) {
      return FormResult.fail(FormError(
        code: 'form.template_not_found',
        message: 'Template "${document.templateId}" not found',
      ));
    }

    final result = _validator.validate(
      document: document,
      template: templateResult.data!,
      autoFix: autoFix,
    );

    return FormResult.ok(result);
  }

  @override
  Future<FormResult<FormDocument>> getDocument({
    required String documentId,
  }) async {
    final document = _documents[documentId];
    if (document == null) {
      return FormResult.fail(FormError(
        code: 'form.document_not_found',
        message: 'Document "$documentId" not found',
      ));
    }
    return FormResult.ok(document);
  }

  @override
  Future<FormResult<List<FormDocument>>> listDocuments({
    String? templateId,
    String? status,
    int? limit,
    int? offset,
  }) async {
    var results = _documents.values.toList();

    if (templateId != null) {
      results = results.where((d) => d.templateId == templateId).toList();
    }
    if (status != null) {
      results = results.where((d) => d.status.name == status).toList();
    }

    final start = offset ?? 0;
    if (start >= results.length) {
      return FormResult.ok(const []);
    }
    if (start > 0) {
      results = results.sublist(start);
    }
    if (limit != null && limit < results.length) {
      results = results.sublist(0, limit);
    }

    return FormResult.ok(results);
  }

  @override
  Future<FormResult<FormDocument>> patch({
    required String documentId,
    required List<FormPatchOperation> operations,
    required int targetVersion,
  }) async {
    final document = _documents[documentId];
    if (document == null) {
      return FormResult.fail(FormError(
        code: 'form.document_not_found',
        message: 'Document "$documentId" not found',
      ));
    }

    // Version conflict check
    if (document.version != targetVersion) {
      return FormResult.fail(FormError(
        code: 'form.version_conflict',
        message:
            'Version conflict: expected $targetVersion, '
            'current ${document.version}',
      ));
    }

    final patchResult = _patchEngine.apply(
      document: document,
      operations: operations,
    );

    if (!patchResult.isSuccess || patchResult.document == null) {
      final errorMessage = patchResult.errors.isNotEmpty
          ? patchResult.errors.first.message
          : 'Patch operation failed';
      return FormResult.fail(FormError(
        code: 'form.patch_failed',
        message: errorMessage,
      ));
    }

    final patched = patchResult.document!;
    _documents[documentId] = patched;

    // Record new version
    _versionHistory.recordVersion(
      documentId: documentId,
      version: patched.version,
      document: patched,
    );

    return FormResult.ok(patched);
  }

  @override
  Future<FormResult<List<FormDocumentVersion>>> getDocumentHistory({
    required String documentId,
  }) async {
    final entries = _versionHistory.listVersions(documentId);
    final versions = entries.map((e) {
      return FormDocumentVersion(
        versionNumber: e.version,
        timestamp: e.recordedAt,
        author: e.snapshot.metadata.author,
        changeDescription: e.transition != null
            ? '${e.transition!.from.name} -> ${e.transition!.to.name}'
            : null,
      );
    }).toList();

    return FormResult.ok(versions);
  }
}
