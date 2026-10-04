import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinbench_cloud/auth/auth_service.dart';
import 'package:pinbench_cloud/auth/auth_user.dart';

import 'package:pinbench/core/auth/auth_provider.dart';
import 'package:pinbench/layout/bars/activity/activity_bar.dart';
import 'package:pinbench/layout/bars/activity/activity_bar_button.dart';
import 'package:pinbench/layout/bars/activity/activity_target.dart';

import '../support/harness.dart';

/// The account sidebar is sign-in and nothing else, so its button is only on
/// the rail when the build has an auth backend.
void main() {
  Future<void> pump(WidgetTester tester, AuthService auth) => tester.pumpWidget(
    ProviderScope(
      overrides: [authServiceProvider.overrideWithValue(auth)],
      child: appTestApp(const SizedBox(height: 600, child: ActivityBar())),
    ),
  );

  Finder accountButton() =>
      find.byWidgetPredicate((w) => w is ActivityBarButton && w.tab == ActivityBarTab.account);

  testWidgets('no account button when sign-in is not configured', (tester) async {
    await pump(tester, const DisabledAuthService());

    expect(accountButton(), findsNothing);
    expect(find.byType(SettingsTabButton), findsOneWidget, reason: 'settings stays');
  });

  testWidgets('an account button when it is', (tester) async {
    await pump(tester, _EnabledAuthService());

    expect(accountButton(), findsOneWidget);
  });
}

/// Sign-in configured, nobody signed in.
class _EnabledAuthService implements AuthService {
  @override
  bool get enabled => true;

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> get onAuthChanged => const Stream.empty();

  @override
  Future<AuthUser?> signInWithGoogle() async => null;

  @override
  Future<void> signOut() async {}
}
