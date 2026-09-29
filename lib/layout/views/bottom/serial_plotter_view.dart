import 'package:flutter/widgets.dart';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/theme/text.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import '../../../features/workspace/providers/serial_plotter_provider.dart';

/// Plots numeric values printed to the serial monitor over time, one line per
/// channel (the Arduino IDE Serial Plotter convention). Print e.g.
/// `Serial.println(value)`, `Serial.println("$a $b")`, or labelled channels
/// `Serial.println("temp:23.5,humidity:60")` to chart them.
class const SerialPlotterView({super.key}) extends ConsumerWidget {
  static const _seriesColors = [
    Color(0xFF4FC3F7),
    Color(0xFFFF8A65),
    Color(0xFF81C784),
    Color(0xFFBA68C8),
    Color(0xFFFFD54F),
    Color(0xFFE57373),
  ];

  static Color _colorFor(int i) => _seriesColors[i % _seriesColors.length];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final data = ref.watch(serialPlotterDataProvider);

    if (data.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              AppIcons.serialPlotter,
              size: AppIconSize.hero,
              color: colors.mutedForeground.withValues(alpha: 0.5),
            ),
            Gap.vXl,
            const Text(AppStrings.noPlotterDataMessage),
            Gap.vMd,
            const Text(AppStrings.plotterHintMessage, textAlign: TextAlign.center),
          ],
        ),
      );
    }

    final bars = <LineChartBarData>[];
    final plotted = <int>[]; // channel indices that made it onto the chart
    for (var i = 0; i < data.series.length; i++) {
      final values = data.series[i];
      if (values.length < 2) continue;
      plotted.add(i);
      bars.add(
        LineChartBarData(
          spots: [for (var x = 0; x < values.length; x++) FlSpot(x.toDouble(), values[x])],
          barWidth: 1.5,
          color: _colorFor(i),
          dotData: const FlDotData(show: false),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Legend(data: data, channels: plotted),
          Gap.vMd,
          Expanded(child: _chart(colors, bars)),
        ],
      ),
    );
  }

  Widget _chart(AppColorScheme colors, List<LineChartBarData> bars) => LineChart(
    LineChartData(
      lineBarsData: bars,
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: colors.border.withValues(alpha: 0.4), strokeWidth: 0.5),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => colors.surface,
          getTooltipItems: (spots) => [
            for (final s in spots)
              LineTooltipItem(s.y.toStringAsFixed(2), AppTextStyles.plotterLabel(s.bar.color)),
          ],
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        bottomTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(0)),
          ),
        ),
      ),
    ),
  );
}

/// A compact legend: one chip per plotted channel showing its colour, label and
/// latest value.
class const _Legend({required final SerialPlotData data, required final List<int> channels})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 4,
    children: [
      for (final i in channels)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: SerialPlotterView._colorFor(i),
                borderRadius: AppRadii.xsAll,
              ),
            ),
            Gap.hSm,
            Text(data.labelFor(i), style: context.appText.sm),
            Gap.hXs,
            Text(data.latest(i)?.toStringAsFixed(2) ?? '—'),
          ],
        ),
    ],
  );
}
