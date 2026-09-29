// Flutter imports:
import 'package:flutter/widgets.dart';

import '../../../painting/grid_system.dart';

/// Geometry of a solderless breadboard, in the board's own space.
///
/// **The board lies landscape.** Its long axis — the numbered rows, 1…30 or
/// 1…63 — runs along local **x**, and the banks stack down local **y**: power
/// rail, `a`–`e`, notch, `f`–`j`, power rail. That is how a breadboard is
/// printed and how every photo of one is taken, so it is the orientation the
/// part is drawn in rather than something the user has to rotate into.
///
/// The anatomy the names follow:
///  * **power rails** — the `+`/`-` pairs along the top and bottom edges, each
///    one single node for the full length of the board;
///  * **terminal strips** — the lettered rows either side of the middle, where
///    each numbered row of five holes (`a`–`e`, `f`–`j`) is one node joined
///    down the column;
///  * **centre notch** — the channel along the middle that keeps the two
///    terminal strips of a row electrically apart (and straddles a DIP chip).
///
/// One historical wrinkle: port ids say `left`/`right` (`sig_left_a_7`) for
/// what are now the top and bottom banks. Those ids are the on-disk format for
/// `.cdl` templates and saved projects, so they stay as they are.
@immutable
class BreadboardConfig {
  final int rowsCount;

  /// Holes per terminal strip: `a`–`e` in the top bank, `f`–`j` in the bottom.
  final colsCount = 5;

  /// Real MB-102 outline across the rows, for reference only — [boardBreadth]
  /// is derived rather than set to this, the same way [boardLength] is derived
  /// from [rowPadding]. See [boardBreadth] for why.
  ///
  /// 55 mm, not the 52 mm this used to claim: the notch is a full 0.3" wide
  /// (see [centerNotchCells]) and the rails have to clear it, which is exactly
  /// why the real part is 55 mm rather than 52.
  static const realBoardBreadthMm = 55;

  // One full hole pitch of padding: keeps the first bank ≡ cellCenter mod
  // pitch, so every hole sits on the shared connection lattice (see
  // GridSystem.pitch) regardless of cell size.
  final padding = GridSystem.pitch;

  final gridCellSize = GridSystem.cellSize;
  final gridCellStep = GridSystem.cellSize * 2;

  /// Symmetric by construction, the cross-axis twin of [boardLength].
  ///
  /// This used to be pinned to [realBoardBreadthMm] while every band inside it
  /// was derived from the lattice, so the two disagreed and the leftover fell
  /// entirely on the bottom edge: the top rail's `+` line sat 12 px inside the
  /// board and the bottom rail's `−` line 14.46 px, and the board read
  /// lopsided.
  ///
  /// Deriving it instead gives an equal margin at both edges. The rail ink runs
  /// half a cell outside its hole line on each side (`PowerRailConfig`'s
  /// `plusLineOffset` / `minusLineOffset`), so mirroring the top margin below
  /// the bottom rail is exactly one [gridCellStep] past [bottomPowerRailY],
  /// plus [topPowerRailY] again. That lands at 54.61 mm — 0.39 mm under the
  /// real part, and unlike the pinned value it cannot drift when a band moves.
  late final boardBreadth = topPowerRailY + bottomPowerRailY + gridCellStep;

  late final powerRailCells = 3; // plus rail + inter-rail gap + minus rail
  late final sideMarginCells = powerRailCells + 1; // 1 = row-number band

  /// The channel between the two terminal strips, in whole hole pitches of
  /// clear space between row `e` and row `f`.
  ///
  /// TWO cells, which puts `e`→`f` three pitches apart — 0.3", the DIP lead
  /// span the notch exists to straddle. It is not decoration: a 6 mm tactile
  /// switch's legs are 0.3" apart too, so at one cell (two pitches) a button
  /// laid across the notch reached `e`→`g` and could never sit in the row
  /// pair it's meant to bridge. Anything that spans the notch — DIP chips,
  /// buttons, DIP switches — is built to this number.
  final centerNotchCells = 2;

  // ---------------------------------------------------------------------
  // Across the board (local y): the five bands, top to bottom.
  // ---------------------------------------------------------------------

  /// The `+` hole line of the top power rail, and the anchor every other band
  /// is measured from.
  late final topPowerRailY = padding + GridSystem.cellCenter;

  /// Row `a` — the first hole line of the top terminal strip.
  late final topTerminalStripY = topPowerRailY + sideMarginCells * gridCellStep;

  /// Row `e`, where the top strip ends, for anything that spans or clears the
  /// notch.
  late final topTerminalStripEndY = topTerminalStripY + (colsCount - 1) * gridCellStep;

  /// Row `f` — the first hole line of the bottom terminal strip.
  late final bottomTerminalStripY =
      topPowerRailY + (sideMarginCells + centerNotchCells + colsCount) * gridCellStep;

  late final bottomLabelStartCells = sideMarginCells + centerNotchCells + 2 * colsCount;

  /// The band of row numbers printed under the bottom strip.
  late final bottomRowLabelY = topPowerRailY + bottomLabelStartCells * gridCellStep;

  /// Two cells past the bottom row-number band, not one: the rail's hole lines
  /// start at its origin (see `PowerRailConfig`), so one cell would leave the
  /// bottom rail a pitch closer to the numbers than the top one is, and the
  /// board would read lopsided.
  late final bottomPowerRailY = topPowerRailY + (bottomLabelStartCells + 2) * gridCellStep;

  /// The centre notch: the moulded channel that separates a row's two terminal
  /// strips, so `a`–`e` and `f`–`j` of the same number are different nodes.
  late final centerNotchCenterY = (topTerminalStripEndY + bottomTerminalStripY) / 2;

  /// How thick the channel is *drawn*, which is not how wide the gap is: the
  /// electrical spacing is [centerNotchCells] (three pitches, `e`→`f`), while
  /// the grey band is one pitch, leaving a full pitch of plain board between
  /// each edge and the `e`/`f` hole lines. Narrowing this changes nothing
  /// about where parts plug in.
  late final centerNotchThickness = gridCellStep;

  // ---------------------------------------------------------------------
  // Along the board (local x): the numbered rows.
  // ---------------------------------------------------------------------

  /// Board edge to the first hole row, and the last hole row to the far edge —
  /// the same at both ends, with the letter band sitting inside it.
  ///
  /// Both axes are derived; this is the knob for the length, as the band stack
  /// is for [boardBreadth]. Hole rows have to land on the connection lattice,
  /// so the padding is a WHOLE number of hole pitches and [boardLength] falls
  /// out of it.
  /// A real 82 mm half board leaves 4.2 mm at each end, which is not a whole
  /// pitch — one of the two has to give, and the lattice is what component
  /// legs land in.
  ///
  /// Half pitches are not available here however tidy they look: 1.5 pitches
  /// puts the first row at 28 px, which is half a pitch off the lattice, and
  /// takes every hole on the board with it — so nothing snapped to the grid
  /// can line up with a hole and every wire into the board comes out slanted.
  ///
  /// Changing it by whole pitches is legal but not free: it moves every hole
  /// row, and the bundled templates are wired by *position*, so their parts
  /// come out of the holes they were fitted to. Two pitches comes out at
  /// 85 mm / 169 mm, the closest the lattice gets to the real 82 mm / 165 mm
  /// while leaving the labels room.
  late final rowPadding = GridSystem.pitch * 2;

  late final firstRowX = rowPadding + GridSystem.cellCenter;
  late final lastRowX = firstRowX + (rowsCount - 1) * gridCellStep;

  /// Where row [row] (0-based) sits along the board.
  double rowX(int row) => firstRowX + row * gridCellStep;

  /// Symmetric by construction: [firstRowX] of board before the first row, the
  /// same after the last.
  late final boardLength = lastRowX + firstRowX;

  /// The two letter bands, just outside the first and last rows — the `A B C
  /// D E` printed down each end of the board.
  late final startLabelX = firstRowX - GridSystem.cellSize * 2;
  late final endLabelX = lastRowX + GridSystem.cellSize * 2;

  /// A printed board numbers the first row and then every fifth one (1, 5,
  /// 10, …) — a number against all 30 (or 64) rows turns the band into a wall
  /// of digits you can't read a position off.
  static const rowLabelInterval = 5;

  /// Rows at each end that sit outside the printed numbering.
  ///
  /// The numbering runs 1…60 down the middle of a full board and the two rows
  /// past each end carry no number, so the numbered field is centred. Without
  /// this the numbering started hard against the left end and every spare row
  /// piled up on the right, which read as though the board had been cut off.
  ///
  /// These rows are ordinary holes in every other respect — same lattice, same
  /// node, same `sig_…` ids, which stay 0-based over *all* [rowsCount] rows.
  /// Only the printed digit is affected.
  static const unnumberedEndRows = 2;

  /// The number printed against row [row] (0-based), or null if the row is one
  /// of the [unnumberedEndRows] at either end.
  int? rowNumber(int row) {
    final number = row - unnumberedEndRows + 1;
    if (number < 1 || number > rowsCount - 2 * unnumberedEndRows) return null;
    return number;
  }

  /// Whether row [row] (0-based) carries a printed number.
  bool isLabelledRow(int row) {
    final number = rowNumber(row);
    return number != null && (number == 1 || number % rowLabelInterval == 0);
  }

  /// Landscape: long axis first.
  Size get boardSize => Size(boardLength, boardBreadth);

  new _({required this.rowsCount});

  /// 30 rows — 26 of them numbered, plus the [unnumberedEndRows] at each end.
  factory half() => BreadboardConfig._(rowsCount: 30);

  /// 64 rows, so the printed numbering runs a full 1…60 with the
  /// [unnumberedEndRows] to spare at each end.
  factory full() => BreadboardConfig._(rowsCount: 64);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BreadboardConfig && runtimeType == other.runtimeType && rowsCount == other.rowsCount;

  @override
  int get hashCode => rowsCount.hashCode;
}
