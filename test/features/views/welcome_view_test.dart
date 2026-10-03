import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` (the type of ProviderScope.overrides) lives here in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';
import 'package:pinbench_edition_api/side_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinbench/core/auth/auth_provider.dart';
import 'package:pinbench/core/edition/edition_provider.dart';
import 'package:pinbench_cloud/auth/auth_service.dart';
import 'package:pinbench/core/utils/shared_preferences_provider.dart';
import 'package:pinbench/features/workspace/providers/recent_workspaces_provider.dart';
import 'package:pinbench/features/workspace/services/template_service.dart';
import 'package:pinbench/layout/views/center/welcome_view.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/widgets/brand_logo.dart';

import '../../support/harness.dart';

Widget _app(List<Override> overrides) =>
    ProviderScope(overrides: overrides, child: appTestApp(const WelcomeView()));

List<Override> _baseOverrides(SharedPreferences prefs) => [
  sharedPreferencesProvider.overrideWithValue(prefs),
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

  patrolWidgetTest('a build from source leads with the start and template cards', ($) async {
    await $.pumpWidgetAndSettle(_app(_baseOverrides(prefs)));

    // The entry points the patrol journeys tap.
    expect($(AppStrings.newBlankProjectTitle).exists, isTrue);
    expect($(AppStrings.templatesSectionTitle).exists, isTrue);
  });

  patrolWidgetTest('the header is the brand lockup, still named for screen readers', ($) async {
    final semantics = $.tester.ensureSemantics();
    await $.pumpWidgetAndSettle(_app(_baseOverrides(prefs)));

    // Drawn, not typed: the kit's icon and outlined wordmark.
    expect($(BrandIcon).exists, isTrue);
    expect($(BrandWordmark).exists, isTrue);
    expect(find.bySemanticsLabel('PinBench'), findsOneWidget);
    semantics.dispose();
  });

  patrolWidgetTest("puts an edition side panel's entry above the cards", ($) async {
    const entry = Key('side-panel-welcome');
    await $.pumpWidgetAndSettle(
      _app([
        ..._baseOverrides(prefs),
        editionPanelProvider.overrideWithValue(
          SidePanel(
            build: (_) => const SizedBox(),
            welcome: (_) => const SizedBox(key: entry),
          ),
        ),
      ]),
    );

    expect($(entry).exists, isTrue);
    // The entry is a headline, not a replacement.
    expect($(AppStrings.newBlankProjectTitle).exists, isTrue);
    expect($(AppStrings.templatesSectionTitle).exists, isTrue);
  });
}
