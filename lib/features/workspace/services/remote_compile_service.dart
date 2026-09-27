import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../data/workspace_fs.dart';
import 'compiler_service.dart' show CompilerException;

/// Web only: POSTs a sketch's source files to a remote `arduino-cli` compile
/// service (the browser cannot run `arduino-cli` locally) and returns the
/// Intel-HEX it produces. Throws [CompilerException] carrying the compiler
/// output on failure (shown in the Problems pane / serial monitor).
abstract final class RemoteCompileService {
  static const _sourceExtensions = {'.ino', '.h', '.hpp', '.c', '.cpp', '.s'};

  /// Shared bearer token for the compile service, set at build time with
  /// `--dart-define=COMPILE_API_TOKEN=…`. Optional: when empty, no
  /// `Authorization` header is sent, which is what a self-hosted service
  /// running without `COMPILE_API_TOKEN` expects.
  ///
  /// This is **not** a secret in a web build — it ships inside the JavaScript
  /// bundle and anyone can read it out of devtools. It exists to stop casual
  /// scripted abuse of the endpoint; the service's rate limiting and
  /// concurrency caps are what actually bound the damage.
  // ignore: do_not_use_environment
  static const _apiToken = String.fromEnvironment('COMPILE_API_TOKEN');

  static Future<String> compile(String directoryPath, String compileApiUrl) async {
    final fs = WorkspaceFs();
    final sketch = p.basename(directoryPath);
    final files = <String, String>{};
    for (final path in fs.listFiles(directoryPath)) {
      if (_sourceExtensions.contains(p.extension(path).toLowerCase())) {
        files[p.basename(path)] = fs.readStringSync(path);
      }
    }
    if (files.isEmpty) {
      throw CompilerException('No Arduino source files (.ino) found to compile.');
    }

    final base = compileApiUrl.endsWith('/')
        ? compileApiUrl.substring(0, compileApiUrl.length - 1)
        : compileApiUrl;

    final http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse('$base/compile'),
            headers: {
              'Content-Type': 'application/json',
              if (_apiToken.isNotEmpty) 'Authorization': 'Bearer $_apiToken',
            },
            body: jsonEncode({'sketch': sketch, 'fqbn': 'arduino:avr:uno', 'files': files}),
          )
          .timeout(const Duration(seconds: 120));
    } catch (e) {
      throw CompilerException('Could not reach the compile service at $base.\n$e');
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw CompilerException(
        'Compile service returned an unexpected response (HTTP ${resp.statusCode}).',
      );
    }

    if (resp.statusCode == 200 && body['hex'] is String) {
      return body['hex'] as String;
    }

    throw CompilerException(friendlyError(resp.statusCode, body));
  }

  /// Turn a compile-service error response into something worth showing a
  /// user. Compiler diagnostics (`stderr`) are the whole point of a failed
  /// build, so those pass through verbatim; the service's own operational
  /// rejections get a plain-language explanation instead of a raw error code.
  @visibleForTesting
  static String friendlyError(int statusCode, Map<String, dynamic> body) {
    final error = body['error']?.toString() ?? '';

    switch (statusCode) {
      case 401:
        return 'The compile service rejected this build (unauthorized). If you '
            'are self-hosting, check that COMPILE_API_TOKEN matches on both the '
            'app and the service.';
      case 413:
        return 'This sketch is too large for the compile service to accept. Try '
            'removing unused files, or compile it in the desktop app.';
      case 429:
        final retryAfterSec = body['retryAfterSec'];
        final wait = retryAfterSec is num
            ? ' Try again in about ${_humanDuration(retryAfterSec.round())}.'
            : ' Try again shortly.';
        return "You've hit the compile limit for now.$wait You can compile "
            'without limits in the desktop app.';
      case 503:
        return 'The compile service is busy right now. Try again in a few '
            'seconds.';
      case 504:
        return 'Compiling took too long and was stopped by the service. This '
            'usually means the sketch is very large or stuck in a loop the '
            'compiler cannot resolve.';
    }

    // Compiler output is the useful thing for a genuine build failure.
    final stderr = body['stderr']?.toString();
    if (stderr != null && stderr.trim().isNotEmpty) return stderr;

    final detail = body['detail']?.toString();
    if (detail != null && detail.trim().isNotEmpty) {
      return error.isEmpty ? detail : '$error: $detail';
    }
    return error.isEmpty ? 'Unknown compile error (HTTP $statusCode).' : error;
  }

  static String _humanDuration(int seconds) {
    if (seconds < 60) return '$seconds seconds';
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) return '$minutes minute${minutes == 1 ? '' : 's'}';
    final hours = (minutes / 60).ceil();
    return '$hours hour${hours == 1 ? '' : 's'}';
  }
}
