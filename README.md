# MCP Form

Schema-based document generation for the MCP ecosystem: fixed templates filled with content produce consistently structured documents (résumés, reports, invoices, business cards, contracts). Implements the `FormPort` / `FormRendererPort` / `FormTemplatePort` Contract Layer defined in `mcp_bundle`.

## Components

- **Template** — field types, schema, layout policy, versioning, ecosystem / bundling.
- **Document** — object model, block types, sections, snapshots, lifecycle.
- **Validator** — form / layout / schema validators with an autofix engine.
- **Binding** — runtime data binding connecting templates to documents.
- **Rendering** — six output formats: PDF, HTML, DOCX, Markdown, UI DSL, and a pure-Dart PNG image. Rich styling & copy-fit, tables, charts, math, barcodes / QR, absolute placement & backgrounds, page frame / page breaks, and multilingual TrueType embedding.
- **LLM-native** — export a template as a JSON Schema so an LLM fills within its structure; per-field capacity feed-forward.
- **MCP tools** — the `form.*` tool surface (template management, filling, document lifecycle, rendering).
- **Standard port adapters** — implementations of the `mcp_bundle` form Contract Layer.

## Quick Start

```dart
import 'package:mcp_form/mcp_form.dart';

final template = FormTemplateFactory.create(...);
final doc = DocumentFactory.fromTemplate(template);

final validator = FormValidator();
final result = validator.validate(doc);
if (!result.isValid) {
  final fixed = AutofixEngine().apply(doc, result);
}
```

## Support

- [Issue Tracker](https://github.com/app-appplayer/mcp_form/issues)
- [Discussions](https://github.com/app-appplayer/mcp_form/discussions)

## License

MIT — see [LICENSE](LICENSE).
