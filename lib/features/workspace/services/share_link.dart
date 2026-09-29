import 'package:flutter/foundation.dart' show kIsWeb;

/// Base URL share links are built against.
///
/// On the web the app knows its own origin, so links point at wherever it is
/// actually served — a preview channel link stays on the preview channel. On
/// desktop there is no origin to read, so links have to name the public site;
/// a link is only useful to someone else anyway, and they will open it in a
/// browser.
// Build-time config, not a secret — it is the public address of the site.
// ignore: do_not_use_environment
const _fallbackOrigin = String.fromEnvironment(
  'SHARE_LINK_ORIGIN',
  defaultValue: 'https://pinbench.web.app',
);

/// The URL that opens project [projectId].
///
/// Matches the `/p/:projectId` route, so a shared link lands directly on the
/// circuit rather than on a landing page the visitor has to navigate from.
String shareLinkFor(String projectId, {String? origin}) {
  final base = origin ?? (kIsWeb ? Uri.base.origin : _fallbackOrigin);
  return '${base.replaceAll(RegExp(r'/+$'), '')}/p/$projectId';
}

/// Whether [value] is plausibly an email address.
///
/// Deliberately loose. The authoritative check happens when the invitee signs
/// in with a verified address, so being strict here only risks rejecting valid
/// but unusual addresses — plenty of which exist, and RFC 5322 is not
/// something to reimplement in a text field validator. This catches the
/// genuine mistakes: empty, no `@`, no domain dot, stray whitespace.
bool isProbablyEmail(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) return false;
  final at = trimmed.indexOf('@');
  if (at <= 0 || at != trimmed.lastIndexOf('@')) return false;
  final domain = trimmed.substring(at + 1);
  return domain.contains('.') && !domain.startsWith('.') && !domain.endsWith('.');
}

/// An `<iframe>` snippet a blog or course page can paste in.
///
/// `?embed=1` selects the chrome-less render. The height is a default that
/// suits a circuit rather than a rule — whoever pastes this owns their layout
/// and will change it.
///
/// `loading="lazy"` because an embed is usually well below the fold in an
/// article, and `allow="autoplay"` so the simulation can drive the buzzer
/// without the browser muting it.
///
/// [live] adds `&live=1`, which subscribes the embed to the project's files so
/// a reader with the page already open sees the author's corrections. Without
/// it the embed is a snapshot that refreshes only on reload — which is the
/// right default: most embeds illustrate a finished article, and a circuit
/// changing under a reader mid-paragraph is worse than a stale one.
String embedSnippetFor(String projectId, {String? origin, int height = 420, bool live = false}) {
  final src = '${shareLinkFor(projectId, origin: origin)}?embed=1${live ? '&live=1' : ''}';
  return '<iframe src="$src" width="100%" height="$height" '
      'style="border:1px solid #ddd;border-radius:8px" '
      'loading="lazy" allow="autoplay" title="Arduino circuit"></iframe>';
}

/// The two flags a `/p/:projectId` URL can carry, read back off the query.
///
/// The reading half of the contract [embedSnippetFor] writes. It lives here,
/// next to the writer, so the two cannot drift — and so the round trip is
/// testable without booting a router, which is what let `live=1` ship parsed
/// but unused: the URL said one thing and the code below it did another, with
/// no single place where that mismatch was visible.
class const ShareLinkOptions({
  /// `?embed=1` — render the chrome-less view meant for an `<iframe>`.
  final bool embed = false,

  /// `?live=1` — subscribe to the author's edits instead of taking a snapshot.
  final bool live = false,
}) {
  /// Reads the flags out of [query], the way `GoRouterState.uri.queryParameters`
  /// supplies them. Anything other than an exact `1` is off: a flag that widens
  /// what a link does should have to be spelled correctly.
  factory fromQuery(Map<String, String> query) =>
      ShareLinkOptions(embed: query['embed'] == '1', live: query['live'] == '1');
}
