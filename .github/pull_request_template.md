## What and why

<!-- What changes, and what problem it solves. The diff shows what; this should
     explain why. Link the issue if there is one. -->

Closes #

## How it was verified

<!-- Tick what you actually ran, not what you assume passes. -->

- [ ] `dart analyze --fatal-infos` — clean
- [ ] `dart format lib test` — no changes
- [ ] `flutter test --exclude-tags arduino` — passing
- [ ] Tried it in the running app

## If you changed a painter

<!-- Delete this section if not applicable. -->

- [ ] `grid_alignment_test` still passes — every port is on the connection
      lattice. Nudging a pin offset to line artwork up will silently stop wires
      meeting breadboard holes.
- [ ] `real_world_dimensions_test` updated if a drawn size changed, in the
      `drawn X (real Y)` form, **and** the comment next to the constant matches.

## Notes for the reviewer

<!-- Anything you're unsure about, decisions you'd like a second opinion on, or
     things you deliberately left out of scope. -->
