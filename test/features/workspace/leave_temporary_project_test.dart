import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` (the type of ProviderScope.overrides) lives here in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';

import 'package:pinbench/core/auth/auth_provider.dart';
import 'package:pinbench_cloud/auth/auth_service.dart';
import 'package:pinbench_cloud/auth/auth_user.dart';
import 'package:pinbench/features/workspace/models/workspace_state.dart';
import 'package:pinbench/features/workspace/providers/workspace_files_provider.dart';
import 'package:pinbench/features/workspace/widgets/leave_temporary_project_dialog.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/ui/app_button.dart';

import '../../support/harness.dart';

/// Signed in, so the cloud is somewhere the project could go.
class _SignedInAuth implements AuthService {
  @override
  bool get enabled => true;

  @override
  AuthUser? get currentUser => const AuthUser(uid: 'u1');

  @override
  Stream<AuthUser?> get onAuthChanged => const Stream.empty();

  @override
  Future<AuthUser?> signInWithGoogle() async => currentUser;

  @override
  Future<void> signOut() async {}
}

class _FakeWorkspace extends WorkspaceFiles {
  _FakeWorkspace(this._state);

  final WorkspaceState _state;

  @override
  WorkspaceState build() => _state;
}

/// Pumps a button that runs the prompt and records what it answered.
Widget _app(List<Override> overrides, List<bool> answers) => ProviderScope(
  overrides: overrides,
  child: appTestApp(
    Consumer(
      builder: (context, ref, _) => AppButton(
        onPressed: () async => answers.add(await confirmLeavingTemporaryProject(context, ref)),
        child: const Text('leave'),
      ),
    ),
  ),
);

List<Override> _overrides(WorkspaceState state) => [
  workspaceFilesProvider.overrideWith(() => _FakeWorkspace(state)),
  authServiceProvider.overrideWithValue(const DisabledAuthService()),
];

void main() {
  // A saved project is already somewhere the user can find it, so leaving is
  // not a decision worth interrupting for.
  patrolWidgetTest('leaves a saved project without asking', ($) async {
    final answers = <bool>[];
    await $.pumpWidgetAndSettle(
      _app(_overrides(const WorkspaceState(workspacePath: '/tmp/project')), answers),
    );

    await $('leave').tap();
    await $.pumpAndSettle();

    expect(answers, [true]);
    expect($(AppStrings.leaveTemporaryTitle).exists, isFalse);
  });

  patrolWidgetTest('leaves when there is no project at all', ($) async {
    final answers = <bool>[];
    await $.pumpWidgetAndSettle(_app(_overrides(const WorkspaceState()), answers));

    await $('leave').tap();
    await $.pumpAndSettle();

    expect(answers, [true]);
  });

  patrolWidgetTest('asks before discarding a temporary project', ($) async {
    final answers = <bool>[];
    await $.pumpWidgetAndSettle(
      _app(
        _overrides(
          const WorkspaceState(workspacePath: '/tmp/fap_project_1/Untitled', isTemporary: true),
        ),
        answers,
      ),
    );

    await $('leave').tap();
    await $.pumpAndSettle();

    expect($(AppStrings.leaveTemporaryTitle).exists, isTrue);
    expect($(AppStrings.leaveTemporarySaveToComputer).exists, isTrue);
    // Signed out, so there is nowhere in the cloud to put it.
    expect($(AppStrings.leaveTemporarySaveToCloud).exists, isFalse);
    expect(answers, isEmpty, reason: 'still waiting on the answer');

    await $(AppStrings.leaveTemporaryDiscard).tap();
    await $.pumpAndSettle();

    expect(answers, [true]);
  });

  patrolWidgetTest('offers the cloud once signed in', ($) async {
    final answers = <bool>[];
    await $.pumpWidgetAndSettle(
      _app([
        workspaceFilesProvider.overrideWith(
          () => _FakeWorkspace(
            const WorkspaceState(workspacePath: '/tmp/fap_project_1/Untitled', isTemporary: true),
          ),
        ),
        authServiceProvider.overrideWithValue(_SignedInAuth()),
      ], answers),
    );

    await $('leave').tap();
    await $.pumpAndSettle();

    expect($(AppStrings.leaveTemporarySaveToCloud).exists, isTrue);
  });

  // Dismissing without answering is ambiguous, and the safe reading of an
  // ambiguous answer is the one that keeps the work: stay put.
  patrolWidgetTest('stays put when the prompt is dismissed', ($) async {
    final answers = <bool>[];
    await $.pumpWidgetAndSettle(
      _app(
        _overrides(
          const WorkspaceState(workspacePath: '/tmp/fap_project_1/Untitled', isTemporary: true),
        ),
        answers,
      ),
    );

    await $('leave').tap();
    await $.pumpAndSettle();
    await $.tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await $.pumpAndSettle();

    expect(answers, [false]);
  });
}
