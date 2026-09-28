import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` (the type of ProviderScope.overrides) lives here in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinbench/core/telemetry/telemetry_consent.dart';
import 'package:pinbench/core/utils/shared_preferences_provider.dart';
import 'package:pinbench/layout/views/center/privacy_panel.dart';
import 'package:pinbench/layout/views/center/settings_tab_view.dart';
import 'package:pinbench/layout/views/center/welcome/welcome_consent_card.dart';
import 'package:pinbench_ui/strings.dart';
import '../../support/harness.dart';

/// Records what the consent UI asked of telemetry.
class _FakeControl implements TelemetryControl {
  _FakeControl({this.available = true});

  @override
  final bool available;

  @override
  String? get privacyPolicyUrl => 'https://example.com/privacy';

  final applied = <bool>[];

  @override
  void applyConsent({required bool granted}) => applied.add(granted);
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  List<Override> overrides(TelemetryControl control) => [
    sharedPreferencesProvider.overrideWithValue(prefs),
    telemetryControlProvider.overrideWithValue(control),
  ];

  group('consent', () {
    test('is unknown until the user answers — and nothing is collected then', () {
      expect(readTelemetryConsent(prefs), TelemetryConsent.unknown);
    });

    test('an answer is applied at once and survives a restart', () async {
      final control = _FakeControl();
      final container = ProviderContainer(overrides: overrides(control));
      addTearDown(container.dispose);

      await container.read(telemetryConsentProvider.notifier).choose(granted: true);
      expect(control.applied, [true]);
      expect(readTelemetryConsent(prefs), TelemetryConsent.granted);

      await container.read(telemetryConsentProvider.notifier).choose(granted: false);
      expect(control.applied, [true, false]);
      expect(readTelemetryConsent(prefs), TelemetryConsent.denied);
    });

    test('a build without telemetry has no control to apply to', () {
      expect(const NoTelemetry().available, isFalse);
      expect(const NoTelemetry().privacyPolicyUrl, isNull);
    });
  });

  group('the welcome question', () {
    Widget app(TelemetryControl control) =>
        ProviderScope(overrides: overrides(control), child: appTestApp(const WelcomeConsentCard()));

    patrolWidgetTest('is asked when the build has telemetry and no answer yet', ($) async {
      await $.pumpWidgetAndSettle(app(_FakeControl()));
      expect($(AppStrings.telemetryConsentTitle).exists, isTrue);
      expect($(AppStrings.privacyPolicyLink).exists, isTrue);
    });

    patrolWidgetTest('is never asked in a build without telemetry', ($) async {
      await $.pumpWidgetAndSettle(app(_FakeControl(available: false)));
      expect($(AppStrings.telemetryConsentTitle).exists, isFalse);
    });

    patrolWidgetTest('goes away once answered, and applies the answer', ($) async {
      final control = _FakeControl();
      await $.pumpWidgetAndSettle(app(control));

      await $(AppStrings.telemetryConsentDecline).tap();

      expect(control.applied, [false]);
      expect($(AppStrings.telemetryConsentTitle).exists, isFalse);
      expect(readTelemetryConsent(prefs), TelemetryConsent.denied);
    });
  });

  group('settings', () {
    Widget app(TelemetryControl control) =>
        ProviderScope(overrides: overrides(control), child: appTestApp(const SettingsTabView()));

    patrolWidgetTest('have a privacy section only when the build has telemetry', ($) async {
      await $.pumpWidgetAndSettle(app(_FakeControl()));
      expect($(PrivacyPanel).exists, isTrue);

      await $.pumpWidgetAndSettle(app(_FakeControl(available: false)));
      expect($(PrivacyPanel).exists, isFalse);
    });
  });
}
