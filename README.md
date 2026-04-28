# MCP Form

Form document creation, validation, rendering, and management for the MCP ecosystem. Implements the `FormPort` / `FormRendererPort` / `FormTemplatePort` Contract Layer defined in `mcp_bundle`.

## Components

- **Template** — field types, layout extensions, schema validator, defaults, summary, version compatibility / validator.
- **Document** — factory, extensions, summary.
- **Validator** — form / layout / schema validators with autofix engine.
- **Binding** — runtime data binding engine connecting templates to documents.
- **Standard port adapters** — implementations of `mcp_bundle` form Contract Layer.

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
