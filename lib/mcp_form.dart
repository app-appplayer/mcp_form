/// MCP Form - Form document creation, validation, rendering,
/// and management for the MCP ecosystem.
///
/// This package provides business logic for form document operations
/// using types defined in mcp_bundle (FormDocument, FormTemplate, etc.).
library;

// Core: Template utilities (MOD-CORE-001)
export 'src/core/template/field_type.dart';
export 'src/core/template/layout_extensions.dart';
export 'src/core/template/schema_validator.dart'
    show validateSchema; // hide TemplateSchemaValidator to avoid ambiguity
export 'src/core/template/template_defaults.dart';
export 'src/core/template/template_summary.dart';
export 'src/core/template/version_compatibility.dart';
export 'src/core/template/version_validator.dart';

// Core: Document factory and extensions (MOD-CORE-002)
export 'src/core/document/document_extensions.dart';
export 'src/core/document/document_factory.dart';
export 'src/core/document/document_summary.dart';

// Core: Validator (MOD-CORE-003)
export 'src/core/validator/autofix_engine.dart';
export 'src/core/validator/form_validator.dart';
export 'src/core/validator/layout_validator.dart';
export 'src/core/validator/schema_validator.dart';

// Core: Binding engine (MOD-CORE-004)
export 'src/core/binding/binding_engine.dart';
export 'src/core/binding/binding_exceptions.dart';
export 'src/core/binding/binding_resolver.dart';

// Core: Patch engine (MOD-CORE-005)
export 'src/core/patch/conflict_detector.dart';
export 'src/core/patch/incremental_builder.dart';
export 'src/core/patch/patch_engine.dart';

// Core: Workflow engine (MOD-CORE-006)
export 'src/core/workflow/signature_inserter.dart';
export 'src/core/workflow/transition_rule.dart';
export 'src/core/workflow/version_history.dart';
export 'src/core/workflow/workflow_engine.dart';

// Infrastructure: Renderer (MOD-INFRA-001)
export 'src/infra/renderer/layout_enforcer.dart';
export 'src/infra/renderer/render_context.dart';
export 'src/infra/renderer/renderer_registry.dart';
export 'src/infra/renderer/renderers/docx_renderer.dart';
export 'src/infra/renderer/renderers/html_renderer.dart';
export 'src/infra/renderer/renderers/markdown_renderer.dart';
export 'src/infra/renderer/renderers/pdf_renderer.dart';
export 'src/infra/renderer/renderers/ui_dsl_renderer.dart';

// Adapters: Port implementations
export 'src/adapters/form_port_impl.dart';
export 'src/adapters/form_renderer_port_impl.dart';
export 'src/adapters/form_template_port_impl.dart';

// Feature: MCP tools (MOD-FEAT-001)
export 'src/feat/mcp/form_resource_handler.dart';
export 'src/feat/mcp/form_tool_handler.dart';
export 'src/feat/mcp/mcp_types.dart';
