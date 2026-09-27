import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench/core/utils/shared_preferences_provider.dart';
import 'package:pinbench_ai/models/ai_config.dart';
import 'package:pinbench_ai/models/chat_message.dart';
import 'package:pinbench_ai/models/file_proposal.dart';
import 'package:pinbench/features/ai/providers/ai_chat_provider.dart';
import 'package:pinbench/features/ai/providers/ai_config_provider.dart';
import 'package:pinbench_ai/clients/ai_client.dart';
import 'package:pinbench/core/parts/part_registry_provider.dart';
import 'package:pinbench/features/workspace/providers/workspace_files_provider.dart';

/// An [AiClient] that replays a scripted reply, so the notifier's streaming,
/// cancellation and error handling are testable without a model server.
class _FakeAiClient implements AiClient {
  _FakeAiClient({this.chunks = const [], this.failure});

  final List<String> chunks;
  final Object? failure;

  /// The system prompt of the last request, for asserting it was sent.
  String? lastSystem;

  /// The transcript of the last request.
  List<ChatMessage> lastHistory = const [];

  @override
  Stream<String> streamChat({required String system, required List<ChatMessage> history}) {
    lastSystem = system;
    lastHistory = history;
    if (failure != null) return Stream<String>.error(failure!);
    return Stream.fromIterable(chunks);
  }

  @override
  Future<List<String>> listModels() async => const [];

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  ProviderContainer configured(AiClient client, {AiConfig? config}) {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        aiClientProvider.overrideWithValue(client),
        // Reading the real registry needs an asset bundle; the built-in palette
        // is what the prompt is built from anyway.
        partRegistryProvider.overrideWith((ref) async => standardParts),
      ],
    );
    addTearDown(container.dispose);
    unawaited(
      container
          .read(aiConfigControllerProvider.notifier)
          .save(config ?? const AiConfig(model: 'test-model')),
    );
    return container;
  }

  group('AiChat', () {
    test('streams a reply into the transcript and extracts its proposals', () async {
      final client = _FakeAiClient(
        chunks: ['Here is the circuit.\n\n```cdl\n', 'Circuit {\n}\n', '```\n'],
      );
      final container = configured(client);

      await container.read(aiChatProvider.notifier).send('blink an LED');
      await pumpEventQueue();

      final messages = container.read(aiChatProvider);
      expect(messages, hasLength(2));
      expect(messages.first.role, ChatRole.user);
      expect(messages.first.text, 'blink an LED');

      final reply = messages.last;
      expect(reply.role, ChatRole.assistant);
      expect(reply.isStreaming, isFalse);
      expect(reply.text, contains('Circuit {'));
      expect(reply.proposals.single.kind, ProposalKind.circuit);
      // The prose shown above the proposal card excludes the code block.
      expect(reply.prose, 'Here is the circuit.');
    });

    test('sends the generated system prompt and the prior turns', () async {
      final client = _FakeAiClient(chunks: const ['ok']);
      final container = configured(client);

      await container.read(aiChatProvider.notifier).send('first');
      await pumpEventQueue();
      await container.read(aiChatProvider.notifier).send('second');
      await pumpEventQueue();

      expect(client.lastSystem, contains('## ArduinoUno'));
      expect(client.lastHistory.map((m) => m.text), ['first', 'ok', 'second']);
      // The empty placeholder for the reply being generated is not sent.
      expect(client.lastHistory.every((m) => !m.isStreaming), isTrue);
    });

    test('records a failure on the assistant turn instead of dropping it', () async {
      final container = configured(_FakeAiClient(failure: const AiException('server is down')));

      await container.read(aiChatProvider.notifier).send('hello');
      await pumpEventQueue();

      final reply = container.read(aiChatProvider).last;
      expect(reply.error, 'server is down');
      expect(reply.isStreaming, isFalse);
      expect(container.read(aiChatProvider).first.text, 'hello');
    });

    test('explains itself rather than calling out when no model is configured', () async {
      final client = _FakeAiClient(chunks: const ['should not be reached']);
      final container = configured(client, config: const AiConfig());

      await container.read(aiChatProvider.notifier).send('hello');
      await pumpEventQueue();

      expect(container.read(aiChatProvider).last.error, contains('No model is configured'));
      expect(client.lastSystem, isNull);
    });

    test('ignores an empty prompt', () async {
      final container = configured(_FakeAiClient());

      await container.read(aiChatProvider.notifier).send('   ');

      expect(container.read(aiChatProvider), isEmpty);
    });

    test('stop keeps the partial reply and extracts what completed', () async {
      final client = _FakeAiClient(chunks: ['```cdl\nCircuit {\n}\n```\nand then I rambl']);
      final container = configured(client);

      await container.read(aiChatProvider.notifier).send('blink');
      await pumpEventQueue();
      await container.read(aiChatProvider.notifier).stop();

      final reply = container.read(aiChatProvider).last;
      expect(reply.isStreaming, isFalse);
      expect(reply.proposals.single.kind, ProposalKind.circuit);
    });

    // The bug: build a project with the assistant, press Home, then ask for
    // something else — the previous exchange was still in the transcript, so
    // the model was handed the old circuit and answered about that instead,
    // and the stale Apply buttons above it were still live.
    test('ends the conversation when the project is left', () async {
      final container = configured(_FakeAiClient(chunks: const ['ok']));

      await container.read(aiChatProvider.notifier).send('Blink an LED on pin 13');
      await pumpEventQueue();
      expect(container.read(aiChatProvider), isNotEmpty);

      final project = Directory.systemTemp.createTempSync('fap_chat_test');
      addTearDown(() => project.deleteSync(recursive: true));
      await container
          .read(workspaceFilesProvider.notifier)
          .setWorkspace(workspacePath: project.path);
      await pumpEventQueue();
      expect(container.read(aiChatProvider), isNotEmpty, reason: 'opening it keeps the thread');

      // What the Home button does, via closeFolder().
      container.read(workspaceFilesProvider.notifier).clearWorkspaceState();
      await pumpEventQueue();

      expect(container.read(aiChatProvider), isEmpty);
    });

    // The welcome prompt starts the conversation and *then* makes somewhere to
    // put the answer, so the first project opening under it must not wipe it.
    test('survives the first project opening under it', () async {
      final container = configured(_FakeAiClient(chunks: const ['ok']));

      await container.read(aiChatProvider.notifier).send('Blink an LED on pin 13');
      await pumpEventQueue();
      final project = Directory.systemTemp.createTempSync('fap_chat_test');
      addTearDown(() => project.deleteSync(recursive: true));
      await container
          .read(workspaceFilesProvider.notifier)
          .setWorkspace(workspacePath: project.path);
      await pumpEventQueue();

      expect(container.read(aiChatProvider), isNotEmpty);
    });

    test('clear empties the transcript', () async {
      final container = configured(_FakeAiClient(chunks: const ['hi']));

      await container.read(aiChatProvider.notifier).send('hello');
      await pumpEventQueue();
      await container.read(aiChatProvider.notifier).clear();

      expect(container.read(aiChatProvider), isEmpty);
    });
  });
}
