import 'package:pinbench/features/workspace/services/remote_compile_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The compile service can reject a build for reasons that have nothing to do
/// with the user's code (rate limit, busy queue, bad token). Those must not
/// surface as raw error codes in the Problems pane — a user who sees
/// `rate_limited` has no idea what to do next.
void main() {
  group('RemoteCompileService.friendlyError', () {
    test('passes compiler diagnostics through verbatim', () {
      const stderr = "blink.ino:3:1: error: expected ';' before '}' token";
      expect(
        RemoteCompileService.friendlyError(400, {'error': 'compile_failed', 'stderr': stderr}),
        stderr,
      );
    });

    test('explains a rate limit and quotes the wait in human units', () {
      final message = RemoteCompileService.friendlyError(429, {
        'error': 'rate_limited',
        'retryAfterSec': 1800,
      });
      expect(message, contains('compile limit'));
      expect(message, contains('30 minutes'));
      expect(message, contains('desktop app'));
      expect(message, isNot(contains('rate_limited')));
    });

    test('falls back to a vague wait when the service omits retryAfterSec', () {
      final message = RemoteCompileService.friendlyError(429, {'error': 'rate_limited'});
      expect(message, contains('Try again shortly'));
    });

    test('formats retry waits across the seconds/minutes/hours boundaries', () {
      String waitFor(int seconds) =>
          RemoteCompileService.friendlyError(429, {'retryAfterSec': seconds});

      expect(waitFor(45), contains('45 seconds'));
      expect(waitFor(60), contains('1 minute'));
      expect(waitFor(90), contains('2 minutes'));
      expect(waitFor(3600), contains('1 hour'));
      expect(waitFor(7200), contains('2 hours'));
    });

    test('explains a busy queue as transient', () {
      final message = RemoteCompileService.friendlyError(503, {'error': 'busy'});
      expect(message, contains('busy'));
      expect(message, contains('few'));
      expect(message, isNot(contains('503')));
    });

    test('explains an auth failure with the self-hosting hint', () {
      final message = RemoteCompileService.friendlyError(401, {'error': 'unauthorized'});
      expect(message, contains('COMPILE_API_TOKEN'));
    });

    test('explains an oversized payload', () {
      final message = RemoteCompileService.friendlyError(413, {'error': 'payload_too_large'});
      expect(message, contains('too large'));
    });

    test('explains a compile timeout without blaming the network', () {
      final message = RemoteCompileService.friendlyError(504, {'error': 'compile_timeout'});
      expect(message, contains('too long'));
    });

    test('combines error and detail for unmapped validation failures', () {
      expect(
        RemoteCompileService.friendlyError(400, {
          'error': 'unsupported_fqbn',
          'detail': 'fqbn must be one of: arduino:avr:uno',
        }),
        'unsupported_fqbn: fqbn must be one of: arduino:avr:uno',
      );
    });

    test('prefers stderr over detail when both are present', () {
      expect(
        RemoteCompileService.friendlyError(400, {
          'error': 'compile_failed',
          'stderr': 'real compiler output',
          'detail': 'less useful',
        }),
        'real compiler output',
      );
    });

    test('never returns an empty message, even for an empty body', () {
      final message = RemoteCompileService.friendlyError(500, const {});
      expect(message.trim(), isNotEmpty);
      expect(message, contains('500'));
    });

    test('ignores blank stderr rather than showing whitespace', () {
      expect(
        RemoteCompileService.friendlyError(500, {'error': 'hex_not_generated', 'stderr': '   \n '}),
        'hex_not_generated',
      );
    });
  });
}
