import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` (the type of ProviderScope.overrides) lives here in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinbench/core/auth/auth_provider.dart';
import 'package:pinbench_cloud/auth/auth_service.dart';
import 'package:pinbench/core/utils/shared_preferences_provider.dart';
import 'package:pinbench_ai/models/ai_config.dart';
import 'package:pinbench/features/ai/providers/ai_config_provider.dart';
import 'package:pinbench/features/workspace/providers/recent_workspaces_provider.dart';
import 'package:pinbench/features/workspace/services/template_service.dart';
import 'package:pinbench/layout/views/center/welcome_view.dart';
import 'package:pinbench_ui/strings.dart';
import '../../support/harness.dart';

class _FakeConfig extends AiConfigController {
  _FakeConfig(this._config);

  final AiConfig _config;

  @override
  AiConfig build() => _config;
}

Widget _app(List<Override> overrides) =>
    ProviderScope(overrides: overrides, child: appTestApp(const WelcomeView()));

List<Override> _baseOverrides(SharedPreferences prefs) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
  aiConfigControllerProvider.overrideWith(() => _FakeConfig(const AiConfig(model: 'test-model'))),
  availableAiModelsProvider.overrideWith((ref) async => const <String>[]),
  // A real auth backend would try to reach the network from a widget test.
  authServiceProvider.overrideWithValue(const DisabledAuthService()),
  availableTemplatesProvider.overrideWith((ref) async => const ['blink']),
  recentWorkspacesProvider.overrideWith(_FakeRecents.new),
];

class _FakeRecents extends RecentWorkspaces {
  @override
  List<String> build() => const [];
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  // One welcome screen now: the mode toggle that used to choose between
  // leading with the prompt and leading with the cards is gone, so there is
  // no second arrangement left to test.
  patrolWidgetTest('leads with the prompt, keeping the cards below it', ($) async {
    await $.pumpWidgetAndSettle(_app(_baseOverrides(prefs)));

    expect($(AppStrings.welcomePromptHeading).exists, isTrue);
    // The prompt is the headline, not a replacement — the entry points the
    // existing patrol journeys tap stay on the screen beneath it.
    expect($(AppStrings.newBlankProjectTitle).exists, isTrue);
    expect($(AppStrings.templatesSectionTitle).exists, isTrue);
  });
}
