# pinbench_ui

The app's UI kit: the theme and its colour scale, the widget wrappers every
screen is built from, and the strings they show.

```
lib/
  theme/      the colour scale, tokens, typography, icons, the forui theme,
              and the theme-mode provider. Plus `testing.dart` — how to mount
              this kit in a test
  ui/         the wrappers: AppButton, AppDialog, AppSelect, AppToast, …
  widgets/    things composed *out of* ui/: the colour picker, the floating
              pane, the text-input dialog, the logs viewer
  strings.dart
```

## This is the only place that may name a widget library

`forui` and `lucide_icons_flutter` appear in `theme/` and `ui/` and nowhere
else — not in this package's own `widgets/`, and not anywhere in the app, which
no longer even lists them as dependencies. That is enforced by
`test/architecture/ui_library_boundary_test.dart` in the app, which scans both
sides of the boundary.

The point is not tidiness. A library's theme lookup and its buttons spread to
wherever they are wanted, and unpicking that later means editing every screen.
Swapping the library should mean rewriting this package.

The rule has already caught the mistake it exists for: while `ui/` and
`widgets/` sat in one directory, `text_input_dialog` reached straight for the
library's text field with `AppTextField` sitting beside it.

## The colours are checked, not chosen

Every foreground/background pair in `AppPalette` has been measured against WCAG
AA — 4.5:1 for body text, 3:1 for large text and non-text boundaries. Several
were below it before the scale was introduced, most severely the light-mode
accent pair at 1.85:1, which made active toolbar buttons nearly unreadable.

Two traps are recorded in the code and worth repeating: `muted` is a *surface*
and `mutedForeground` is the secondary *text* on it — an earlier scale had them
inverted — and the brand teal `#009696` is the identity colour but is
deliberately not an interactive fill, because white on it reaches only 3.6:1.

## One hand-written provider

`themeModeProvider` is a plain `NotifierProvider` rather than a generated
`@Riverpod`, so this package needs no `build_runner` step — which matters
because CI's per-package loop runs `pub get`, `analyze` and `test`, and nothing
else. A plain `NotifierProvider` is keep-alive already.

## The test harness ships in `lib/`

`theme/testing.dart` exports `appTestApp`, which mounts a widget under the same
theming the real app does. Both this package's tests and the app's use it — the
app's `test/support/harness.dart` is a one-line re-export — because a copy on
each side is a copy that drifts. It depends on no test framework; it returns a
widget.
