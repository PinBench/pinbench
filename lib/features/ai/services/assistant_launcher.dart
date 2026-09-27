import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../workspace/providers/workspace_files_provider.dart';
import '../../workspace/services/template_service.dart';
import '../providers/ai_chat_provider.dart';
import '../../../core/chrome/chrome_commands.dart';

part 'assistant_launcher.g.dart';

/// The launcher, for widgets that only hold a `WidgetRef`.
///
/// `keepAlive` is load-bearing, not an optimisation. An auto-disposing
/// provider read with `ref.read` has no listener, so it is disposed the moment
/// the read returns — and [AssistantLauncher.startFromPrompt] then throws on
/// its first `await`, having already created the workspace but not yet sent
/// the prompt. The caller is unmounted by then (opening a project closes the
/// welcome screen), so the failure is invisible: a blank project opens and
/// nothing else happens.
@Riverpod(keepAlive: true)
AssistantLauncher assistantLauncher(Ref ref) => AssistantLauncher(ref);

/// Starts a project from a prompt: opens somewhere to build, reveals the
/// assistant, and sends the first message.
///
/// This is the Welcome screen's one-box path — type what you want and land in
/// the editor with the assistant already working. It exists as a service
/// because it spans three domains (workspace, layout chrome, and the chat)
/// that otherwise have no reason to know about each other.
class AssistantLauncher {
  /// Creates a launcher bound to [ref].
  const AssistantLauncher(this.ref);

  /// Riverpod handle used to reach the workspace, layout and chat providers.
  final Ref ref;

  /// Opens a blank project if none is open, shows the assistant pane, and
  /// sends [prompt].
  ///
  /// A workspace is created up front rather than left to the first Apply, so
  /// the canvas the reply is about is on screen while it streams in — landing
  /// on the welcome screen watching text arrive with nowhere to put it reads
  /// as though nothing happened.
  Future<void> startFromPrompt(String prompt) async {
    if (prompt.trim().isEmpty) return;

    final files = ref.read(workspaceFilesProvider.notifier);
    if (ref.read(workspaceFilesProvider).workspacePath == null) {
      final path = await ref.read(templateServiceProvider).createBlankWorkspace();
      await files.openWorkspace(path, isTemporary: true);
    }

    // `closeWelcome` already reveals the pane when leaving the welcome screen;
    // asking for it explicitly keeps this correct if the launcher is ever
    // called from somewhere else, and reveals rather than toggles, so a pane
    // that is already open stays open.
    ref.read(chromeCommandsProvider)
      ..closeWelcome()
      ..setPaneVisible(AppPane.right, visible: true);

    await ref.read(aiChatProvider.notifier).send(prompt);
  }
}
