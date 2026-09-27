import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

import '../ui/app_page_route.dart';
import '../ui/app_scaffold.dart';
import 'forui_theme.dart';

/// Pumps [home] under the same theming the real app mounts.
///
/// Mirrors the app's root widget: a bare [WidgetsApp] on the outside, with the
/// forui theme, the scaffold's background and the toaster wrapping the content
/// that dialogs, menus and toasts mount into.
///
/// It was a `MaterialApp` until Flutter 3.47 moved Material out of the SDK.
/// Nothing was lost in the swap — what the app itself mounts is a
/// [WidgetsApp] too, so this harness is now closer to the real tree than it
/// was, not further from it.
///
/// Use this rather than a hand-rolled app wrapper in a test. A widget with a
/// bare wrapper keeps passing until whatever it contains grows a dependency on
/// the theme, and then fails in a way that reads like a product bug — which is
/// exactly what happened to the canvas gesture test when the context menu
/// moved to a forui popover and threw on a missing accessibility scope.
///
/// It mounts [AppScaffold] as well, so tests pass the widget under test
/// directly. They used to wrap it in a `Scaffold` themselves — 30-odd copies
/// of the same line, each one a chance to forget the background colour.
///
/// It lives in `lib/` rather than in a test folder because both this package's
/// tests and the app's need it, and a copy on each side is a copy that drifts.
/// It pulls in no test framework — it returns a widget.
///
/// And it lives under `theme/` rather than at the package root because
/// mounting the theme is what it does, which is the one job `theme/` is
/// allowed to name the widget library for — see the app's
/// `ui_library_boundary_test`. An exemption would have been the other way to
/// get there, and a worse one.
Widget appTestApp(Widget home, {Brightness brightness = Brightness.light}) => WidgetsApp(
  color: const Color(0xFF000000),
  // [home] rather than a router: every test pumps one screen, and a route
  // table would be three more things to keep in step for no gain. It is what
  // puts a `Navigator` in the tree, though, which is not optional — a dialog
  // is a pushed route, and `showAppDialog` throws without one.
  home: home,
  pageRouteBuilder: <T>(settings, builder) => AppPageRoute<T>(settings: settings, builder: builder),
  // Above the navigator, so dialogs and other overlay routes mount *inside*
  // the theme and the toaster and inherit both — the same reason the app's own
  // root wraps its router here rather than around it.
  builder: (context, child) => FTheme(
    data: fTheme(brightness),
    child: FToaster(child: AppScaffold(child: child!)),
  ),
);
