import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/widgets/color_select.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/tokens.dart';

import '../../providers/canvas_controller_provider.dart';

class const WireColorSelect({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the STATE, not just the notifier: selecting a wire only bumps the
    // canvas state, and without this subscription the dropdown never rebuilt,
    // so it kept showing the previous color. A select only reports a pick that
    // differs from the value it is displaying — so a stale "Red" made picking
    // Red a silent no-op until some other color was chosen first. `AppSelect`
    // is controlled for this reason, but it can only be as fresh as its input.
    ref.watch(canvasControllerProvider);
    final controller = ref.watch(canvasControllerProvider.notifier);

    var targetColor = controller.wiringManager.currentWireColor;

    if (controller.selectionManager.selectedWireIds.isNotEmpty) {
      final wireIndex = controller.wires.indexWhere(
        (w) => w.id == controller.selectionManager.selectedWireIds.first,
      );
      if (wireIndex != -1) {
        targetColor = controller.wires[wireIndex].color;
      }
    }

    var selectedColorName = 'Auto';
    for (final entry in ColorSelect.colorsMap.entries) {
      if (entry.value?.toARGB32() == targetColor?.toARGB32()) {
        selectedColorName = entry.key;
        break;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: Row(
        spacing: 8,
        children: [
          const Text(AppStrings.wireColorLabel),
          SizedBox(
            width: 90,
            child: ColorSelect(
              value: selectedColorName,
              openUpwards: true,
              onChanged: (newValue) {
                if (newValue == null) return;
                controller.updateWireColor(ColorSelect.colorsMap[newValue]);
              },
            ),
          ),
        ],
      ),
    );
  }
}
