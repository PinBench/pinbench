import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode;

import 'package:http/http.dart' as http;
import 'package:pinbench_edition_api/telemetry.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';
import 'analytics_backend.dart';
import 'analytics_service.dart';
import 'telemetry_consent.dart';

/// Analytics on Windows and Linux, which the Firebase SDK does not support:
/// events go to a Google Analytics 4 web data stream over the Measurement
/// Protocol, a plain HTTPS endpoint, so these installs are counted as users
/// in the same property as every other platform.
///
/// What the SDK does on its own is done here by hand:
///
/// * **The user** is a random client id kept in [SharedPreferences] — the
///   install, not the person. A new one also sends [firstLaunchEvent], since
///   the protocol may not send `first_visit` itself.
/// * **Sessions**: a `session_id` that renews after 30 minutes without an
///   event, and `engagement_time_msec` on every event. Without both, GA4 does
///   not count the user as active.
/// * **Batching**: events wait up to [flushDelay], or until there are 25 (the
///   protocol's limit per request), and [flush] sends the rest before exit.
///
/// Screens are sent as `page_view`: a web stream refuses `screen_view`.
///
/// Debug builds post to the validation endpoint, which checks each request and
/// records nothing, and log what it objects to.
class MeasurementProtocolBackend implements AnalyticsBackend {
  new({
    required this._config,
    required this._clientId,
    required this._platform,
    required this._language,
    http.Client? client,
    DateTime Function()? clock,
    this.flushDelay = const Duration(seconds: 10),
    this._validateOnly = kDebugMode,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  /// Logged the first time an install sends anything.
  static const firstLaunchEvent = 'first_launch';

  /// The protocol's limit on events in one request.
  static const _batchSize = 25;

  static const _sessionTimeout = Duration(minutes: 30);

  /// The most engagement one event can claim. The time since the previous
  /// event includes time spent away from the app, so a long gap would
  /// otherwise count as a long stretch of use.
  static const _maxEngagement = Duration(minutes: 1);

  final MeasurementProtocolConfig _config;
  final String _clientId;
  final String _platform;
  final String _language;
  final http.Client _client;
  final DateTime Function() _clock;
  final bool _validateOnly;

  /// How long an event may wait to be batched with others.
  final Duration flushDelay;

  final _userProperties = <String, String>{};
  final _pending = <Map<String, Object>>[];
  Timer? _timer;
  int? _sessionId;
  DateTime? _lastEventAt;

  /// The events waiting to be sent. Visible for tests.
  List<Map<String, Object>> get pending => List.unmodifiable(_pending);

  @override
  Future<void> logEvent(String name, Map<String, Object>? params) async =>
      _enqueue(name, params ?? const {});

  @override
  Future<void> logScreenView(String screenName) async => _enqueue('page_view', {
    'page_title': screenName,
    'page_location': 'app://pinbench/$screenName',
  });

  @override
  Future<void> setUserProperty(String name, String value) async => _userProperties[name] = value;

  /// Withdrawing consent drops what has not been sent yet: it was collected
  /// with consent, but the user has just said not to send it.
  @override
  Future<void> setConsent({required bool granted}) async {
    if (granted) return;
    _timer?.cancel();
    _pending.clear();
  }

  @override
  Future<void> flush() async {
    _timer?.cancel();
    while (_pending.isNotEmpty) {
      final batch = _pending.take(_batchSize).toList();
      _pending.removeRange(0, batch.length);
      await _send(batch);
    }
  }

  void _enqueue(String name, Map<String, Object> params) {
    final now = _clock();
    final last = _lastEventAt;
    final sessionId = last == null || now.difference(last) > _sessionTimeout || _sessionId == null
        ? now.millisecondsSinceEpoch ~/ 1000
        : _sessionId!;
    final engaged = sessionId == _sessionId && last != null ? now.difference(last) : Duration.zero;
    _sessionId = sessionId;
    _lastEventAt = now;

    _pending.add({
      'name': name,
      'params': {
        ...params,
        'session_id': sessionId,
        // Must be above zero for the user to count as active.
        'engagement_time_msec': max(1, min(engaged.inMilliseconds, _maxEngagement.inMilliseconds)),
      },
    });
    if (_pending.length >= _batchSize) {
      unawaited(flush());
    } else {
      _timer ??= Timer(flushDelay, () {
        _timer = null;
        unawaited(flush());
      });
    }
  }

  Future<void> _send(List<Map<String, Object>> events) async {
    final uri = Uri.https(
      'www.google-analytics.com',
      _validateOnly ? '/debug/mp/collect' : '/mp/collect',
      {'measurement_id': _config.measurementId, 'api_secret': _config.apiSecret},
    );
    final body = jsonEncode({
      'client_id': _clientId,
      if (_userProperties.isNotEmpty)
        'user_properties': {
          for (final MapEntry(:key, :value) in _userProperties.entries) key: {'value': value},
        },
      // Only ever sent with the user's consent to analytics; there are no ads.
      'consent': {'ad_user_data': 'DENIED', 'ad_personalization': 'DENIED'},
      'device': {
        'category': 'desktop',
        'operating_system': _operatingSystem,
        'language': _language,
      },
      'events': events,
    });
    try {
      final response = await _client.post(
        uri,
        headers: {'content-type': 'application/json'},
        body: body,
      );
      if (_validateOnly) {
        talker.debug('Measurement Protocol validation: ${response.body}');
      } else if (response.statusCode >= 300) {
        talker.warning('Measurement Protocol answered ${response.statusCode}');
      }
    } catch (e) {
      // Offline, or the request failed: the batch is dropped rather than
      // kept, so an install that is never online does not grow a backlog.
      talker.warning('Measurement Protocol send failed: $e');
    }
  }

  /// GA4's spelling of the operating system, from the app's platform label.
  String get _operatingSystem => switch (_platform) {
    'windows' => 'Windows',
    'linux' => 'Linux',
    'macOS' => 'Macintosh',
    final other => other,
  };
}

/// The consent switch for [MeasurementProtocolBackend]: no backend — and no
/// client id — exists until the user agrees, and withdrawing drops it again.
class MeasurementProtocolControl implements TelemetryControl {
  new(
    this.privacyPolicyUrl, {
    required this._createBackend,
    required this._prefs,
    required this._onAnalyticsOn,
  });

  static const _clientIdKey = 'analytics.client_id';

  @override
  final String privacyPolicyUrl;

  final MeasurementProtocolBackend Function(String clientId) _createBackend;
  final SharedPreferences _prefs;
  final void Function(AnalyticsService analytics) _onAnalyticsOn;

  final _slot = AnalyticsSlot();
  late final analytics = AnalyticsService.switchable(_slot);

  @override
  bool get available => true;

  @override
  void applyConsent({required bool granted}) {
    if (granted) {
      if (_slot.instance != null) return;
      final stored = _prefs.getString(_clientIdKey);
      final clientId = stored ?? _newClientId();
      if (stored == null) unawaited(_prefs.setString(_clientIdKey, clientId));
      _slot.instance = _createBackend(clientId);
      analytics.setConsent(granted: true);
      _onAnalyticsOn(analytics);
      if (stored == null) analytics.logEvent(MeasurementProtocolBackend.firstLaunchEvent);
    } else if (_slot.instance != null) {
      analytics.setConsent(granted: false);
      _slot.instance = null;
    }
  }

  /// Random, in the shape of the id gtag.js keeps in its cookie.
  static String _newClientId() {
    final random = Random.secure();
    final seconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return '${random.nextInt(1 << 31)}.$seconds';
  }
}
