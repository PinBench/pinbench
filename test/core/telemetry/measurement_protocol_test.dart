import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pinbench_edition_api/telemetry.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinbench/core/telemetry/analytics_service.dart';
import 'package:pinbench/core/telemetry/measurement_protocol.dart';

const _config = MeasurementProtocolConfig(measurementId: 'G-TEST', apiSecret: 'secret');

/// Every request the backend made, decoded.
class _Requests {
  final uris = <Uri>[];
  final bodies = <Map<String, Object?>>[];

  late final client = MockClient((request) async {
    uris.add(request.url);
    bodies.add(jsonDecode(request.body) as Map<String, Object?>);
    return http.Response('', 204);
  });

  List<Map<String, Object?>> get events => [
    for (final body in bodies) ...(body['events']! as List).cast<Map<String, Object?>>(),
  ];
}

void main() {
  late _Requests requests;
  late DateTime now;

  MeasurementProtocolBackend backend({bool validateOnly = false}) => MeasurementProtocolBackend(
    config: _config,
    clientId: '42.1700000000',
    platform: 'windows',
    language: 'en-US',
    client: requests.client,
    clock: () => now,
    validateOnly: validateOnly,
  );

  setUp(() {
    requests = _Requests();
    now = DateTime.utc(2026, 10, 22, 12);
  });

  group('backend', () {
    test('sends a batch with the client, device and user properties', () async {
      final mp = backend();
      await mp.setUserProperty('app_version', '0.1.2');
      await mp.logEvent('open_template', {'template': 'blink'});
      await mp.flush();

      expect(requests.uris.single.path, '/mp/collect');
      expect(requests.uris.single.queryParameters, {
        'measurement_id': 'G-TEST',
        'api_secret': 'secret',
      });
      final body = requests.bodies.single;
      expect(body['client_id'], '42.1700000000');
      expect(body['user_properties'], {
        'app_version': {'value': '0.1.2'},
      });
      expect(body['device'], {
        'category': 'desktop',
        'operating_system': 'Windows',
        'language': 'en-US',
      });
      expect(requests.events.single['name'], 'open_template');
      expect((requests.events.single['params']! as Map)['template'], 'blink');
    });

    test('debug builds only validate', () async {
      final mp = backend(validateOnly: true);
      await mp.logEvent('x', null);
      await mp.flush();

      expect(requests.uris.single.path, '/debug/mp/collect');
    });

    test('screens go as page_view, which a web stream accepts', () async {
      final mp = backend();
      await mp.logScreenView('canvas');
      await mp.flush();

      final event = requests.events.single;
      expect(event['name'], 'page_view');
      expect((event['params']! as Map)['page_title'], 'canvas');
    });

    test('keeps a session going, and starts a new one after 30 idle minutes', () async {
      final mp = backend();
      await mp.logEvent('a', null);
      now = now.add(const Duration(seconds: 20));
      await mp.logEvent('b', null);
      now = now.add(const Duration(minutes: 31));
      await mp.logEvent('c', null);
      await mp.flush();

      final params = [for (final e in requests.events) e['params']! as Map];
      expect(params[0]['session_id'], params[1]['session_id']);
      expect(params[2]['session_id'], isNot(params[1]['session_id']));
      // Every event claims some engagement, or GA4 does not count the user as
      // active: the first of a session the least, the next the time between.
      expect([for (final p in params) p['engagement_time_msec']], [1, 20000, 1]);
    });

    test('a long gap claims at most a minute of engagement', () async {
      final mp = backend();
      await mp.logEvent('a', null);
      now = now.add(const Duration(minutes: 20));
      await mp.logEvent('b', null);
      await mp.flush();

      expect((requests.events.last['params']! as Map)['engagement_time_msec'], 60000);
    });

    test('sends at most 25 events a request', () async {
      final mp = backend();
      for (var i = 0; i < 30; i++) {
        await mp.logEvent('e$i', null);
      }
      await mp.flush();

      expect([for (final body in requests.bodies) (body['events']! as List).length], [25, 5]);
    });

    test('sends on its own after the flush delay', () async {
      final mp = MeasurementProtocolBackend(
        config: _config,
        clientId: 'c',
        platform: 'linux',
        language: 'de-DE',
        client: requests.client,
        flushDelay: Duration.zero,
        validateOnly: false,
      );
      await mp.logEvent('e', null);
      await pumpEventQueue();

      expect(requests.events, hasLength(1));
      expect((requests.bodies.single['device']! as Map)['operating_system'], 'Linux');
    });

    test('withdrawing consent drops what has not been sent', () async {
      final mp = backend();
      await mp.logEvent('e', null);
      await mp.setConsent(granted: false);
      await mp.flush();

      expect(requests.bodies, isEmpty);
    });

    test('a failed request is dropped, not thrown', () async {
      final mp = MeasurementProtocolBackend(
        config: _config,
        clientId: 'c',
        platform: 'windows',
        language: 'en',
        client: MockClient((_) => throw http.ClientException('offline')),
        validateOnly: false,
      );
      await mp.logEvent('e', null);
      await expectLater(mp.flush(), completes);
      expect(mp.pending, isEmpty);
    });
  });

  group('control', () {
    late SharedPreferences prefs;
    late List<String> clientIds;
    late List<AnalyticsService> turnedOn;
    late MeasurementProtocolBackend? created;

    MeasurementProtocolControl control() => MeasurementProtocolControl(
      'https://example.com/privacy',
      prefs: prefs,
      onAnalyticsOn: turnedOn.add,
      createBackend: (clientId) {
        clientIds.add(clientId);
        return created = backend();
      },
    );

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      clientIds = [];
      turnedOn = [];
      created = null;
    });

    test('creates nothing — not even a client id — until the user agrees', () {
      final mp = control()..applyConsent(granted: false);

      expect(mp.analytics.enabled, isFalse);
      expect(clientIds, isEmpty);
      expect(prefs.getString('analytics.client_id'), isNull);
    });

    test('a first agreement makes a client id and reports the first launch', () {
      final mp = control()..applyConsent(granted: true);

      expect(mp.analytics.enabled, isTrue);
      expect(turnedOn, [mp.analytics]);
      expect(prefs.getString('analytics.client_id'), clientIds.single);
      expect(
        [for (final e in created!.pending) e['name']],
        [MeasurementProtocolBackend.firstLaunchEvent],
      );
    });

    test('a later run keeps the client id and is no first launch', () {
      control().applyConsent(granted: true);
      final first = clientIds.single;

      control().applyConsent(granted: true);

      expect(clientIds, [first, first]);
      expect(created!.pending, isEmpty);
    });

    test('withdrawing switches it off', () {
      final mp = control()
        ..applyConsent(granted: true)
        ..applyConsent(granted: false);

      expect(mp.analytics.enabled, isFalse);
      expect(created!.pending, isEmpty);
    });
  });
}
