import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:pinbench/app/router.dart';

/// Every route in this app renders the same screen — the IDE — and differs
/// only in which document it opens into it. They therefore all sit under one
/// shell, so navigating swaps a side effect rather than building a second
/// `Layout`, `PlatView` and canvas and throwing the first away.
///
/// A structural test because that is exactly what is easy to lose: moving a
/// route out of the shell still compiles, still navigates, and quietly costs a
/// whole IDE rebuild per navigation.
void main() {
  test('every screen route lives under the one shell', () {
    expect($appRoutes, hasLength(1), reason: 'a route outside the shell rebuilds the IDE');

    final shell = $appRoutes.single;
    expect(shell, isA<ShellRoute>());

    final paths = (shell as ShellRoute).routes.map((route) => (route as GoRoute).path);
    expect(paths, containsAll(<String>['/', '/t/:template', '/p/:projectId']));
  });
}
