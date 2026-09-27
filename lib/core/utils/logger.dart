import 'package:flutter/foundation.dart';

import 'package:stack_trace/stack_trace.dart';
import 'package:talker_flutter/talker_flutter.dart';

final talker = TalkerFlutter.init(settings: TalkerSettings());

/// Initializes the global logger configuration.
void initAppLogger() {
  FlutterError.onError = (details) {
    talker.handle(details.exception, _foldStackTrace(details.stack), details.context?.toString());
  };
}

/// Folds a stack trace down to this app's own frames. Exposed so the
/// simulation's log adapter (installed in `app/bootstrap.dart`, which is
/// allowed to know about a feature — `core/` is not) can format the same way.
StackTrace? foldStackTrace(StackTrace? stackTrace) => _foldStackTrace(stackTrace);

const _appPackage = 'pinbench';

StackTrace? _foldStackTrace(StackTrace? stackTrace) {
  if (stackTrace == null) return null;
  final trace = Trace.from(stackTrace);
  // Nothing of ours on it: fold it and one line is all that is left — the
  // frame `dart:ui _drawFrame` says the error happened in a frame, which is
  // where every error happens. A trace that answers nothing is worse than a
  // long one, so an error raised entirely inside the framework or a package
  // keeps its own frames, which are the only ones that can name it.
  if (!trace.frames.any((frame) => frame.package == _appPackage)) {
    return StackTrace.fromString(trace.terse.toString());
  }
  final folded = trace.foldFrames((frame) => frame.package != _appPackage, terse: true);
  return StackTrace.fromString(folded.toString());
}

/// A wrapper class to adapt the existing `Logger.get('category')` pattern to Talker.
class AppLogger {
  final String category;

  const AppLogger(this.category);

  void trace(String message) {
    talker.verbose('[$category] $message');
  }

  void debug(String message) {
    talker.debug('[$category] $message');
  }

  void info(String message) {
    talker.info('[$category] $message');
  }

  void warning(String message) {
    talker.warning('[$category] $message');
  }

  void error(String message, {Object? error, StackTrace? stackTrace}) {
    talker.error('[$category] $message', error, _foldStackTrace(stackTrace));
  }
}
