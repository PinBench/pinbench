/// Typed reads of a placed part's properties.
///
/// Properties arrive as whatever last wrote them — a bool or number from the
/// simulation, a string from the properties panel or a saved file — so every
/// painter used to coerce each one by hand. These are those coercions, once.
extension PartProperties on Map<String, dynamic>? {
  /// [key] as a bool: `true` or the string `'true'`.
  bool flag(String key) => switch (this?[key]) {
    final bool b => b,
    final String s => s == 'true',
    _ => false,
  };

  /// [key] as a number, or [fallback] when it is missing or unreadable.
  double number(String key, {double fallback = 0}) => switch (this?[key]) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s) ?? fallback,
    _ => fallback,
  };

  /// [key] as a 0–1 level — a brightness, a wiper's travel.
  double level(String key, {double fallback = 0}) =>
      number(key, fallback: fallback).clamp(0.0, 1.0);
}
