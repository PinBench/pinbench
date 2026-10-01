import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench_ui/widgets/scrubbable_number_field.dart';
import 'package:pinbench_ui/widgets/sidebar_scaffold.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_divider.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/ui/app_switch.dart';
import 'package:pinbench_ui/theme/app_icons.dart';

import '../../controller/canvas_controller.dart';
import 'properties_field_builder.dart';

class const PropertiesSidebarView({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(canvasControllerProvider.notifier);
    // Also watch the state itself (not just the notifier): every field below
    // reads live node data (flip, position, rotation, properties) off
    // `controller.selectedNodes`, so without this the panel never rebuilds
    // when a toggle/slider/field edit changes that data — e.g. the "Flipped
    // Horizontal/Vertical" switches would visually snap back since Flutter
    // keeps rendering them with the stale `value:` from the last build.
    ref.watch(canvasControllerProvider);
    final selectedNode = controller.selectedNodes.firstOrNull;

    return SidebarScaffold(
      title: AppStrings.propertiesSidebarTitle,
      child: selectedNode == null
          ? _buildEmptyState(context)
          : _buildPropertiesList(controller, selectedNode, ref),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            AppIcons.nothingSelected,
            size: AppIconSize.hero,
            color: colors.mutedForeground.withValues(alpha: 0.5),
          ),
          Gap.vXl,
          const Text(AppStrings.noComponentSelectedMessage),
          Gap.vMd,
          const Text(AppStrings.noComponentSelectedSubtext, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildPropertiesList(CanvasController controller, ComponentInstance node, WidgetRef ref) {
    final comp = node.part;
    final definition = PartRegistry.getPart(comp.definitionId ?? '');
    // A `.pdl` part's editable properties are the ones it declares, each at
    // its default until set; its map also carries the state a run writes,
    // which is not the user's to edit. A built-in part's are every key but
    // its runtime flags.
    final properties = definition == null
        ? node.properties.entries.where((e) => !ComponentProps.runtimeFlags.contains(e.key))
        : [
            for (final MapEntry(:key, value: declared) in definition.properties.entries)
              MapEntry<String, dynamic>(key, node.properties[key] ?? declared.defaultValue),
          ];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStaticRow(AppStrings.propertyLabelName, comp.name),
          const AppDivider.section(),
          _buildNumberInput(
            AppStrings.propertyLabelPositionX,
            node.position.dx,
            node,
            (val) => controller.updateNode(node.key, position: Offset(val, node.position.dy)),
          ),
          _buildNumberInput(
            AppStrings.propertyLabelPositionY,
            node.position.dy,
            node,
            (val) => controller.updateNode(node.key, position: Offset(node.position.dx, val)),
          ),
          const AppDivider.section(),
          _buildNumberInput(
            AppStrings.propertyLabelRotation,
            node.rotationAngle * 180 / math.pi,
            node,
            (val) => controller.updateNode(node.key, rotationAngle: val * math.pi / 180),
            defaultValue: 0.0,
            onReset: () => controller.updateNode(node.key, rotationAngle: 0.0),
          ),
          _buildSwitchRow(
            AppStrings.propertyLabelFlipH,
            node.flipHorizontal,
            (val) => controller.updateNode(node.key, flipHorizontal: val),
          ),
          _buildSwitchRow(
            AppStrings.propertyLabelFlipV,
            node.flipVertical,
            (val) => controller.updateNode(node.key, flipVertical: val),
          ),
          const AppDivider.section(),
          _buildNumberInput(
            AppStrings.propertyLabelWidth,
            node.customWidth ?? comp.size.width,
            node,
            (val) => controller.updateNode(node.key, customWidth: val),
            defaultValue: comp.size.width,
            onReset: () => controller.updateNode(node.key, clearCustomWidth: true),
          ),
          _buildNumberInput(
            AppStrings.propertyLabelHeight,
            node.customHeight ?? comp.size.height,
            node,
            (val) => controller.updateNode(node.key, customHeight: val),
            defaultValue: comp.size.height,
            onReset: () => controller.updateNode(node.key, clearCustomHeight: true),
          ),
          if (properties.isNotEmpty) ...[
            const AppDivider.section(),
            for (final property in properties)
              PropertiesFieldBuilder.build(
                node,
                property,
                controller,
                ref,
                options: definition?.properties[property.key]?.options ?? const [],
                displayLabel: definition?.properties[property.key]?.label,
                configures: definition?.configuration?.property == property.key,
              ),
          ],
        ],
      ),
    );
  }

  /// Both halves ellipsize rather than wrap: a two-line label beside a
  /// one-line value reads as a rendering fault, and the value is the half
  /// worth keeping, so it is laid out first and the label takes what is left.
  Widget _buildStaticRow(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Expanded(child: Text(label, overflow: TextOverflow.ellipsis, softWrap: false)),
      Gap.hMd,
      Flexible(child: Text(value, overflow: TextOverflow.ellipsis, softWrap: false)),
    ],
  );

  Widget _buildSwitchRow(String label, bool value, ValueChanged<bool> onChanged) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // The switch is a fixed-size control and the sidebar is narrow, so the
        // label is what gives way. "Flipped Horizontal" does not fit beside it
        // at this width.
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis, softWrap: false)),
        AppSwitch(value: value, onChanged: onChanged),
      ],
    ),
  );

  Widget _buildNumberInput(
    String label,
    double value,
    ComponentInstance node,
    void Function(double) onChanged, {
    double? defaultValue,
    VoidCallback? onReset,
  }) => ScrubbableNumberField(
    key: Key('${node.key}_$label'),
    label: label,
    value: value,
    defaultValue: defaultValue,
    onReset: onReset,
    onChanged: onChanged,
  );
}
