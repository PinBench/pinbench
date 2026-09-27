// Project imports:
import 'breadboard_config.dart';

/// One of the board's two terminal-strip banks: the `a`–`e` lines above the
/// centre notch, or the `f`–`j` lines below it.
///
/// A *terminal strip* is one numbered row within a bank — five holes joined
/// across the bank, one node. The notch is why `a`–`e` and `f`–`j` of the same
/// row number are two independent strips rather than a run of ten.
class TerminalStripConfig {
  /// Where this bank prints its row numbers, relative to its own first hole
  /// line: above the `a`–`e` bank, below the `f`–`j` one.
  final double rowLabelRelY;

  /// Column ids, lower case because they go into port ids (`sig_left_a_3`).
  /// [columnDisplayLabels] is what gets printed on the board.
  final List<String> columnLabels;

  TerminalStripConfig._({required this.rowLabelRelY, required this.columnLabels});

  /// The top bank, `a`–`e`. Historically "left" — that's what its port ids say.
  factory TerminalStripConfig.left(BreadboardConfig config) => TerminalStripConfig._(
    rowLabelRelY: -config.gridCellStep,
    columnLabels: const ['a', 'b', 'c', 'd', 'e'],
  );

  /// The bottom bank, `f`–`j`. Historically "right".
  factory TerminalStripConfig.right(BreadboardConfig config) => TerminalStripConfig._(
    rowLabelRelY: config.colsCount * config.gridCellStep,
    columnLabels: const ['f', 'g', 'h', 'i', 'j'],
  );

  /// Real boards silk-screen the column letters in caps.
  List<String> get columnDisplayLabels => [for (final l in columnLabels) l.toUpperCase()];

  /// Holes per strip — the group of five the image calls out as "connected
  /// horizontally".
  int get holesPerStrip => columnLabels.length;
}
