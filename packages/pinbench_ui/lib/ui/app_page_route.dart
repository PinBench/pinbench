import 'package:flutter/widgets.dart';

/// A full-screen route that simply appears.
///
/// Replaces `MaterialPageRoute`, which left the SDK with the rest of Material
/// in Flutter 3.47. The two places that build one — the shell's window
/// bootstrap and the File ▸ New Window action — hand it to
/// `multiview_desktop` as the route every *window* mounts its content into,
/// and a window's first and only page has nothing to transition from. Material
/// was animating a slide nobody could see.
///
/// [barrierColor] and [maintainState] keep the defaults a `PageRoute` wants;
/// [opaque] is what makes this a page rather than an overlay.
class AppPageRoute<T> extends PageRoute<T> {
  AppPageRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  /// No transition, so no duration. `Duration.zero` rather than a short one:
  /// a nominal animation still costs a frame of the window's first paint.
  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);
}
