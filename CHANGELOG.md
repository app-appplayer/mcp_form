## [0.1.1] - 2026-05-23 - mcp_bundle 0.4.0 cascade

### Changed (cascade)
- `mcp_bundle` caret bumped from `^0.3.0` to `^0.4.0`. mcp_form does not touch `UiSection.pages` directly, so this release is a caret-only cascade. Consumers should bump to `^0.1.1`.

## [0.1.0] - 2026-04-28 - Initial Release

### Added
- Template subsystem — field types, layout extensions, schema validator, defaults, summary, version compatibility and validator.
- Document subsystem — factory, extensions, summary.
- Validator subsystem — form / layout / schema validators with autofix engine.
- Binding engine for runtime template-to-document data binding.
- Standard port adapters implementing `mcp_bundle` form Contract Layer (`FormPort`, `FormRendererPort`, `FormTemplatePort`).
