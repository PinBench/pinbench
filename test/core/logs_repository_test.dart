import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/core/services/logs_repository.dart';

void main() {
  group('LogsRepository', () {
    test('stores logs per channel independently', () {
      final repo = LogsRepository();
      repo.addLog(LogChannel.debug, 'd1');
      repo.addLog(LogChannel.serial, 's1');
      repo.addLog(LogChannel.debug, 'd2');

      expect(repo.getLogs(LogChannel.debug), ['d1', 'd2']);
      expect(repo.getLogs(LogChannel.serial), ['s1']);
      expect(repo.getLogs(LogChannel.spice), isEmpty);
    });

    test('clear empties only the targeted channel', () {
      final repo = LogsRepository();
      repo.addLog(LogChannel.debug, 'd1');
      repo.addLog(LogChannel.spice, 'sp1');

      repo.clear(LogChannel.debug);

      expect(repo.getLogs(LogChannel.debug), isEmpty);
      expect(repo.getLogs(LogChannel.spice), ['sp1']);
    });

    test('caps each channel at 1000 entries, keeping the most recent', () {
      final repo = LogsRepository();
      for (var i = 0; i < 1200; i++) {
        repo.addLog(LogChannel.serial, 'line $i');
      }
      final logs = repo.getLogs(LogChannel.serial);
      expect(logs.length, 1000);
      expect(logs.first, 'line 200');
      expect(logs.last, 'line 1199');
    });

    test('getLogs returns a copy that does not mutate internal state', () {
      final repo = LogsRepository();
      repo.addLog(LogChannel.debug, 'a');
      repo.getLogs(LogChannel.debug).add('b');
      expect(repo.getLogs(LogChannel.debug), ['a']);
    });
  });
}
