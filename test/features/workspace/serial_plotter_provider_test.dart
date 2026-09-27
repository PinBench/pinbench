import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench/features/workspace/providers/serial_plotter_provider.dart';

void main() {
  group('parseSerialPlotData', () {
    test('treats the n-th number on each line as channel n', () {
      final data = parseSerialPlotData(['1 2 3', '4 5 6']);
      expect(data.series.length, 3);
      expect(data.series[0], [1, 4]);
      expect(data.series[1], [2, 5]);
      expect(data.series[2], [3, 6]);
    });

    test('parses a single value per line into one channel', () {
      final data = parseSerialPlotData(['10', '20', '30']);
      expect(data.series.length, 1);
      expect(data.series[0], [10, 20, 30]);
    });

    test('handles negatives, decimals and scientific notation', () {
      final data = parseSerialPlotData(['-1.5', '2.0e2']);
      expect(data.series[0], [-1.5, 200.0]);
    });

    test('ignores non-numeric noise around the numbers', () {
      final data = parseSerialPlotData(['temp=23.4C', 'temp=24.1C']);
      expect(data.series.length, 1);
      expect(data.series[0], [23.4, 24.1]);
    });

    test('isEmpty is true until a series has at least two points', () {
      expect(parseSerialPlotData(['hello', 'world']).isEmpty, isTrue);
      expect(parseSerialPlotData(['1']).isEmpty, isTrue);
      expect(parseSerialPlotData(['1', '2']).isEmpty, isFalse);
    });

    test('parses labelled channels and keeps them by name', () {
      final data = parseSerialPlotData(['temp:23.5,humidity:60', 'temp:24,humidity:58']);
      expect(data.series.length, 2);
      expect(data.labelFor(0), 'temp');
      expect(data.labelFor(1), 'humidity');
      expect(data.series[0], [23.5, 24]);
      expect(data.series[1], [60, 58]);
    });

    test('labelled channels keep identity even if their order changes', () {
      final data = parseSerialPlotData(['a:1 b:2', 'b:3 a:4']);
      expect(data.labelFor(0), 'a');
      expect(data.labelFor(1), 'b');
      expect(data.series[0], [1, 4]); // a, in first-seen order
      expect(data.series[1], [2, 3]); // b keeps its identity despite the swap
    });

    test('latest() reports the most recent value per channel', () {
      final data = parseSerialPlotData(['5 6', '7 8']);
      expect(data.latest(0), 7);
      expect(data.latest(1), 8);
    });

    test('unlabelled channels fall back to CHn names', () {
      final data = parseSerialPlotData(['1 2', '3 4']);
      expect(data.labelFor(0), 'CH1');
      expect(data.labelFor(1), 'CH2');
    });
  });
}
