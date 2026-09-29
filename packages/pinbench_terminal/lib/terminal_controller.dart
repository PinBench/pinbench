import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart' show Terminal;

import 'pty/pty_service.dart';
import 'terminal_state.dart';

/// How this platform spawns a shell, if it can.
///
/// Both providers here are written by hand rather than generated with
/// `@Riverpod(keepAlive: true)`, so this package needs no `build_runner` step
/// — CI's per-package loop runs pub get, analyze and test and nothing else.
/// Plain providers are keep-alive already, which is what these want: the
/// controller holds a live process and a stream subscription for the lifetime
/// of the app.
final ptyServiceProvider = Provider<PtyService>((ref) => PtyService());

/// Owns the lifecycle of the embedded shell terminal.
///
/// Builds an xterm [Terminal], starts a backing PTY process immediately, and
/// wires process IO through [PtyService]. Kept alive because it holds a
/// long-lived process and stream subscription for the duration of the app.
final terminalControllerProvider = NotifierProvider<TerminalController, TerminalState>(
  TerminalController.new,
);

class TerminalController extends Notifier<TerminalState> {
  PtyService get _pty => ref.read(ptyServiceProvider);
  StreamSubscription<String>? _outputSubscription;

  @override
  TerminalState build() {
    ref.onDispose(() => _outputSubscription?.cancel());

    final terminal = Terminal(maxLines: 10000);

    // Start the shell process immediately.
    unawaited(Future.microtask(startTerminal));

    return TerminalState(terminal: terminal);
  }

  void startTerminal() {
    try {
      final pty = _pty.start();

      // No process handle means the platform can't spawn a shell (web build).
      if (pty == null) {
        state.terminal.write(
          '\r\n\x1b[33mThe embedded terminal is not available in the web '
          'preview.\x1b[0m\r\n',
        );
        return;
      }

      // Cancel any previous subscription before creating a new one.
      unawaited(_outputSubscription?.cancel());

      // Feed process output into the terminal.
      _outputSubscription = _pty
          .output(pty)
          .listen(
            state.terminal.write,
            onDone: () {
              debugPrint('Terminal process ended.');
            },
            onError: (Object err) {
              debugPrint('Terminal process error: $err');
            },
          );

      // Feed user input from the terminal UI into the process.
      state.terminal.onOutput = (data) {
        _pty.write(pty, data);
      };

      // Forward resize events from the terminal view to the process.
      state.terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        _pty.resize(pty, height, width);
      };

      state = TerminalState(terminal: state.terminal, pty: pty);
    } catch (e, st) {
      debugPrint('Failed to start terminal: $e\n$st');
      state.terminal.write('\r\n\x1b[31mFailed to start terminal: $e\x1b[0m\r\n');
    }
  }

  void killTerminal() {
    final pty = state.pty;
    if (pty != null) {
      _pty.kill(pty);
    }
    state.terminal.eraseDisplay();
    state.terminal.setCursor(0, 0);
    state = TerminalState(terminal: state.terminal);
  }

  void restartTerminal() {
    killTerminal();
    startTerminal();
  }
}
