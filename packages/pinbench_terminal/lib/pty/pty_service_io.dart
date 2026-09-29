import 'dart:convert';
import 'dart:io';

import 'package:flutter_pty/flutter_pty.dart';

import 'pty_service.dart';

/// Native [PtyService] backed by `flutter_pty` and `dart:io`.
///
/// Encapsulates shell selection, process start, the UTF-8 decoded output
/// stream, and write/resize/kill operations. The opaque [Object] handles in the
/// [PtyService] contract are real [Pty] instances here.
class PtyServiceImpl implements PtyService {
  /// Resolves the user's shell, falling back to a platform default.
  String resolveShell() =>
      Platform.environment['SHELL'] ?? (Platform.isWindows ? 'cmd.exe' : 'bash');

  @override
  Pty start([String? shell]) => Pty.start(shell ?? resolveShell());

  /// Malformed bytes are allowed so a stray non-UTF-8 sequence never tears down
  /// the stream.
  @override
  Stream<String> output(covariant Pty pty) =>
      pty.output.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true));

  @override
  void write(covariant Pty pty, String data) => pty.write(const Utf8Encoder().convert(data));

  @override
  void resize(covariant Pty pty, int rows, int cols) => pty.resize(rows, cols);

  @override
  void kill(covariant Pty pty) => pty.kill();
}
