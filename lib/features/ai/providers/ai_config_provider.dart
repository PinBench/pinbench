import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:pinbench_ai/models/ai_config.dart';
import 'package:pinbench_ai/clients/ai_client.dart';
import 'package:pinbench_ai/clients/anthropic_client.dart';
import 'package:pinbench_ai/clients/openai_compatible_client.dart';

import '../../../core/utils/shared_preferences_provider.dart';

part 'ai_config_provider.g.dart';

/// Which model server the assistant talks to, persisted across launches.
@Riverpod(keepAlive: true)
class AiConfigController extends _$AiConfigController {
  static const _prefsKey = 'ai.config';

  @override
  AiConfig build() => AiConfig.decode(ref.read(sharedPreferencesProvider).getString(_prefsKey));

  /// Replaces the configuration and persists it.
  Future<void> save(AiConfig config) async {
    state = config;
    await ref.read(sharedPreferencesProvider).setString(_prefsKey, config.encode());
  }

  /// Convenience for the settings form, which edits one field at a time.
  Future<void> update({String? baseUrl, String? model, String? apiKey, AiProtocol? protocol}) =>
      save(state.copyWith(baseUrl: baseUrl, model: model, apiKey: apiKey, protocol: protocol));

  /// Applies a preset: its URL and protocol, its suggested model when the
  /// current one would not work there, and a cleared key for local servers.
  ///
  /// The model is replaced rather than kept because model ids do not carry
  /// across providers — leaving `qwen2.5-coder:7b` set after switching to
  /// Anthropic produces a 404 on the first message.
  Future<void> applyPreset(AiPreset preset) => save(
    state.copyWith(
      baseUrl: preset.baseUrl,
      protocol: preset.protocol,
      model: preset.suggestedModel ?? '',
      apiKey: preset.needsKey ? state.apiKey : '',
    ),
  );
}

/// The chat backend for the current configuration.
///
/// Rebuilt whenever the configuration changes, which also closes the previous
/// client's connection pool — pointing at a different server must not keep the
/// old one's sockets around, and switching protocol swaps the client entirely.
@Riverpod(keepAlive: true)
AiClient aiClient(Ref ref) {
  final config = ref.watch(aiConfigControllerProvider);
  final client = switch (config.protocol) {
    AiProtocol.openAiCompatible => OpenAiCompatibleClient(config),
    AiProtocol.anthropic => AnthropicClient(config),
  };
  ref.onDispose(client.close);
  return client;
}

/// Model names the configured server offers, for the settings picker.
///
/// Not `keepAlive`: it is a live probe of a server the user may have just
/// started, so it should re-run when the settings panel is reopened rather
/// than cache a failure from before `ollama serve` was running.
@riverpod
Future<List<String>> availableAiModels(Ref ref) {
  final config = ref.watch(aiConfigControllerProvider);
  if (config.baseUrl.trim().isEmpty) return Future.value(const []);
  return ref.watch(aiClientProvider).listModels();
}
