import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` (the type of ProviderScope.overrides) lives here in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinbench/core/utils/shared_preferences_provider.dart';
import 'package:pinbench_ai/models/ai_config.dart';
import 'package:pinbench/features/ai/providers/ai_config_provider.dart';
import 'package:pinbench/layout/views/center/welcome/welcome_prompt_section.dart';
import 'package:pinbench/core/chrome/chrome_commands.dart';
import 'package:pinbench_ui/strings.dart';
import '../../support/chrome_commands.dart';
import '../../support/harness.dart';

class _FakeConfig extends AiConfigController {
  _FakeConfig(this._config);

  final AiConfig _config;

  @override
  AiConfig build() => _config;
}

const _configured = AiConfig(model: 'test-model');

Widget _app(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: appTestApp(const SizedBox(width: 700, child: WelcomePromptSection())),
);

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  patrolWidgetTest('offers a prompt box and examples once a model is set', ($) async {
    await $.pumpWidgetAndSettle(
      _app([
        sharedPreferencesProvider.overrideWithValue(prefs),
        aiConfigControllerProvider.overrideWith(() => _FakeConfig(_configured)),
        availableAiModelsProvider.overrideWith((ref) async => const <String>[]),
      ]),
    );

    expect($(AppStrings.welcomePromptHeading).exists, isTrue);
    expect($(AppStrings.welcomePromptStart).exists, isTrue);
    // The examples double as documentation for the level of detail that works.
    expect($(AppStrings.welcomePromptExamples.first).exists, isTrue);
  });

  // The box is what this screen is for, so it stays. What changes without a
  // model is that the screen says so and points at the one place that fixes
  // it — the settings form itself is not duplicated here.
  patrolWidgetTest('keeps the box and points at Settings when no model is set', ($) async {
    await $.pumpWidgetAndSettle(
      _app([
        sharedPreferencesProvider.overrideWithValue(prefs),
        availableAiModelsProvider.overrideWith((ref) async => const <String>[]),
      ]),
    );

    expect($(AppStrings.welcomePromptStart).exists, isTrue);
    expect($(AppStrings.aiNeedsSetupHint).exists, isTrue);
    expect($(AppStrings.aiOpenSettings).exists, isTrue);
    // The model form belongs to Settings now, not to the welcome screen.
    expect($('Ollama').exists, isFalse);
    expect($(AppStrings.aiBaseUrlLabel).exists, isFalse);
  });

  // Pressing Build it with nothing to send to opens Settings rather than
  // creating a project the assistant cannot act on.
  patrolWidgetTest('an unconfigured Build it goes to Settings', ($) async {
    final chrome = FakeChromeCommands();

    await $.pumpWidgetAndSettle(
      _app([
        sharedPreferencesProvider.overrideWithValue(prefs),
        availableAiModelsProvider.overrideWith((ref) async => const <String>[]),
        chromeCommandsProvider.overrideWithValue(chrome),
      ]),
    );

    await $(AppStrings.welcomePromptExamples.first).tap();

    expect(chrome.calls, ['openSettingsTab']);
  });
}
