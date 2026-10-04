import 'package:flutter/widgets.dart';
import 'package:pinbench/features/workspace/providers/workspace_files_provider.dart';
import 'package:pinbench/features/workspace/widgets/shared_project_banner.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinbench/core/auth/auth_provider.dart';
import 'package:pinbench/core/utils/shared_preferences_provider.dart';

import '../../../support/fake_auth.dart';
import '../../../support/harness.dart';

/// The banner sits unconditionally in the app layout, so "renders nothing" is its
/// normal state and the case most likely to regress unnoticed — a stray box
/// above every workspace would be a visible bug for every user, shared project
/// or not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
  });

  tearDown(() => container.dispose());

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: appTestApp(const SharedProjectBanner())),
  );

  testWidgets('renders nothing for a plain local workspace', (tester) async {
    await pump(tester);

    expect(find.byType(SizedBox), findsWidgets);
    expect(find.textContaining(AppStrings.sharedProjectBannerTitle), findsNothing);
    expect(find.text(AppStrings.sharedProjectBannerBody), findsNothing);
  });

  testWidgets('appears, and names the project, when viewing a shared one', (tester) async {
    final workspace = container.read(workspaceFilesProvider.notifier);
    workspace.state = workspace.state.copyWith(
      viewingSharedProjectId: 'p1',
      viewingSharedProjectName: 'Traffic light',
    );

    await pump(tester);

    expect(find.textContaining(AppStrings.sharedProjectBannerTitle), findsOneWidget);
    expect(find.textContaining('Traffic light'), findsOneWidget);
    // The banner has to state the consequence, not just the state — a visitor
    // who does not realise their edits are going nowhere is the failure case.
    expect(find.text(AppStrings.sharedProjectBannerBody), findsOneWidget);
  });

  testWidgets('survives a shared project with no name', (tester) async {
    final workspace = container.read(workspaceFilesProvider.notifier);
    workspace.state = workspace.state.copyWith(viewingSharedProjectId: 'p1');

    await pump(tester);

    expect(find.textContaining(AppStrings.sharedProjectBannerTitle), findsOneWidget);
  });

  testWidgets('offers sign-in rather than a dead button when signed out', (tester) async {
    // Sign-in configured, nobody signed in — the anonymous-visitor path,
    // which is exactly who follows a share link.
    container.dispose();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
        authServiceProvider.overrideWithValue(SignedOutAuthService()),
      ],
    );
    final workspace = container.read(workspaceFilesProvider.notifier);
    workspace.state = workspace.state.copyWith(
      viewingSharedProjectId: 'p1',
      viewingSharedProjectName: 'Blink',
    );

    await pump(tester);

    expect(find.text(AppStrings.sharedProjectSignInToCopy), findsOneWidget);
    expect(find.text(AppStrings.sharedProjectSaveCopyLabel), findsNothing);
  });

  testWidgets('disappears when the shared view is cleared', (tester) async {
    final workspace = container.read(workspaceFilesProvider.notifier);
    workspace.state = workspace.state.copyWith(
      viewingSharedProjectId: 'p1',
      viewingSharedProjectName: 'Blink',
    );
    await pump(tester);
    expect(find.textContaining(AppStrings.sharedProjectBannerTitle), findsOneWidget);

    // What "Save a copy" does on success: links the workspace to the new
    // project, which clears the shared view.
    workspace.state = workspace.state.copyWith(clearViewingShared: true);
    await tester.pump();

    expect(find.textContaining(AppStrings.sharedProjectBannerTitle), findsNothing);
  });

  testWidgets('points at no sign-in in a build that has none', (tester) async {
    // The default auth service is the disabled one: share links still open,
    // but there is no sign-in to save a copy with.
    final workspace = container.read(workspaceFilesProvider.notifier);
    workspace.state = workspace.state.copyWith(
      viewingSharedProjectId: 'p1',
      viewingSharedProjectName: 'Blink',
    );

    await pump(tester);

    expect(find.textContaining(AppStrings.sharedProjectBannerTitle), findsOneWidget);
    expect(find.text(AppStrings.sharedProjectSignInToCopy), findsNothing);
    expect(find.text(AppStrings.sharedProjectSaveCopyLabel), findsNothing);
  });
}
