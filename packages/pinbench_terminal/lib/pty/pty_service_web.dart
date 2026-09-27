import 'pty_service.dart';

/// Web stub for [PtyService].
///
/// The web build has no OS shell to attach to, so [start] returns `null` and
/// every other operation is a safe no-op. The terminal UI surfaces a message
/// explaining that the embedded shell is unavailable in the browser preview.
class PtyServiceImpl implements PtyService {
  @override
  Object? start([String? shell]) => null;

  @override
  Stream<String> output(Object pty) => const Stream.empty();

  @override
  void write(Object pty, String data) {}

  @override
  void resize(Object pty, int rows, int cols) {}

  @override
  void kill(Object pty) {}
}
