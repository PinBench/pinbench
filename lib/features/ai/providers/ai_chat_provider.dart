import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:pinbench_ai/models/chat_message.dart';
import 'package:pinbench_ai/models/file_proposal.dart';
import 'package:pinbench_ai/clients/ai_client.dart';
import 'package:pinbench_ai/circuit_system_prompt.dart';
import 'package:pinbench_ai/proposal_extractor.dart';

import '../../../core/utils/logger.dart';
import '../../../core/parts/part_registry_provider.dart';
import '../../workspace/providers/workspace_files_provider.dart';
import '../services/proposal_applier.dart';
import '../services/workspace_context.dart';
import 'ai_config_provider.dart';

part 'ai_chat_provider.g.dart';

/// The assistant transcript, and the one place a request to the model is made.
///
/// `keepAlive` so the conversation survives the AI panel being hidden — the
/// natural workflow is ask, close the panel, look at the canvas, come back.
@Riverpod(keepAlive: true)
class AiChat extends _$AiChat {
  static const _log = AppLogger('app.ai.chat');

  StreamSubscription<String>? _subscription;

  /// Ids for chat messages, which only ever need to be distinct within one
  /// conversation — they are matched against `replyId` while a reply streams
  /// in, and never leave memory.
  ///
  /// A local counter rather than the shared `IdGenerator` this used to call:
  /// that helper moved into `package:pinbench_parts` with the circuit domain, where
  /// it stamps the persisted identity of nodes and wires. A chat bubble has no
  /// business importing the parts catalog to number itself.
  var _messageCounter = 0;
  String _nextMessageId() => 'msg_${_messageCounter++}';

  @override
  List<ChatMessage> build() {
    ref.onDispose(() => unawaited(_subscription?.cancel()));

    // A conversation is about a project. Leaving one ends it: otherwise going
    // home and asking for something else replays the previous circuit to the
    // model, which answers about that circuit instead — and the stale Apply
    // buttons above are still live, ready to write the old circuit into the
    // new project.
    //
    // Only on *leaving* a project (a path going null, or swapping straight to
    // another). Opening the first project of a thread keeps it, because that
    // is what the welcome prompt does: it starts the conversation and then
    // creates the workspace to put the answer in.
    ref.listen(workspaceFilesProvider, (before, after) {
      final was = before?.workspacePath;
      if (was == null || was == after.workspacePath) return;
      unawaited(clear());
    });

    return const [];
  }

  /// Whether a reply is currently streaming in.
  ///
  /// Private: the transcript is the public API, and the view derives this from
  /// the messages it already watches rather than reaching for the notifier.
  bool get _isStreaming => state.any((message) => message.isStreaming);

  /// Sends [prompt] and streams the reply into the transcript.
  ///
  /// Returns as soon as the request is under way; the UI follows the stream
  /// through the provider's state rather than by awaiting this.
  Future<void> send(String prompt) async {
    final text = prompt.trim();
    if (text.isEmpty || _isStreaming) return;

    final config = ref.read(aiConfigControllerProvider);
    final replyId = _nextMessageId();
    state = [
      ...state,
      ChatMessage(id: _nextMessageId(), role: ChatRole.user, text: text),
      ChatMessage(id: replyId, role: ChatRole.assistant, text: '', isStreaming: true),
    ];

    if (!config.isConfigured) {
      // Distinguish "nothing set up" from "set up but no key": a hosted
      // provider with the URL and model filled in but no key is the easy
      // mistake, and the provider's own error for it names an HTTP header
      // rather than the thing the user has to go and paste in.
      _fail(
        replyId,
        config.requiresKey && !config.isAuthenticated && config.model.trim().isNotEmpty
            ? '${config.baseUrl} needs an API key. Open the assistant settings '
                  '(the sliders icon) and paste one into the API key field.'
            : 'No model is configured yet. Open the assistant settings and point it '
                  'at a local server (Ollama, LM Studio) or a hosted provider.',
      );
      return;
    }

    final String system;
    try {
      // The catalog is fixed; the workspace is not, so it goes last. That does
      // cost prompt caching on providers that offer it — worth it, because a
      // stale circuit produces confidently wrong answers, and the alternative
      // is the user pasting their `.cdl` in by hand every time.
      system =
          CircuitSystemPrompt.build(await ref.read(partRegistryProvider.future)) +
          WorkspaceContext.build(ref);
    } catch (e) {
      _fail(replyId, 'Could not read the component palette: $e');
      return;
    }

    // History excludes the empty placeholder just appended — sending the model
    // a blank assistant turn asking to be filled in confuses smaller models.
    final history = state.where((message) => message.id != replyId).toList();

    final buffer = StringBuffer();
    await _subscription?.cancel();
    _subscription = ref
        .read(aiClientProvider)
        .streamChat(system: system, history: history)
        .listen(
          (chunk) {
            buffer.write(chunk);
            _update(replyId, (message) => message.copyWith(text: buffer.toString()));
          },
          onError: (Object error) {
            _log.error('AI request failed', error: error);
            _fail(replyId, error is AiException ? error.message : '$error');
          },
          onDone: () {
            final reply = buffer.toString();
            _update(
              replyId,
              (message) => message.copyWith(
                text: reply,
                proposals: ProposalExtractor.extract(reply),
                isStreaming: false,
              ),
            );
          },
          cancelOnError: true,
        );
  }

  /// Stops an in-flight reply, keeping whatever text already arrived.
  ///
  /// The partial text keeps its proposals extracted from what completed, so
  /// stopping a model that has already written the circuit but is rambling
  /// through an explanation still leaves something applyable.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    state = [
      for (final message in state)
        if (message.isStreaming)
          message.copyWith(isStreaming: false, proposals: ProposalExtractor.extract(message.text))
        else
          message,
    ];
  }

  /// Empties the transcript, cancelling anything in flight.
  Future<void> clear() async {
    await _subscription?.cancel();
    _subscription = null;
    state = const [];
  }

  /// Writes [proposal] into the workspace. Returns the path written.
  Future<String> apply(FileProposal proposal) => ProposalApplier(ref).apply(proposal);

  void _update(String id, ChatMessage Function(ChatMessage) transform) {
    state = [
      for (final message in state)
        if (message.id == id) transform(message) else message,
    ];
  }

  void _fail(String id, String error) =>
      _update(id, (message) => message.copyWith(isStreaming: false, error: error));
}
