import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ai/models/ai_config.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/text.dart';
import 'package:pinbench_ui/ui/app_icon_button.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_button.dart';
import 'package:pinbench_ui/ui/app_text_field.dart';
import 'package:pinbench_ui/ui/app_select.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import '../providers/ai_config_provider.dart';

/// Where the assistant's model lives: a preset, a URL, a model name and an
/// optional key.
///
/// Shown in two places — inline in the chat panel when nothing is configured
/// yet, and in the Settings sidebar afterwards — so it is one widget rather
/// than a form duplicated per host.
class AiSettingsPanel extends ConsumerStatefulWidget {
  /// Creates the settings form.
  const AiSettingsPanel({super.key});

  @override
  ConsumerState<AiSettingsPanel> createState() => _AiSettingsPanelState();
}

class _AiSettingsPanelState extends ConsumerState<AiSettingsPanel> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _apiKey;

  @override
  void initState() {
    super.initState();
    final config = ref.read(aiConfigControllerProvider);
    _baseUrl = TextEditingController(text: config.baseUrl);
    _model = TextEditingController(text: config.model);
    _apiKey = TextEditingController(text: config.apiKey);
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  void _applyPreset(AiPreset preset) {
    _baseUrl.text = preset.baseUrl;
    _model.text = preset.suggestedModel ?? '';
    if (!preset.needsKey) _apiKey.clear();
    unawaited(ref.read(aiConfigControllerProvider.notifier).applyPreset(preset));
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(aiConfigControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in AiPreset.all)
              AppButton(
                variant: AppButtonVariant.outline,
                onPressed: () => _applyPreset(preset),
                size: AppButtonSize.sm,
                // forui styles the current choice through `selected` rather
                // than a background override, which is what this always meant.
                selected: preset.baseUrl == config.baseUrl.trim(),
                child: Text(preset.label),
              ),
          ],
        ),
        if (_hintFor(config) case final hint?) ...[
          Gap.vSm,
          Text(hint, style: AppTextStyles.smallMuted(context)),
        ],
        Gap.vLg,
        _Field(
          label: AppStrings.aiBaseUrlLabel,
          child: AppTextField(
            controller: _baseUrl,
            onChanged: (value) =>
                unawaited(ref.read(aiConfigControllerProvider.notifier).update(baseUrl: value)),
          ),
        ),
        Gap.vLg,
        _Field(
          label: AppStrings.aiModelLabel,
          trailing: _ModelReloadButton(),
          child: _ModelPicker(controller: _model),
        ),
        Gap.vLg,
        _Field(
          label: AppStrings.aiApiKeyLabel,
          child: AppTextField(
            controller: _apiKey,
            obscureText: true,
            placeholder: AppStrings.aiApiKeyPlaceholder,
            onChanged: (value) =>
                unawaited(ref.read(aiConfigControllerProvider.notifier).update(apiKey: value)),
          ),
        ),
        Gap.vSm,
        Text(AppStrings.aiApiKeyNote, style: AppTextStyles.smallMuted(context)),
      ],
    );
  }

  /// The setup note for whichever preset the current URL matches, so the hint
  /// tracks what is actually configured rather than what was last clicked.
  String? _hintFor(AiConfig config) {
    for (final preset in AiPreset.all) {
      if (preset.baseUrl == config.baseUrl.trim()) return preset.hint;
    }
    return null;
  }
}

/// The model name: a dropdown of what the server reports, and always a free
/// text field too — a server that does not implement `/models` (or is not
/// running yet) must not make the model un-settable.
class _ModelPicker extends ConsumerWidget {
  const _ModelPicker({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final models = ref.watch(availableAiModelsProvider);
    final current = ref.watch(aiConfigControllerProvider).model;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: controller,
          placeholder: AppStrings.aiModelPlaceholder,
          onChanged: (value) =>
              unawaited(ref.read(aiConfigControllerProvider.notifier).update(model: value)),
        ),
        Gap.vSm,
        switch (models) {
          AsyncLoading() => Text(
            AppStrings.aiModelsLoading,
            style: AppTextStyles.smallMuted(context),
          ),
          AsyncError() => Text(
            AppStrings.aiNoModelsFound,
            style: AppTextStyles.smallMuted(context),
          ),
          AsyncValue(value: final list?) when list.isNotEmpty => AppSelect<String>(
            placeholder: AppStrings.aiModelLabel,
            value: list.contains(current) ? current : null,
            options: {for (final id in list) id: id},
            onChanged: (value) {
              if (value == null) return;
              controller.text = value;
              unawaited(ref.read(aiConfigControllerProvider.notifier).update(model: value));
            },
          ),
          _ => Text(AppStrings.aiNoModelsFound, style: AppTextStyles.smallMuted(context)),
        },
      ],
    );
  }
}

class _ModelReloadButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) => AppIconButton(
    icon: AppIcons.refresh,
    size: AppIconButtonSize.small,
    tooltip: AppStrings.aiRefreshModelsTooltip,
    isLoading: ref.watch(availableAiModelsProvider).isLoading,
    onPressed: () => ref.invalidate(availableAiModelsProvider),
  );
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.trailing});

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: AppTextStyles.smallMuted(context))),
          ?trailing,
        ],
      ),
      Gap.vXs,
      child,
    ],
  );
}
