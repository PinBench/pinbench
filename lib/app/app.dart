import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:feedback/feedback.dart';
import 'package:pinbench_ui/theme/app_ui_scope.dart';
import 'package:pinbench_ui/theme/forui_theme.dart';
import 'package:pinbench_ui/theme/theme.dart';

import 'router.dart';

/// Root widget: resolves light/dark from [themeModeProvider], mounts
/// [createAppRouter], and wraps the app in the feedback overlay.
///
/// Every window uses the same router — on the web it drives the browser URL
/// (e.g. `/t/blink` deep-links a template, back/forward works); on native
/// desktop each `multiview_desktop` window gets its own independent `App`
/// (and so its own [GoRouter]), giving both platforms one navigation model
/// instead of native bypassing routes with direct function calls.
class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  late final GoRouter _router = createAppRouter();

  @override
  Widget build(BuildContext context) {
    // The one brightness in the app that is not a guess. `AppThemeMode.system`
    // means "whatever the platform says", and this is where that question gets
    // asked; everything else — the forui theme, the toasts,
    // `context.appBrightness` — hangs off the answer, which is what keeps them
    // from disagreeing.
    //
    // `MaterialApp` used to resolve this from `themeMode` and hand it back
    // through `Theme.of` in its builder. With Material out of the SDK as of
    // Flutter 3.47 there is no `ThemeData` to route it through, so the
    // resolution is explicit — and being explicit, it is watched properly:
    // `MediaQuery.platformBrightnessOf` rebuilds this widget when the user
    // flips the OS between light and dark, which the old indirection also did
    // but by a route nobody could see.
    final brightness = ref
        .watch(themeModeProvider)
        .resolve(MediaQuery.platformBrightnessOf(context));

    return WidgetsApp.router(
      routerConfig: _router,
      // A `WidgetsApp` has no theme to take this from, and it is what shows
      // through behind a route transition and in the task switcher.
      color: fTheme(brightness).colors.background,
      // The corner ribbon sits over the pane-toggle buttons in the title bar,
      // and this app is used in debug more than it is built for release — the
      // window chrome says which build it is well enough.
      debugShowCheckedModeBanner: false,
      builder: (context, child) => BetterFeedback(
        isDesktop: true,
        // A plain `Text` in ordinary layout (a Row, a Column) inherits no
        // themed colour of its own and can end up invisible against the
        // background after a light/dark switch. Binding it here, where every
        // route's content mounts, means such a `Text` follows the theme
        // without needing its own explicit style.
        child: DefaultTextStyle.merge(
          style: TextStyle(color: fTheme(brightness).colors.foreground),
          // The theme and the toaster wrap the router's navigator, so dialogs
          // and other overlay routes mount inside them and inherit both.
          // `showFToast` throws without a toaster above it, and the toaster
          // has to sit inside the theme for the toasts it mounts to be themed.
          child: AppUiScope(brightness: brightness, child: child!),
        ),
      ),
    );
  }
}
