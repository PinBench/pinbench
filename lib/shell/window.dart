import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../app/app.dart';
import '../core/updates/update_providers.dart';

part 'window.g.dart';

/// `dependencies: []` because this one really is scoped: every window mounts a
/// `ProviderScope` below the global one and overrides this with its own id (see
/// `build` below), which is the whole point of it. The empty list says "may be
/// scoped, and depends on nothing else that is" — without it Riverpod treats
/// the provider as never-scoped and `scoped_providers_should_specify_dependencies`
/// objects, correctly.
@Riverpod(keepAlive: true, dependencies: [])
int windowId(Ref ref) => 0;

/// Whether this window is in the OS's full-screen mode.
///
/// Fed by [_FullScreenWatcher]. The chrome needs it because full screen takes
/// the window's own controls away: macOS hides the traffic lights, Windows and
/// Linux hide the caption buttons, and the space the title bar holds open for
/// them becomes a gap with nothing in it.
@Riverpod(keepAlive: true)
class WindowIsFullScreen extends _$WindowIsFullScreen {
  @override
  bool build() => false;

  void report({required bool fullScreen}) => state = fullScreen;
}

class Window extends ConsumerStatefulWidget {
  final int windowId;

  const Window({super.key, required this.windowId});

  @override
  ConsumerState<Window> createState() => _WindowState();
}

class _WindowState extends ConsumerState<Window> {
  @override
  void initState() {
    super.initState();
    _maximize();

    // The first window only. The update providers live in the root container,
    // so every extra window would be a second check against the same state —
    // and on Sparkle platforms a second native check on top of a running one.
    //
    // Deliberately not awaited and deliberately after the first frame: this
    // reaches the network, and nothing about it should sit between launch and
    // a usable window. It surfaces as the title bar's update badge if it
    // finds anything, and says nothing at all if it does not.
    if (widget.windowId != 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Sparkle keeps its own schedule across launches, so the stored
      // preference has to be pushed back into it — otherwise turning the
      // toggle off would hold only until the next launch.
      final automatic = ref.read(automaticUpdateChecksProvider);
      await ref.read(updateServiceProvider).setAutomaticChecks(enabled: automatic);
      await ref.read(updateControllerProvider.notifier).checkInBackground();
    });
  }

  /// Opens the app's window maximized.
  ///
  /// An IDE laid out as four panes around a canvas has nothing to show in an
  /// 800x600 default: the sidebars and the assistant leave the editor a
  /// column. Maximizing is the state a user would put it in anyway.
  ///
  /// After the first frame, because the OS window is only there to maximize
  /// once it has been shown. Addressed by id rather than through
  /// `MultiViewDesktop.of(context)`: `runMultiApp` hands this widget the same
  /// public view id, so there is no inherited scope to go looking for, and
  /// nothing here depends on where in the tree this sits.
  ///
  /// The root window only. A window opened from File ▸ New Window is a second
  /// place to work, and where it goes is the user's business — the OS will put
  /// it beside this one. The web has no OS window at all.
  void _maximize() {
    if (kIsWeb || widget.windowId != 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await MultiViewDesktop.fromId(widget.windowId).maximize();
    });
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [windowIdProvider.overrideWithValue(widget.windowId)],
    // On the web there is no OS window to be full screen, and nothing above
    // this to ask — `runApp` mounts it without the desktop shell's `ViewScope`,
    // which the watcher needs to find its window.
    child: kIsWeb ? const App() : const _FullScreenWatcher(child: App()),
  );
}

/// Keeps [windowIsFullScreenProvider] in step with the OS window.
///
/// A widget of its own, mounted under the desktop shell's `ViewScope`: the
/// window listener registers by context, and the title bar — the one place
/// that cares — is also rendered on its own in tests, where no such scope
/// exists.
class _FullScreenWatcher extends ConsumerStatefulWidget {
  const _FullScreenWatcher({required this.child});

  final Widget child;

  @override
  ConsumerState<_FullScreenWatcher> createState() => _FullScreenWatcherState();
}

class _FullScreenWatcherState extends ConsumerState<_FullScreenWatcher> with WindowListener {
  /// One query in flight at a time: `onWindowResize` fires many times a second
  /// while the window is moving, and each answer is a platform round trip.
  var _asking = false;

  @override
  void initState() {
    super.initState();
    // The window may already be full screen when this mounts — restored into
    // it by the OS, or put there before the first frame — so the state is read
    // once rather than waited for.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_askTheWindow()));
  }

  /// Asks the window itself rather than trusting the last event to arrive.
  ///
  /// This is what makes the change feel immediate. macOS posts
  /// `windowDidEnterFullScreen` — the event behind [onWindowEnterFullScreen] —
  /// only once its second-long zoom animation has *finished*, so a title bar
  /// waiting for it holds a gap where the traffic lights used to be for that
  /// whole second. The window's style mask carries `fullScreen` from the start
  /// of the animation, and resize events arrive throughout it, so the first of
  /// those gets the true answer while the window is still moving.
  Future<void> _askTheWindow() async {
    if (_asking || !mounted) return;
    _asking = true;
    try {
      final fullScreen = await MultiViewDesktop.of(context).isFullScreen();
      if (mounted) _report(fullScreen: fullScreen);
    } finally {
      _asking = false;
    }
  }

  void _report({required bool fullScreen}) =>
      ref.read(windowIsFullScreenProvider.notifier).report(fullScreen: fullScreen);

  @override
  void onWindowResize() => unawaited(_askTheWindow());

  // Kept even though a resize usually gets there first: both directions end in
  // one of these, so a dropped or throttled resize cannot leave the bar wrong.
  @override
  void onWindowEnterFullScreen() => _report(fullScreen: true);

  @override
  void onWindowLeaveFullScreen() => _report(fullScreen: false);

  @override
  Widget build(BuildContext context) => widget.child;
}
