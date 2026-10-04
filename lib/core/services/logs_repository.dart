import 'package:flutter/foundation.dart';

enum LogChannel() {
  debug,
  serial,
  spice,
}

class LogsRepository {
  final Map<LogChannel, List<String>> _logs = {
    LogChannel.debug: [],
    LogChannel.serial: [],
    LogChannel.spice: [],
  };

  final Map<LogChannel, Set<VoidCallback>> _listeners = {};

  void addLog(LogChannel channel, String log) {
    final list = _logs[channel]!;
    list.add(log);
    if (list.length > 1000) {
      list.removeRange(0, list.length - 1000);
    }
    _notify(channel);
  }

  void clear(LogChannel channel) {
    _logs[channel]?.clear();
    _notify(channel);
  }

  /// Empties every channel, for when the workspace whose output they hold is
  /// replaced by another.
  void clearAll() => LogChannel.values.forEach(clear);

  List<String> getLogs(LogChannel channel) => List.of(_logs[channel] ?? []);

  void listen(LogChannel channel, VoidCallback onChanged) {
    _listeners.putIfAbsent(channel, () => {}).add(onChanged);
  }

  void unlisten(LogChannel channel, VoidCallback onChanged) {
    _listeners[channel]?.remove(onChanged);
  }

  final Map<LogChannel, int> _lastNotify = {};
  final Map<LogChannel, bool> _notifyPending = {};

  void _notify(LogChannel channel) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastNotify[channel] ?? 0;

    if (now - last < 100) {
      if (!(_notifyPending[channel] ?? false)) {
        _notifyPending[channel] = true;
        Future.delayed(const Duration(milliseconds: 100), () {
          _notifyPending[channel] = false;
          _notify(channel);
        });
      }
      return;
    }

    _lastNotify[channel] = now;

    final callbacks = _listeners[channel];
    if (callbacks != null) {
      for (final callback in List<VoidCallback>.from(callbacks)) {
        callback();
      }
    }
  }
}
