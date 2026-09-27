import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` (the type of ProviderScope.overrides) lives here in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinbench/core/utils/shared_preferences_provider.dart';
import 'package:pinbench_ai/models/ai_config.dart';
import 'package:pinbench_ai/models/chat_message.dart';
import 'package:pinbench_ai/models/file_proposal.dart';
import 'package:pinbench/features/ai/providers/ai_chat_provider.dart';
import 'package:pinbench/features/ai/providers/ai_config_provider.dart';
import 'package:pinbench/features/ai/widgets/ai_chat_view.dart';
import 'package:pinbench/core/chrome/chrome_commands.dart';
import 'package:pinbench_ui/strings.dart';
import '../../support/chrome_commands.dart';
import '../../support/harness.dart';

class _FakeChat extends AiChat {
  _FakeChat(this._messages);

  final List<ChatMessage> _messages;

  @override
  List<ChatMessage> build() => _messages;
}

class _FakeConfig extends AiConfigController {
  _FakeConfig(this._config);

  final AiConfig _config;

  @override
  AiConfig build() => _config;
}

Widget _app(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: appTestApp(const SizedBox(width: 420, child: AiChatView())),
);

const _configured = AiConfig(model: 'test-model');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  patrolWidgetTest('sends the user to Settings when no model is set', ($) async {
    final prefs = await SharedPreferences.getInstance();
    final chrome = FakeChromeCommands();

    await $.pumpWidgetAndSettle(
      _app([
        sharedPreferencesProvider.overrideWithValue(prefs),
        availableAiModelsProvider.overrideWith((ref) async => const <String>[]),
        chromeCommandsProvider.overrideWithValue(chrome),
      ]),
    );

    expect($(AppStrings.aiNotConfiguredTitle).exists, isTrue);
    // The form lives in the Settings tab and only there — this pane is too
    // narrow for it, and a second copy of it drifts from the first.
    expect($('Ollama').exists, isFalse);
    expect($(AppStrings.aiBaseUrlLabel).exists, isFalse);

    await $(AppStrings.aiOpenSettings).tap();
    expect(chrome.calls, ['openSettingsTab']);
  });

  patrolWidgetTest('shows the empty state once a model is configured', ($) async {
    final prefs = await SharedPreferences.getInstance();

    await $.pumpWidgetAndSettle(
      _app([
        sharedPreferencesProvider.overrideWithValue(prefs),
        aiConfigControllerProvider.overrideWith(() => _FakeConfig(_configured)),
        availableAiModelsProvider.overrideWith((ref) async => const <String>[]),
      ]),
    );

    expect($(AppStrings.aiEmptyStateBody).exists, isTrue);
    expect($(AppStrings.aiNotConfiguredTitle).exists, isFalse);
  });

  patrolWidgetTest('renders a reply as prose plus an applyable proposal', ($) async {
    final prefs = await SharedPreferences.getInstance();

    await $.pumpWidgetAndSettle(
      _app([
        sharedPreferencesProvider.overrideWithValue(prefs),
        aiConfigControllerProvider.overrideWith(() => _FakeConfig(_configured)),
        availableAiModelsProvider.overrideWith((ref) async => const <String>[]),
        aiChatProvider.overrideWith(
          () => _FakeChat(const [
            ChatMessage(id: '1', role: ChatRole.user, text: 'blink an LED'),
            ChatMessage(
              id: '2',
              role: ChatRole.assistant,
              text: 'Here is the circuit.\n```cdl\nCircuit {\n}\n```',
              proposals: [FileProposal(kind: ProposalKind.circuit, content: 'Circuit {\n}\n')],
            ),
          ]),
        ),
      ]),
    );

    expect($('blink an LED').exists, isTrue);
    expect($('Here is the circuit.').exists, isTrue);
    expect($(AppStrings.aiProposalCircuitTitle).exists, isTrue);
    expect($(AppStrings.aiApply).exists, isTrue);
    // The code is behind a disclosure, so a long sketch cannot bury the chat.
    expect($('Circuit {').exists, isFalse);
  });

  patrolWidgetTest('a streaming turn shows progress rather than an empty bubble', ($) async {
    final prefs = await SharedPreferences.getInstance();

    await $.pumpWidgetAndSettle(
      _app([
        sharedPreferencesProvider.overrideWithValue(prefs),
        aiConfigControllerProvider.overrideWith(() => _FakeConfig(_configured)),
        availableAiModelsProvider.overrideWith((ref) async => const <String>[]),
        aiChatProvider.overrideWith(
          () => _FakeChat(const [
            ChatMessage(id: '1', role: ChatRole.user, text: 'blink'),
            ChatMessage(id: '2', role: ChatRole.assistant, text: '', isStreaming: true),
          ]),
        ),
      ]),
    );

    expect($(AppStrings.aiThinking).exists, isTrue);
  });

  patrolWidgetTest('a failed turn shows the error next to what was asked', ($) async {
    final prefs = await SharedPreferences.getInstance();

    await $.pumpWidgetAndSettle(
      _app([
        sharedPreferencesProvider.overrideWithValue(prefs),
        aiConfigControllerProvider.overrideWith(() => _FakeConfig(_configured)),
        availableAiModelsProvider.overrideWith((ref) async => const <String>[]),
        aiChatProvider.overrideWith(
          () => _FakeChat(const [
            ChatMessage(id: '1', role: ChatRole.user, text: 'blink'),
            ChatMessage(
              id: '2',
              role: ChatRole.assistant,
              text: '',
              error: 'Could not reach a model server at http://localhost:11434/v1.',
            ),
          ]),
        ),
      ]),
    );

    expect($('blink').exists, isTrue);
    expect($(find.textContaining('Could not reach a model server')).exists, isTrue);
  });
}
