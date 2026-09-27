import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_sim/models/simulation_state.dart';
import 'package:pinbench_ui/theme/theme.dart';

import '../../features/editor/providers/editor_provider.dart';
import '../../features/simulation/providers/simulation_provider.dart';
import 'telemetry_providers.dart';

/// Wraps the app and turns cross-cutting state changes into telemetry:
/// navigation, theme, simulation-state crash context, and a flush of buffered
/// OpenTelemetry spans before the app exits or is backgrounded.
///
/// Explicit actions (buttons, menu items, feature usage) are logged at their
/// call sites via [analyticsProvider] / [tracingProvider]; this holds only the
/// implicit, app-lifecycle-scoped telemetry.
///
/// Navigation is logged as a **normalized screen name** (`editor` / `canvas` /
/// `welcome`) plus file extension — never the raw tab id, which is an absolute
/// file path and would leak the user's home directory / username.
class TelemetryListener extends ConsumerStatefulWidget {
  const TelemetryListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<TelemetryListener> createState() => _TelemetryListenerState();
}

class _TelemetryListenerState extends ConsumerState<TelemetryListener> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // OpenTelemetry batches spans (~5s), so the last batch can be lost on quit.
    // Flush on a cancelable exit (desktop ⌘Q / window close) and on pause
    // (mobile backgrounding). No-op when tracing is disabled (web / unconfigured).
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await ref.read(tracingProvider).flush();
        return AppExitResponse.exit;
      },
      onPause: () => unawaited(ref.read(tracingProvider).flush()),
    );
    // Seed the initial theme user property (ref.listen only fires on change).
    ref.read(analyticsProvider).setTheme(ref.read(themeModeProvider).name);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(activeTabProvider, (previous, next) {
      if (next.isEmpty || next == previous) return;
      final screen = _describeScreen(next);
      ref.read(analyticsProvider)
        ..tabSwitched(screen.name, fileType: screen.fileType)
        ..logScreen(screen.name);
      ref.read(crashReporterProvider).setKey('screen', screen.name);
      // Mirror navigation into OpenTelemetry as a marker span (native only;
      // no-op on the web). Uses the normalized screen, not the raw path.
      unawaited(
        ref
            .read(tracingProvider)
            .trace(
              'navigate.tab',
              () async {},
              attributes: {
                'screen': screen.name,
                if (screen.fileType != null) 'file_type': screen.fileType!,
              },
            ),
      );
    });

    ref.listen<AppThemeMode>(themeModeProvider, (_, mode) {
      ref.read(analyticsProvider).setTheme(mode.name);
      ref.read(crashReporterProvider).setKey('theme', mode.name);
    });

    ref.listen<SimulationState>(simulationProvider, (_, state) {
      ref.read(crashReporterProvider).setKey('sim_state', state.name);
    });

    return widget.child;
  }
}

/// Maps a tab id (an absolute file path, `canvas_<path>`, or `Welcome`) to a
/// PII-free screen name + file extension.
({String name, String? fileType}) _describeScreen(String tabId) {
  if (tabId == 'Welcome' || tabId == 'welcome') {
    return (name: 'welcome', fileType: null);
  }
  if (tabId.startsWith('canvas_')) {
    return (name: 'canvas', fileType: _extension(tabId));
  }
  return (name: 'editor', fileType: _extension(tabId));
}

/// The file extension (including the leading dot, e.g. `.ino`) of [path], or
/// null. Never returns anything path-like.
String? _extension(String path) {
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf(RegExp(r'[/\\]'));
  if (dot <= slash || dot == path.length - 1) return null;
  return path.substring(dot);
}
