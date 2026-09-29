import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The widget library is an implementation detail of `package:pinbench_ui`.
///
/// Everything else draws with the app's own components — `AppButton`,
/// `AppDialog`, `AppToast`, `context.appColors` — so replacing the library
/// means rewriting those wrappers instead of every screen that used it.
///
/// This is not a style preference. A library's theme lookup and its buttons
/// spread to wherever they are wanted, and unpicking that later means editing
/// every screen. A guard is cheaper, and a convention nothing checks is one
/// people forget.
void main() {
  /// Only these may name a widget library: `theme/` builds the theme objects
  /// it needs (and holds `AppIcons`), and `ui/` is the wrapper layer itself.
  ///
  /// `pinbench_ui`'s own `widgets/` is deliberately *not* on this list. What lives
  /// there is composed out of `ui/` — a colour picker, a floating pane, a text
  /// input dialog — so it has no business naming a library either. Keeping it
  /// out is what turns "prefer the wrappers" into something enforced: while
  /// the two sat in one directory, `text_input_dialog` reached straight for
  /// the library's text field with `AppTextField` sitting beside it.
  ///
  /// Note what the kit becoming a package did to the other half of this rule:
  /// nothing in `lib/` may name a library at all now, with no exception to
  /// carve out, because there is nothing left in the app that is allowed to.
  const allowedPrefixes = ['packages/pinbench_ui/lib/theme/', 'packages/pinbench_ui/lib/ui/'];

  /// Both sides of the boundary: the app, and the kit it draws with.
  const scanned = ['lib', 'packages/pinbench_ui/lib'];

  /// Packages whose types must not appear outside [allowedPrefixes].
  ///
  /// The icon set counts: it is a widget library's worth of API surface, and
  /// it spreads to as many files as a theme lookup does. Call sites name
  /// `AppIcons.delete`, not whichever glyph the vendor calls it.
  const uiLibraries = ['package:forui/', 'package:lucide_icons_flutter/'];

  /// Material is a design system like any other, and this app does not use it.
  ///
  /// Flutter 3.47 moved it out of the SDK into `package:material_ui`, which is
  /// what finally made that statement checkable: until then `material.dart`
  /// was one import away in every file and re-exported half of
  /// `flutter/widgets.dart`, so files pulled it in for `Text` and `Column` and
  /// nobody noticed. 244 of this repo's 540 Dart files imported it; fewer than
  /// twenty used anything from it.
  ///
  /// Unlike [uiLibraries] there is no allowed prefix. `pinbench_ui` may name the
  /// kit it is a wrapper for, but Material is not that kit — a wrapper around
  /// it would be a second design system in the tree, which is the thing this
  /// file exists to prevent. Both spellings are banned: the SDK's legacy
  /// library, still present and deprecated in the Fall release, and the
  /// standalone package that replaced it.
  const bannedEverywhere = ['package:flutter/material.dart', 'package:material_ui/'];

  Iterable<File> dartFilesIn(String directory) =>
      Directory(directory)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

  /// Every first-party root, app and packages alike.
  ///
  /// Wider than [scanned], which is only the two sides of the wrapper
  /// boundary. Material has no boundary to be on the right side of — the
  /// painters in `pinbench_parts` and the engine tests in `pinbench_sim` are as covered
  /// as the screens are.
  final firstParty = [
    'lib',
    'test',
    for (final package in Directory('packages').listSync().whereType<Directory>())
      for (final directory in const ['lib', 'test'])
        if (Directory('${package.path}/$directory').existsSync()) '${package.path}/$directory',
  ];

  /// The one import Material still has in this repo, and why.
  ///
  /// `FTextFieldStyle.border` is typed as Material's `InputBorder`, so
  /// `AppSelect` cannot say "no border" — the one thing it wants to say —
  /// without naming it. forui imports Material in 33 of its own files and has
  /// not migrated to 3.47 yet; it is tracked at duobaseio/forui#1159, itself
  /// blocked on flutter/flutter#191095.
  ///
  /// This list is a record of an upstream constraint, not a door. Adding to it
  /// means proving the same thing: that the kit's public API leaves no other
  /// way to express it. Delete the entry when forui's migration lands.
  const forcedByForui = {'packages/pinbench_ui/lib/ui/app_select.dart'};

  test('nothing in the repo imports Material', () {
    const exempt = {'test/architecture/ui_library_boundary_test.dart', ...forcedByForui};

    final offenders = [
      for (final directory in firstParty)
        for (final file in dartFilesIn(directory))
          if (!exempt.contains(file.path))
            for (final library in bannedEverywhere)
              if (file.readAsStringSync().contains(library)) '${file.path} imports $library',
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'These files import Material:\n${offenders.join('\n')}\n\n'
          'The app draws with `package:pinbench_ui` — `AppScaffold`, `AppSpinner`, '
          '`AppSelectionArea`, `AppPageRoute`, `AppPalette` — and with '
          '`package:flutter/widgets.dart` underneath it. If something is '
          'genuinely missing, add the wrapper to `packages/pinbench_ui/lib/ui/` '
          'rather than reaching for a second design system.',
    );
  });

  test('only the wrapper layer names a widget library', () {
    final offenders = [
      for (final directory in scanned)
        for (final file in dartFilesIn(directory))
          if (!allowedPrefixes.any(file.path.startsWith))
            for (final library in uiLibraries)
              if (file.readAsStringSync().contains(library)) '${file.path} imports $library',
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'These files reach past the wrapper layer:\n${offenders.join('\n')}\n\n'
          'Add or extend a component in packages/pinbench_ui/lib/widgets/ and use that '
          'instead, so the next library swap is a handful of files rather '
          'than all of them.',
    );
  });

  /// Tests are the other half of the boundary, and the half that bites later.
  ///
  /// A test naming the library keeps passing right up until the widget under
  /// it changes, and then fails looking like a product bug — `properties_view`
  /// went looking for a switch widget that no longer existed, and the canvas
  /// gesture test mounted its own themeless app and threw on a missing scope
  /// the moment the context menu became a forui popover.
  ///
  /// Only this file is exempt, since it has to spell the package names out in
  /// order to look for them. `test/support/` used to be too — it was where the
  /// theme got set up once so no other test had to — but that harness is now
  /// `package:pinbench_ui/testing.dart`, mounting the kit's theme from inside the
  /// kit, so the exemption was spent and is gone.
  ///
  /// The kit's own tests are scanned as well: a wrapper's test that asserts
  /// against the library's widget instead of the wrapper is the same mistake
  /// one layer down.
  test("tests reach for the app's widgets, not the library's", () {
    const exempt = ['test/architecture/ui_library_boundary_test.dart'];

    final offenders = [
      for (final directory in const ['test', 'packages/pinbench_ui/test'])
        for (final file in dartFilesIn(directory))
          if (!exempt.any(file.path.startsWith))
            for (final library in uiLibraries)
              if (file.readAsStringSync().contains(library)) '${file.path} imports $library',
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'These tests name a widget library directly:\n${offenders.join('\n')}\n\n'
          "Pump through `appTestApp` and assert against the app's own widgets, "
          'so swapping the library does not rewrite the suite.',
    );
  });
}
