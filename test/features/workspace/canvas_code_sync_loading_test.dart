import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pinbench/core/parts/part_registry_provider.dart';
import 'package:pinbench/features/workspace/providers/canvas_code_sync_provider.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench/app/canvas_sync_bindings.dart';

/// Regression test for the startup crash:
/// `AsyncValueIsLoadingException: requireValue was called on AsyncLoading` in
/// `canvasCodeSyncService`. It was hit when the recent-workspace auto-open read
/// the sync service before the async component registry had loaded. The service
/// must build (with no components yet) instead of throwing.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('canvasCodeSyncService builds while the component registry is still loading', () {
    final container = ProviderContainer(
      overrides: [
        ...canvasSyncBindings,
        // A registry future that never completes -> stays AsyncLoading.
        partRegistryProvider.overrideWith((ref) => Completer<List<PartModel>>().future),
      ],
    );
    addTearDown(container.dispose);

    expect(() => container.read(canvasCodeSyncServiceProvider), returnsNormally);
  });
}
