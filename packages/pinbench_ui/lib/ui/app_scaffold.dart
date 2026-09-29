import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';

/// The ground a route's content sits on: the themed background colour, and
/// nothing else.
///
/// Replaces `Scaffold`, which left the SDK with the rest of Material in
/// Flutter 3.47. Almost nothing it offered was in use here — this app draws
/// its own title bar, its own status bar and its own panes, and there is no
/// app bar, drawer, snack bar or floating action button anywhere in it. What
/// was actually load-bearing was `scaffoldBackgroundColor`, which is why a
/// bare `Scaffold(body: …)` is the shape every call site had.
///
/// The child padding is off: forui pads a scaffold's child for a phone
/// screen, and every surface here is either full-bleed or already carries its
/// own inset.
class const AppScaffold({super.key, required final Widget child}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => FScaffold(childPad: false, child: child);
}
