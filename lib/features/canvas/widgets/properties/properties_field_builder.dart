import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_sim/models/simulation_state.dart';
import 'package:pinbench_ui/widgets/color_select.dart';
import 'package:pinbench_ui/ui/app_select.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_text_field.dart';
import 'package:pinbench_ui/ui/app_slider.dart';
import 'package:pinbench_ui/theme/theme.dart';

import '../../controller/canvas_controller.dart';
import '../../../simulation/providers/simulation_provider.dart';

/// Builds the editor widget for one component property, dispatching on the
/// property key (color swatch, potentiometer position slider, or a plain
/// text field). Extracted from `PropertiesSidebarView._buildPropertiesList`
/// so adding a new property type doesn't grow the view file.
abstract final class PropertiesFieldBuilder {
  /// A property a `.pdl` part declares as an enum comes with its [options],
  /// and is shown under its [displayLabel]; [configures] says it picks which
  /// configuration of the part this is.
  static Widget build(
    ComponentInstance node,
    MapEntry<String, dynamic> property,
    CanvasController controller,
    WidgetRef ref, {
    List<String> options = const [],
    String? displayLabel,
    bool configures = false,
  }) {
    final label = property.key;
    final value = property.value.toString();
    if (options.isNotEmpty) {
      return _buildSelect(
        node,
        label,
        displayLabel ?? label,
        value,
        options,
        controller,
        ref,
        configures: configures,
      );
    }
    if (label == ComponentProps.color) {
      return _buildColorDropdown(node, label, value, controller);
    }
    if (label == ComponentProps.potentiometerValue) {
      return _buildPositionSlider(node, label, value, controller, ref);
    }
    return _buildTextInput(node, label, value, controller);
  }

  /// The label gives way, because the control beside it cannot: it is a fixed
  /// width, so a label allowed to wrap breaks mid-word rather than shortening.
  static Widget _buildFieldRow({required String label, required Widget child}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis, softWrap: false)),
        Gap.hMd,
        child,
      ],
    ),
  );

  static Widget _buildFieldColumn({required String label, required Widget child}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label), child]),
  );

  static Widget _buildTextInput(
    ComponentInstance node,
    String label,
    String value,
    CanvasController controller,
  ) => _buildFieldRow(
    label: label,
    child: SizedBox(
      width: 120,
      child: _PropertyTextField(
        key: Key('${node.key}_$label'),
        node: node,
        label: label,
        value: value,
        controller: controller,
      ),
    ),
  );

  static Widget _buildColorDropdown(
    ComponentInstance node,
    String label,
    String value,
    CanvasController controller,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis, softWrap: false)),
        Gap.hMd,
        SizedBox(
          width: 100,
          child: ColorSelect(
            value: value,
            excludeAuto: true,
            customColorsMap: const {
              'Red': AppPalette.red,
              'Blue': AppPalette.blue,
              'Green': AppPalette.green,
              'Yellow': AppPalette.yellow,
              'Cyan': AppPalette.cyan,
              'Pink': AppPalette.pink,
              'Orange': AppPalette.orange,
            },
            onChanged: (newValue) {
              if (newValue != null) {
                final newProps = Map<String, dynamic>.from(node.properties)..[label] = newValue;
                controller.updateNodeProperties(node.key, newProps);
              }
            },
          ),
        ),
      ],
    ),
  );

  /// A `.pdl` enum property, as a dropdown of its options.
  ///
  /// The property a part's configurations are chosen by — a transistor's
  /// Type — changes what the part *is*, not one of its values: it swaps the
  /// placed part and moves its wires (see `CanvasController.reconfigureNode`),
  /// and, mid-run, rebuilds the circuit around the new one.
  static Widget _buildSelect(
    ComponentInstance node,
    String label,
    String displayLabel,
    String value,
    List<String> options,
    CanvasController controller,
    WidgetRef ref, {
    required bool configures,
  }) => _buildFieldRow(
    label: displayLabel,
    child: SizedBox(
      width: 180,
      child: AppSelect<String>(
        key: Key('${node.key}_$label'),
        options: {for (final option in options) option: option},
        value: value,
        onChanged: (picked) {
          if (picked == null || picked == value) return;
          if (configures) {
            controller.reconfigureNode(node.key, picked);
            final simState = ref.read(simulationProvider);
            if (simState == SimulationState.running || simState == SimulationState.paused) {
              ref.read(simulationProvider.notifier).rebuildCircuit();
            }
          } else {
            controller.updateNodeProperties(node.key, {...node.properties, label: picked});
          }
        },
      ),
    ),
  );

  /// A 0–1 slider for the potentiometer wiper. Dragging updates the dial live
  /// (without flooding the undo history); on release the change is recorded once
  /// and, if a simulation is running, the SPICE circuit is rebuilt so
  /// `analogRead` reflects the new wiper voltage.
  static Widget _buildPositionSlider(
    ComponentInstance node,
    String label,
    String value,
    CanvasController controller,
    WidgetRef ref,
  ) {
    final pos = (double.tryParse(value) ?? 0.5).clamp(0.0, 1.0);

    void apply(double v, {required bool record}) {
      final clamped = double.parse(v.clamp(0.0, 1.0).toStringAsFixed(2));
      final newProps = Map<String, dynamic>.from(node.properties)..[label] = clamped;
      controller.updateNodeProperties(node.key, newProps, recordHistory: record);
    }

    return _buildFieldColumn(
      label: label,
      child: Row(
        children: [
          Expanded(
            child: AppSlider(
              key: Key('${node.key}_$label'),
              value: pos,
              onChanged: (v) => apply(v, record: false),
              onChangeEnd: (v) {
                apply(v, record: true);
                // Re-solve the analog model so a turn is reflected mid-run.
                final simState = ref.read(simulationProvider);
                if (simState == SimulationState.running || simState == SimulationState.paused) {
                  ref.read(simulationProvider.notifier).rebuildCircuit();
                }
              },
            ),
          ),
          Gap.hMd,
          SizedBox(width: 32, child: Text(pos.toStringAsFixed(2), textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

/// A property value the user types.
///
/// Stateful because a plain field committing only on `onSubmitted` loses the
/// edit whenever focus leaves without Enter being pressed — which is what
/// clicking back onto the canvas does, and the most natural way to change a
/// resistor. The symptom was a properties panel showing 220 Ω while the `.cdl`,
/// the netlist and the solver all still had the old value.
///
/// So it commits on blur as well as on submit, and — because the same value is
/// editable from the code pane — adopts an external change to the property
/// while the field is not being edited.
class const _PropertyTextField({
  super.key,
  required final ComponentInstance node,
  required final String label,
  required final String value,
  required final CanvasController controller,
}) extends StatefulWidget {
  @override
  State<_PropertyTextField> createState() => _PropertyTextFieldState();
}

class _PropertyTextFieldState extends State<_PropertyTextField> {
  late final _text = TextEditingController(text: widget.value);
  late final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit(_text.text);
    });
  }

  @override
  void didUpdateWidget(_PropertyTextField old) {
    super.didUpdateWidget(old);
    // Adopt a value changed elsewhere (the `.cdl` editor, an undo) unless the
    // user is mid-edit, in which case their typing wins.
    if (widget.value != old.value && !_focus.hasFocus && _text.text != widget.value) {
      _text.text = widget.value;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    if (raw == widget.value) return;

    // A bare number is stored as one; anything with a unit or suffix (`10k`,
    // `4R7`) stays a string, which is what `SpiceModelDef.valueFor` reads.
    final asNumber = double.tryParse(raw);
    final parsed = (asNumber != null && asNumber.toString() == raw) ? asNumber : raw;

    final newProps = Map<String, dynamic>.from(widget.node.properties)..[widget.label] = parsed;
    widget.controller.updateNodeProperties(widget.node.key, newProps);
  }

  @override
  Widget build(BuildContext context) => AppTextField(
    controller: _text,
    focusNode: _focus,
    textAlign: TextAlign.right,
    onSubmitted: _commit,
  );
}
