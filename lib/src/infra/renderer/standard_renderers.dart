import '../../style/style_sheet.dart';
import '../../style/truetype_font.dart';
import 'renderer_registry.dart';
import 'renderers/docx_renderer.dart';
import 'renderers/html_renderer.dart';
import 'renderers/image_renderer.dart';
import 'renderers/markdown_renderer.dart';
import 'renderers/pdf_renderer.dart';
import 'renderers/ui_dsl_renderer.dart';

/// A [RendererRegistry] with the five bundled renderers registered
/// (PDF · HTML · DOCX · Markdown · UI DSL).
///
/// A bare `RendererRegistry()` is empty, so a `FormRendererPort` built over it
/// reports every format as unsupported — the reason `form.render` / `form.export`
/// fail with `render.unsupported_format` when a host forgets to register. This
/// factory is the intended default assembly for the `form.*` capability; pass
/// the font/style seams to make multilingual PDF and global styling reachable
/// through the tool path.
RendererRegistry standardRendererRegistry({
  FormStyleSheet? styleSheet,
  TrueTypeFont? embeddedFont,
  List<TrueTypeFont> fallbackFonts = const <TrueTypeFont>[],
}) {
  return RendererRegistry(
    styleSheet: styleSheet,
    embeddedFont: embeddedFont,
    fallbackFonts: fallbackFonts,
  )
    ..register(const PdfRenderer())
    ..register(const HtmlRenderer())
    ..register(const DocxRenderer())
    ..register(const MarkdownRenderer())
    ..register(const UiDslRenderer())
    ..register(const ImageRenderer());
}
