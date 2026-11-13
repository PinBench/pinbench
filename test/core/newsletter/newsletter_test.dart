import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinbench/core/newsletter/newsletter.dart';
import 'package:pinbench/core/utils/shared_preferences_provider.dart';
import 'package:pinbench/features/simulation/providers/simulation_provider.dart';
import 'package:pinbench/layout/components/newsletter_first_run_prompt.dart';
import 'package:pinbench/layout/views/center/welcome/welcome_newsletter_card.dart';
import 'package:pinbench_sim/models/simulation_state.dart';
import 'package:pinbench_ui/strings.dart';

import '../../support/harness.dart';

const _url = 'https://pinbench.web.app/newsletter';

/// Holds whatever state a test sets, without a runner behind it.
class _FakeSimulation extends Simulation {
  @override
  SimulationState build() => SimulationState.stopped;

  void set(SimulationState next) => state = next;
}

void main() {
  late SharedPreferences prefs;
  late List<String> opened;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    opened = [];
  });

  ProviderContainer container({String? url = _url}) {
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        newsletterUrlProvider.overrideWithValue(url),
        newsletterLauncherProvider.overrideWithValue(opened.add),
        simulationProvider.overrideWith(_FakeSimulation.new),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('the sign-up page is told the visit is from the app, and from where', () {
    final uri = newsletterSignupUri('$_url?ref=x', NewsletterEntry.firstRun);

    expect(uri.path, '/newsletter');
    expect(uri.queryParameters, {'ref': 'x', 'source': 'app', 'from': 'firstRun'});
  });

  group('the prompts', () {
    test('opening the page stops both prompts, and survives a restart', () async {
      final c = container();

      await c.read(newsletterPromptsProvider.notifier).open(NewsletterEntry.helpMenu);

      expect(opened, ['$_url?source=app&from=helpMenu']);
      expect(c.read(newsletterPromptsProvider).showWelcomeCard, isFalse);
      expect(c.read(newsletterPromptsProvider).showFirstRunPrompt, isFalse);
      expect(container().read(newsletterPromptsProvider).opened, isTrue);
    });

    test('no thanks on the welcome card leaves the first-run prompt', () async {
      final c = container();

      await c.read(newsletterPromptsProvider.notifier).dismissWelcome();

      expect(c.read(newsletterPromptsProvider).showWelcomeCard, isFalse);
      expect(c.read(newsletterPromptsProvider).showFirstRunPrompt, isTrue);
      expect(container().read(newsletterPromptsProvider).welcomeDismissed, isTrue);
    });

    test('the first-run prompt is claimed once per install', () {
      final controller = container().read(newsletterPromptsProvider.notifier);

      expect(controller.claimFirstRunPrompt(), isTrue);
      expect(controller.claimFirstRunPrompt(), isFalse);
      expect(container().read(newsletterPromptsProvider.notifier).claimFirstRunPrompt(), isFalse);
    });

    test('a build without a newsletter opens nothing and prompts nothing', () async {
      final c = container(url: null);
      final controller = c.read(newsletterPromptsProvider.notifier);

      await controller.open(NewsletterEntry.settings);

      expect(opened, isEmpty);
      expect(controller.claimFirstRunPrompt(), isFalse);
    });
  });

  group('the welcome card', () {
    Future<ProviderContainer> pumpCard(WidgetTester tester, {String? url = _url}) async {
      final c = container(url: url);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: appTestApp(const WelcomeNewsletterCard())),
      );
      return c;
    }

    testWidgets('is absent from a build without a newsletter', (tester) async {
      await pumpCard(tester, url: null);

      expect(find.text(AppStrings.newsletterTitle), findsNothing);
    });

    testWidgets('opens the page from the welcome screen, then goes', (tester) async {
      await pumpCard(tester);
      expect(find.text(AppStrings.newsletterTitle), findsOneWidget);

      await tester.tap(find.text(AppStrings.newsletterSignUp));
      await tester.pumpAndSettle();

      expect(opened, ['$_url?source=app&from=welcome']);
      expect(find.text(AppStrings.newsletterTitle), findsNothing);
    });

    testWidgets('goes for good on no thanks', (tester) async {
      await pumpCard(tester);

      await tester.tap(find.text(AppStrings.newsletterDismiss));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.newsletterTitle), findsNothing);
      expect(opened, isEmpty);
    });
  });

  testWidgets('the first run offers the newsletter once, not on resume or later runs', (
    tester,
  ) async {
    final c = container();
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: appTestApp(const NewsletterFirstRunPrompt())),
    );
    final sim = c.read(simulationProvider.notifier) as _FakeSimulation;
    Finder toast() => find.text(AppStrings.newsletterFirstRunTitle);

    sim.set(SimulationState.running);
    await tester.pumpAndSettle();
    expect(toast(), findsOneWidget);

    await tester.tap(find.text(AppStrings.newsletterSignUp));
    await tester.pumpAndSettle();
    expect(opened, ['$_url?source=app&from=firstRun']);
    expect(toast(), findsNothing);

    sim
      ..set(SimulationState.stopped)
      ..set(SimulationState.running);
    await tester.pumpAndSettle();
    expect(toast(), findsNothing);
  });
}
