/// Generates unique, monotonically increasing IDs for canvas nodes and wires.
///
/// Replaces duplicated `_nodeIdCounter` / `_idCounter` statics in model classes.
final class IdGenerator {
  static var _counter = 0;

  /// Returns a unique ID with the given [prefix], e.g. `node_1720000000_42`.
  static String generate(String prefix) =>
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${_counter++}';
}
