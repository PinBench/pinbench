import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinbench_edition_api/host.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinbench/app/edition_host_bindings.dart';
import 'package:pinbench/core/utils/shared_preferences_provider.dart';
import 'package:pinbench/features/workspace/models/workspace_state.dart';
import 'package:pinbench/features/workspace/providers/workspace_files_provider.dart';
import 'package:pinbench/features/workspace/services/template_service.dart';

/// Hands out blank workspaces slowly, and counts them.
class _SlowTemplates extends TemplateService {
  final created = <String>[];
  final gate = Completer<void>();

  @override
  Future<String> createBlankWorkspace() async {
    final path = '/tmp/blank_${created.length}';
    created.add(path);
    await gate.future;
    return path;
  }
}

class _Workspace extends WorkspaceFiles {
  final opened = <String>[];

  @override
  WorkspaceState build() => const WorkspaceState();

  @override
  Future<void> openWorkspace(String path, {bool isTemporary = false}) async {
    opened.add(path);
    state = WorkspaceState(workspacePath: path);
  }
}

void main() {
  late SharedPreferences prefs;
  late _SlowTemplates templates;
  late _Workspace workspace;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'telemetry.consent': 'denied'});
    prefs = await SharedPreferences.getInstance();
    templates = _SlowTemplates();
    workspace = _Workspace();
    container = ProviderContainer(
      overrides: [
        ...editionHostBindings,
        sharedPreferencesProvider.overrideWithValue(prefs),
        templateServiceProvider.overrideWithValue(templates),
        workspaceFilesProvider.overrideWith(() => workspace),
      ],
    );
    addTearDown(container.dispose);
  });

  test('overlapping requests for a workspace share one', () async {
    final host = container.read(hostActionsProvider);

    final first = host.ensureWorkspace();
    final second = host.ensureWorkspace();
    templates.gate.complete();
    await Future.wait([first, second]);

    expect(templates.created, hasLength(1), reason: 'a second blank project was created');
    expect(workspace.opened, hasLength(1));
  });

  test('once a workspace is open, nothing new is created', () async {
    final host = container.read(hostActionsProvider);
    templates.gate.complete();
    await host.ensureWorkspace();
    await host.ensureWorkspace();

    expect(templates.created, hasLength(1));
  });

  test("a panel's settings cannot reach the app's own", () async {
    final host = container.read(hostActionsProvider);

    // The app's consent answer is not visible under the same key...
    expect(host.readSetting('telemetry.consent'), isNull);

    // ...and writing that key leaves the app's answer alone.
    await host.writeSetting('telemetry.consent', 'granted');
    expect(prefs.getString('telemetry.consent'), 'denied');
    expect(host.readSetting('telemetry.consent'), 'granted');
  });
}
