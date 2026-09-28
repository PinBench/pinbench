# Contributing

Thanks for considering it. This project is most useful when the component
library and board support grow faster than one person can grow them, so
contributions are genuinely wanted rather than merely tolerated.

## Before a large change, open an issue

Small fixes: just send the PR. For anything larger — a new component, a new
board, a refactor, a new feature — **open an issue first** and describe what you
intend. It is a much better use of your time to find out in a comment thread
that something conflicts with the roadmap than in a closed PR.

## Setting up

```bash
git clone --recursive https://github.com/PinBench/pinbench.git
cd pinbench
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test --exclude-tags arduino
```

Cloned without `--recursive`? `git submodule update --init` fills in `packages/`.

### Changing a package

Most packages under `packages/` are ordinary folders in this repository: change
them in the same pull request as the app code that needs the change.

The two file formats are the exception. `pinbench_cdl` and `pinbench_pdl` are
meant for other tools as well, so each is a repository of its own
([`PinBench/cdl`](https://github.com/PinBench/cdl),
[`PinBench/pdl`](https://github.com/PinBench/pdl)), checked out here as a
submodule pinned to the commit the app is tested with. The app resolves both to
the checked-out copy, so an edit there takes effect immediately. To send one:
commit inside the submodule and open the pull request against that repository;
if the app needs it, a second pull request here moves the submodule pointer
(`git add packages/pinbench_pdl`).

Generated `*.g.dart` files are gitignored, so `build_runner` is not optional —
run it after every clone, pull, or branch switch.

The `arduino` tag marks tests that shell out to a local `arduino-cli`
toolchain. CI excludes them; run them locally with `arduino-cli` installed if
you touch the compile path.

## Before you push

CI runs these on every pull request; running them first saves a round trip.
`./setup_hooks.sh`, once after cloning, has git do it for you: the pre-commit
hook formats, sorts imports and analyzes what you staged, and the pre-push hook
runs the analysis and the tests below.

```bash
dart analyze --fatal-infos            # must be clean, infos included — as CI runs it
dart format lib test                  # page_width is 100, set in analysis_options.yaml
flutter test --exclude-tags arduino
for p in packages/*/; do [ -d "$p/test" ] && (cd "$p" && flutter test); done
                                      # packages are not covered by the root run
```

Packages under `packages/` carry their own `pubspec.yaml` and
`analysis_options.yaml` and are checked on their own terms — the root
`flutter analyze` excludes them and the root `flutter test` does not descend
into them. CI loops over every package, and so does the pre-push hook: all of
them are analyzed, and the ones with a `test/` directory are tested.
(`composite_plugin` is a generated analyzer plugin and has none.)

`flutter analyze` exits non-zero on **warnings and infos**, not just errors, so
"it compiles" is not the bar.

## Dependencies

Five dependencies come from Git forks rather than pub.dev, each for a stated
reason (WASM compatibility, a desktop fix, a pure-Dart port). They are pinned
to **commit SHAs, not branches**, so that `pub upgrade` cannot swap
third-party code underneath the project with nothing to review — the diff that
changes them is a diff in `pubspec.yaml`.

To move one forward, replace the `ref:` with the new commit and say why in the
commit message:

```bash
flutter pub get   # confirm pubspec.lock's resolved-ref matches what you pinned
```

The comment above each pin records which branch it was cut from, so you can
find the new head.

## What the tests are protecting

These test files encode invariants that are easy to break by accident and
expensive to notice later. If you change a painter, read the first two.

**`test/features/canvas/grid_alignment_test.dart`** — every connection point
(component port, breadboard hole) must sit on the shared lattice: `≡ cellCenter
mod pitch` on both axes. This is what makes a wire between two snapped parts come
out straight and a leg land in a hole. Nudging a pin offset to make the artwork
line up will break it, and the symptom — wires that no longer meet holes — looks
nothing like the cause.

**`packages/pinbench_parts/test/real_world_dimensions_test.dart`** — parts are drawn at
their true physical size, because the canvas scale is fixed by a breadboard's
0.1" hole pitch (16 px ≡ 2.54 mm). A few parts are deliberately drawn slightly
under datasheet size to read well next to their neighbours; those record both
figures, as `drawn X (real Y)`. If you change a drawn size, update the test in
that form and fix the comment beside the constant — otherwise the next person
finds a comment and a constant that disagree, with no way to tell which is
intended.

**`test/architecture/layering_test.dart`** — the module map in
The module boundaries are checked, not just described: no package imports the
app, `core/` depends on no feature, features never reach up into the chrome,
and a feature may only import another one in a listed direction. If your change adds
a dependency the map does not allow, this fails and names the exact import.

Prefer fixing the dependency — usually by moving shared vocabulary into
`package:pinbench_parts`, or by letting the chrome place a widget instead of the
feature commanding the layout. If it really is the right call, add it to the
allowlist in that file **with a comment saying why**. The allowlists are a
ratchet: a second assertion fails when an entry is no longer needed, so they
shrink over time and never silently grow.

## Adding a circuit part

Most parts need no Dart. A `.pdl` file plus an SVG describes the body, the
pins, the editable properties and the simulation behaviour, and the part
appears in the palette — see [`PDL.md`](packages/pinbench_pdl/doc/PDL.md), which ends with a
five-step recipe.

Reach for a hand-written painter in `packages/pinbench_parts/lib/painters/` only
when the part genuinely animates or hit-tests its own geometry, like the servo
horn or the breadboard.

## Style

Match the surrounding code. Beyond that:

- **Comments explain why, not what.** The codebase leans on this heavily —
  particularly around geometry, where a bare number is meaningless but "≡2 mod 8
  so ports land on the lattice after the 2× scale" prevents a real bug.
- **Keep the platform seams.** Platform-specific code lives behind
  `_io.dart` / `_web.dart` / `_stub.dart` implementations of a shared interface.
  Please do not sprinkle `kIsWeb` through feature code.
- **Canvas mutations go through `CanvasCommand`** so undo/redo keeps working.

## Commits and PRs

Conventional-commit prefixes (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`,
`ci:`, `build:`, `chore:`). Explain **why** in the body — the diff already shows
what.

Keep PRs to one logical change. A formatting sweep bundled with a behaviour
change is very hard to review, and impossible to revert cleanly.

## The CLA

Your first PR gets a comment from a bot asking you to sign the [CLA](CLA.md):
reply with the sentence it gives you. Once per repository, covering all your
future PRs there.

You keep your copyright — it is a licence, not an assignment — and it grants you
an explicit licence back to your own contribution. It exists so the project can
be dual-licensed, which is what funds the hosted service.

**Docs and typo fixes are exempt.** If you would rather not sign, open an issue
describing the change instead and someone can implement it.

## Reporting bugs

Include the platform, the app version, and a `.cdl` file plus sketch that
reproduce it — a circuit is much easier to debug than a description of one.

For anything security-related, **do not open a public issue** — see
[`SECURITY.md`](SECURITY.md).

## Code of conduct

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
