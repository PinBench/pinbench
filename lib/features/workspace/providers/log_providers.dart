import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/logs_repository.dart';

part 'log_providers.g.dart';

@Riverpod(keepAlive: true)
LogsRepository logsRepository(Ref ref) => LogsRepository();

/// Unified log notifier family — replaces DebugLogs, SerialLogs, SpiceLogs.
@Riverpod(keepAlive: true)
class ChannelLogs extends _$ChannelLogs {
  @override
  List<String> build(LogChannel channel) {
    final repo = ref.watch(logsRepositoryProvider);
    void listener() {
      state = repo.getLogs(channel);
    }

    repo.listen(channel, listener);
    ref.onDispose(() => repo.unlisten(channel, listener));
    return repo.getLogs(channel);
  }

  void addLog(String log) {
    ref.read(logsRepositoryProvider).addLog(channel, log);
  }

  void clear() {
    ref.read(logsRepositoryProvider).clear(channel);
  }
}
