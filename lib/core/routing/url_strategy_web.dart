import 'package:flutter_web_plugins/url_strategy.dart';

/// Switches the web app to clean, path-based URLs (no leading `#`), so routes
/// like `/t/blink` work as real browser locations.
void configurePathUrlStrategy() => usePathUrlStrategy();
