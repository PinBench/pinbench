import 'package:flutter/foundation.dart';

/// Which kind of breadboard strip is being hovered.
///
/// The two names come straight off the board's anatomy: the `plus`/`minus`
/// **power rails** run the full length and are one node each, while a
/// **terminal strip** is a numbered row of five holes joined across, with the
/// centre notch splitting each row into an independent left and right strip.
enum BreadboardChannel() {
  plus,
  minus,
  terminalStrip,
}

/// Describes which breadboard hole/strip the cursor is over, so a component
/// being dragged can snap to it. Value type (`==`/`hashCode`) so it can drive
/// rebuilds without spurious churn.
@immutable
class const BreadboardHoverState({
  required final BreadboardChannel channel,

  /// The hole row under the cursor. For a terminal strip that is the numbered
  /// row; for a power rail it is the drilled row the pointer snapped to. Null
  /// means "the whole strip".
  final int? rowIndex,
  final bool isRightSide = false,
}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BreadboardHoverState &&
          runtimeType == other.runtimeType &&
          channel == other.channel &&
          rowIndex == other.rowIndex &&
          isRightSide == other.isRightSide;

  @override
  int get hashCode => Object.hash(channel, rowIndex, isRightSide);

  @override
  String toString() =>
      'BreadboardHoverState(channel: $channel, rowIndex: $rowIndex, isRightSide: $isRightSide)';
}
