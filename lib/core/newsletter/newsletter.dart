import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/open_external_url.dart';
import '../telemetry/telemetry_providers.dart';
import '../utils/shared_preferences_provider.dart';

/// The edition's newsletter sign-up page, or null when the build has none —
/// always the case in a build from source. Overridden in `app/bootstrap.dart`.
final newsletterUrlProvider = Provider<String?>((ref) => null);

/// How the sign-up page is opened: in the browser. Replaced in tests, which
/// have no browser to open it in.
final newsletterLauncherProvider = Provider<void Function(String url)>((ref) => openExternalUrl);

/// Where in the app a newsletter link was followed from. Sent with the
/// `newsletter_open` event and passed to the sign-up page, so the list can say
/// which prompts people actually answer.
enum NewsletterEntry { welcome, firstRun, helpMenu, settings }

/// The sign-up page for [base], told the visit comes from the app and from
/// which part of it.
Uri newsletterSignupUri(String base, NewsletterEntry from) {
  final uri = Uri.parse(base);
  return uri.replace(queryParameters: {...uri.queryParameters, 'source': 'app', 'from': from.name});
}

/// What the user has already done about the newsletter, so the prompts that
/// would otherwise repeat stay away once they have been answered.
///
/// A sign-up happens in the browser, where the app cannot see it. Opening the
/// page is the nearest thing it can know, so that counts as answered: nobody
/// who went to sign up wants to be asked again.
class const NewsletterPrompts({
  /// The user opened the sign-up page, from anywhere in the app.
  final bool opened = false,

  /// The user said no to the welcome-screen card.
  final bool welcomeDismissed = false,

  /// The prompt after a first successful run has been shown — it shows once,
  /// whatever the user did with it.
  final bool firstRunShown = false,
}) {
  bool get showWelcomeCard => !opened && !welcomeDismissed;
  bool get showFirstRunPrompt => !opened && !firstRunShown;
}

final newsletterPromptsProvider = NotifierProvider<NewsletterController, NewsletterPrompts>(
  NewsletterController.new,
);

class NewsletterController extends Notifier<NewsletterPrompts> {
  static const _openedKey = 'newsletter.opened';
  static const _welcomeDismissedKey = 'newsletter.welcome_dismissed';
  static const _firstRunShownKey = 'newsletter.first_run_shown';

  @override
  NewsletterPrompts build() {
    final prefs = ref.read(sharedPreferencesProvider);
    return NewsletterPrompts(
      opened: prefs.getBool(_openedKey) ?? false,
      welcomeDismissed: prefs.getBool(_welcomeDismissedKey) ?? false,
      firstRunShown: prefs.getBool(_firstRunShownKey) ?? false,
    );
  }

  /// Opens the sign-up page in the browser. Does nothing in a build without
  /// one.
  Future<void> open(NewsletterEntry from) async {
    final base = ref.read(newsletterUrlProvider);
    if (base == null) return;
    ref.read(analyticsProvider).logEvent('newsletter_open', {'from': from.name});
    ref.read(newsletterLauncherProvider)(newsletterSignupUri(base, from).toString());
    state = NewsletterPrompts(
      opened: true,
      welcomeDismissed: state.welcomeDismissed,
      firstRunShown: state.firstRunShown,
    );
    await ref.read(sharedPreferencesProvider).setBool(_openedKey, true);
  }

  /// The welcome card's "No thanks": it does not come back. Help and Settings
  /// still lead to the page.
  Future<void> dismissWelcome() async {
    state = NewsletterPrompts(
      opened: state.opened,
      welcomeDismissed: true,
      firstRunShown: state.firstRunShown,
    );
    await ref.read(sharedPreferencesProvider).setBool(_welcomeDismissedKey, true);
  }

  /// Records that the after-first-run prompt was shown, and says whether it
  /// should be — true exactly once per install, and never once the page has
  /// been opened, or in a build without one.
  bool claimFirstRunPrompt() {
    if (ref.read(newsletterUrlProvider) == null || !state.showFirstRunPrompt) return false;
    state = NewsletterPrompts(
      opened: state.opened,
      welcomeDismissed: state.welcomeDismissed,
      firstRunShown: true,
    );
    unawaited(ref.read(sharedPreferencesProvider).setBool(_firstRunShownKey, true));
    return true;
  }
}
