import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

import 'forui_theme.dart';

/// Installs everything the app's widgets need from the UI library.
///
/// Today that is forui's theme and its toast host. Wrapping them means the
/// composition root says *what* it is mounting rather than *whose* it is, and
/// a future library swap changes this file instead of `app.dart` and every
/// test harness.
///
/// Must sit inside whatever owns the navigator, so dialogs and toasts pushed
/// as routes are still below it.
class const AppUiScope({
  super.key,
  required final Brightness brightness,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => FTheme(
    data: fTheme(brightness),
    child: FToaster(child: child),
  );
}
