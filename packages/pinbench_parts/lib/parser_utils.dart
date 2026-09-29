/// How a part's display name is written as a `.cdl` type token.
///
/// It lives beside the part model rather than in either file format because it
/// is a rule about a `PartModel`'s name: `.cdl` only ever sees the token.
abstract final class ParserUtils {
  /// The bare PascalCase-ish identifier a component's display [name] is written
  /// as in the `.cdl` (Slint-style element type): drops spaces and punctuation
  /// so `"Arduino Uno"` -> `ArduinoUno`, `"LED"` -> `LED`. Resolution back to the
  /// display name is by comparing this token (see `CircuitCanvasApplier`), so it
  /// need not be reversible on its own.
  static String typeToken(String name) => name.replaceAll(RegExp('[^A-Za-z0-9]'), '');
}
