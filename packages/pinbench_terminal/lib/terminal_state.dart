import 'package:xterm/xterm.dart';

/// Immutable snapshot of the embedded terminal session.
///
/// Holds the xterm [Terminal] buffer together with the backing PTY process
/// handle. [pty] is `null` when no shell process is currently running (e.g.
/// before startup, after the terminal has been killed, or on the web where
/// process spawning is unsupported).
///
/// This is application/UI session state, not a pure domain model: it wraps a
/// Flutter-coupled [Terminal] and a live, opaque PTY handle, so it lives next
/// to [TerminalController] rather than in `domain/`. The handle is typed as
/// [Object] to keep this file free of the native `flutter_pty` dependency,
/// which cannot compile for the web.
class TerminalState {
  final Terminal terminal;
  final Object? pty;

  const TerminalState({required this.terminal, this.pty});
}
