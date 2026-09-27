import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:patrol/patrol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinbench/app/app.dart';
import 'package:pinbench/core/utils/shared_preferences_provider.dart';

/// Shared Patrol configuration for the integration suite.
///
/// Keeping a single config here means every `patrolTest` in the suite uses the
/// same finder timeouts and settle behaviour.
const patrolConfig = PatrolTesterConfig(
  // The desktop UI animates panels/toasts; give finders a little more headroom
  // than the default before failing.
  existsTimeout: Duration(seconds: 15),
  visibleTimeout: Duration(seconds: 15),
);

/// Pumps the real [App] widget wrapped in the same provider overrides that
/// `main()` installs at runtime, so integration tests exercise the production
/// widget tree the user sees — minus the multi-window desktop shell (which is
/// irrelevant to UI behaviour and not available under the test binding).
///
/// The only provider `main()` *must* override is [sharedPreferencesProvider];
/// everything else resolves to its real implementation on-device.
Future<void> pumpApp(PatrolIntegrationTester $) async {
  // In-memory prefs keep each run deterministic and isolated from whatever is
  // persisted on the host machine. `patrol_test/` isn't an analyzer-recognised
  // test dir, so the @visibleForTesting guard needs an explicit ignore here.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  await $.pumpWidgetAndSettle(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const App(),
    ),
  );
}
