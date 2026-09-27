import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

/// Native/VM implementation: hands [url] to the system browser.
///
/// This was a deliberate no-op while the only caller was the embed view,
/// which exists solely to be rendered inside an `<iframe>`. Desktop has real
/// callers now — the Linux update path and the "get the signed build" link
/// both need to leave the app — so the launcher package earns its place.
///
/// `externalApplication` rather than the default: every URL that reaches here
/// is a page meant to be read, bookmarked and paid on in a real browser, not
/// an in-app web view with no address bar.
///
/// Fire-and-forget to match the web signature. A launch that fails leaves the
/// user on a screen that still says what the link was — there is nothing
/// useful to do with the `false` that `launchUrl` would return.
void openExternalUrl(String url) {
  unawaited(launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication));
}
