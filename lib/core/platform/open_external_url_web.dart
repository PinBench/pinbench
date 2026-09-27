import 'package:web/web.dart' as web;

/// Web implementation: opens [url] in a new tab.
///
/// `_blank` matters for embeds — navigating the host page away from the
/// article the circuit is illustrating would be hostile.
void openExternalUrl(String url) {
  web.window.open(url, '_blank');
}
