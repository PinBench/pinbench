import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/services/logs_repository.dart';
import 'log_providers.dart';

part 'debug_console_provider.g.dart';

/// Backward-compatible aliases for [channelLogsProvider].
final debugLogsProvider = channelLogsProvider(LogChannel.debug);
final serialLogsProvider = channelLogsProvider(LogChannel.serial);
final spiceLogsProvider = channelLogsProvider(LogChannel.spice);

@Riverpod(keepAlive: true)
class VerticalPanelRatio extends _$VerticalPanelRatio {
  var _savedRatio = 0.6;

  @override
  double build() => 0.6;

  void updateRatio(double ratio) {
    state = ratio;
    if (ratio < 0.95) {
      _savedRatio = ratio;
    }
  }

  void toggleCollapse() {
    if (state >= 0.95) {
      state = _savedRatio;
    } else {
      _savedRatio = state;
      state = 1.0;
    }
  }
}
