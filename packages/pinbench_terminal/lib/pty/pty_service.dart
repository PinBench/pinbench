import 'pty_service_web.dart' if (dart.library.io) 'pty_service_io.dart';

/// Thin boundary over a pseudo-terminal (PTY) process.
///
/// The concrete implementation is chosen at compile time: a real
/// `flutter_pty`-backed service on native platforms (via `dart.library.io`),
/// and a no-op stub on the web, where spawning OS processes is impossible.
/// Keeping the contract free of `dart:io` and `flutter_pty` types lets the
/// terminal feature compile for the web build (Firebase Hosting preview).
///
/// Handles are exposed as opaque [Object]s so callers never depend on the
/// native `Pty` type. [start] returns `null` when the platform cannot spawn a
/// process.
abstract interface class PtyService {
  /// Creates the platform-appropriate implementation.
  factory() = PtyServiceImpl;

  /// Starts a shell process. Uses [shell] when provided, otherwise resolves a
  /// platform default. Returns an opaque handle, or `null` when the platform
  /// cannot spawn a process (web).
  Object? start([String? shell]);

  /// UTF-8 decoded output stream for [pty].
  Stream<String> output(Object pty);

  /// Writes UTF-8 encoded [data] to [pty].
  void write(Object pty, String data);

  /// Resizes [pty] to the given [rows] and [cols].
  void resize(Object pty, int rows, int cols);

  /// Kills the [pty] process.
  void kill(Object pty);
}
