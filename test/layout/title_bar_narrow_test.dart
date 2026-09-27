import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/features/workspace/models/workspace_state.dart';
import 'package:pinbench/features/workspace/providers/workspace_files_provider.dart';
import 'package:pinbench/layout/bars/title/title_bar.dart';
import 'package:pinbench/shell/window.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import '../support/harness.dart';
import 'package:pinbench_ui/ui/app_icon_button.dart';

/// The title bar is the one row that spans the whole window, so it is the first
/// thing to break when the window gets narrow — it did, by 142px, the moment the
/// temporary-workspace badge went back into it.
///
/// The desktop runners set an 800x600 floor (`MainFlutterWindow.swift`,
/// `win32_window.cpp`, `my_application.cc`), but the web has no such floor: a
/// browser window can be any width at all. So this checks well below the
/// desktop minimum.
class _TemporaryWorkspace extends WorkspaceFiles {
  @override
  WorkspaceState build() => const WorkspaceState(workspacePath: '/tmp/blink', isTemporary: true);
}

class _FullScreen extends WindowIsFullScreen {
  _FullScreen({required this.fullScreen});

  final bool fullScreen;

  @override
  bool build() => fullScreen;
}

void main() {
  /// Widest first, so a failure list reads as "breaks below N".
  const widths = [1440.0, 1024.0, 800.0, 640.0, 480.0, 360.0];

  for (final width in widths) {
    testWidgets('lays out at ${width.toInt()}px wide', (tester) async {
      tester.view.physicalSize = Size(width, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [workspaceFilesProvider.overrideWith(_TemporaryWorkspace.new)],
          child: appTestApp(const Align(alignment: Alignment.topCenter, child: TitleBar())),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'the title bar overflowed at ${width.toInt()}px',
      );
    });
  }

  testWidgets('keeps every control at the narrowest width', (tester) async {
    Future<int> buttonsAt(double width) async {
      tester.view.physicalSize = Size(width, 200);
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [workspaceFilesProvider.overrideWith(_TemporaryWorkspace.new)],
          child: appTestApp(const Align(alignment: Alignment.topCenter, child: TitleBar())),
        ),
      );
      await tester.pumpAndSettle();
      return tester.widgetList(find.byType(AppIconButton)).length;
    }

    addTearDown(tester.view.reset);

    // Fitting by dropping buttons would also stop it overflowing, which is not
    // the fix that was made: the label truncates and the buttons all survive.
    //
    // Counted against a wide bar rather than against a number, so the test
    // keeps meaning "none were dropped" when a control is added or removed.
    // It used to assert that no Material `IconButton` was present, which was
    // vacuous — there was never one in this bar to find, at any width.
    final wide = await buttonsAt(1440);
    expect(wide, greaterThan(0), reason: 'the bar should have controls to keep');
    expect(await buttonsAt(360), wide);
    expect(tester.takeException(), isNull);
  });

  // Full screen takes the OS window controls away, and the space the bar holds
  // open for them becomes a gap with nothing in it — with the first control
  // stranded 70px from an empty corner.
  testWidgets('reclaims the traffic-light space in full screen', (tester) async {
    tester.view.physicalSize = const Size(1024, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The reserve is per-platform, and a widget test runs as Android, which
    // reserves nothing — without this the two cases are trivially identical
    // and the test passes whatever the code does.
    // Reset in a `finally` rather than an `addTearDown`: the framework checks
    // for leaked debug variables before tear-downs run, and reports the leak
    // instead of whatever the test was actually asserting.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    Future<double> homeButtonX({required bool fullScreen}) async {
      await tester.pumpWidget(
        ProviderScope(
          // Keyed, so each case gets its own container. Without it the second
          // pump keeps the first scope's element — and with it a keep-alive
          // notifier still holding the first case's answer.
          key: ValueKey(fullScreen),
          overrides: [
            workspaceFilesProvider.overrideWith(_TemporaryWorkspace.new),
            // Always present, never conditional: Riverpod asserts on a scope
            // whose override *count* changes between pumps.
            windowIsFullScreenProvider.overrideWith(() => _FullScreen(fullScreen: fullScreen)),
          ],
          child: appTestApp(const Align(alignment: Alignment.topCenter, child: TitleBar())),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getTopLeft(find.byIcon(AppIcons.home)).dx;
    }

    try {
      // Compared rather than asserted against 70: the reserve is per-platform,
      // and this says the reserve is *gone*, whatever it was.
      expect(await homeButtonX(fullScreen: true), lessThan(await homeButtonX(fullScreen: false)));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // A `Row` centres its middle child in what the other two leave over, and the
  // two sides of this bar are never the same width — so the title came out
  // visibly left of centre, and drifted further as the right-hand cluster grew.
  testWidgets('centres the title on the bar, not on what is left of it', (tester) async {
    tester.view.physicalSize = const Size(1440, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [workspaceFilesProvider.overrideWith(_TemporaryWorkspace.new)],
        child: appTestApp(const Align(alignment: Alignment.topCenter, child: TitleBar())),
      ),
    );
    await tester.pumpAndSettle();

    final bar = tester.getRect(find.byType(TitleBar));
    // The workspace name, whatever document happens to be beside it.
    final title = tester.getRect(find.textContaining('blink'));

    expect(title.center.dx, moreOrLessEquals(bar.center.dx, epsilon: 0.5));
  });

  // The bar sits in a `Column`, which offers it as much height as it likes, so
  // a layout that takes what it is offered takes infinity and the frame dies
  // during `performLayout`. It has to size itself to its tallest control, which
  // is what the `Row` it replaced did for free.
  testWidgets('sizes itself to its controls where nothing bounds its height', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [workspaceFilesProvider.overrideWith(_TemporaryWorkspace.new)],
        child: appTestApp(
          const Column(
            children: [
              TitleBar(),
              Expanded(child: SizedBox.expand()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final height = tester.getRect(find.byType(TitleBar)).height;
    expect(height, greaterThan(AppIconButtonSize.medium.size - 1), reason: 'room for a control');
    expect(height, lessThan(60), reason: 'a band of chrome, not a page');
  });
}
