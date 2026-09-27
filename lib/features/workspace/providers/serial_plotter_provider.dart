import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'debug_console_provider.dart';

part 'serial_plotter_provider.g.dart';

/// Parsed numeric series extracted from the serial monitor, for the plotter.
///
/// Two input conventions are supported (both match the Arduino IDE plotter):
///  * **Positional** — bare numbers, where the n-th number on every line forms
///    channel n: `Serial.println("$a $b")`.
///  * **Labelled** — `name:value` tokens, where each name is a stable channel:
///    `Serial.println("temp:23.5,humidity:60")`. Labelled channels keep their
///    identity even if their order changes between lines.
///
/// [series] is `series[channel] = values over time`; [labels] holds the channel
/// name (empty string for a positional channel).
class SerialPlotData {
  const SerialPlotData(this.series, {this.labels = const []});

  final List<List<double>> series;
  final List<String> labels;

  bool get isEmpty => series.every((s) => s.length < 2);

  /// The most recent value of channel [i], or null if it has none yet.
  double? latest(int i) => (i < series.length && series[i].isNotEmpty) ? series[i].last : null;

  /// A display name for channel [i] — its label, or `CH{n}` when unlabelled.
  String labelFor(int i) => (i < labels.length && labels[i].isNotEmpty) ? labels[i] : 'CH${i + 1}';
}

/// Keep the plot bounded so long-running sketches don't grow unboundedly.
const _maxPointsPerSeries = 300;

/// Splits a serial line into tokens on whitespace, commas and semicolons.
final _separator = RegExp(r'[\s,;]+');

/// A `name:value` token (the label may not contain the separators above).
final _labeledPattern = RegExp(r'^([A-Za-z_]\w*):([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)$');

/// A bare number anywhere inside a token (e.g. `temp=23.4C` -> 23.4).
final _numberPattern = RegExp(r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?');

/// Parses serial [logs] into per-channel numeric series. Pure (no Riverpod) so
/// it is directly unit-testable.
SerialPlotData parseSerialPlotData(List<String> logs) {
  final series = <List<double>>[];
  final labels = <String>[];
  final indexByKey = <String, int>{};

  int channelFor(String key, String label) => indexByKey[key] ??= () {
    series.add(<double>[]);
    labels.add(label);
    return series.length - 1;
  }();

  for (final line in logs) {
    var positional = 0;
    for (final token in line.split(_separator)) {
      if (token.isEmpty) continue;

      final labeled = _labeledPattern.firstMatch(token);
      if (labeled != null) {
        final value = double.tryParse(labeled.group(2)!);
        if (value == null) continue;
        final name = labeled.group(1)!;
        series[channelFor('name:$name', name)].add(value);
        continue;
      }

      // Otherwise pull bare numbers out of the token as positional channels.
      for (final m in _numberPattern.allMatches(token)) {
        final value = double.tryParse(m.group(0)!);
        if (value == null) continue;
        series[channelFor('pos:$positional', '')].add(value);
        positional++;
      }
    }
  }

  // Trim each series to the most recent window.
  for (var i = 0; i < series.length; i++) {
    final s = series[i];
    if (s.length > _maxPointsPerSeries) {
      series[i] = s.sublist(s.length - _maxPointsPerSeries);
    }
  }

  return SerialPlotData(series, labels: labels);
}

/// Derives [SerialPlotData] from the live serial log.
@riverpod
SerialPlotData serialPlotterData(Ref ref) => parseSerialPlotData(ref.watch(serialLogsProvider));
