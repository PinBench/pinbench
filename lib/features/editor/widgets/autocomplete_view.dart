import 'package:flutter/widgets.dart';

import 'package:re_editor/re_editor.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/theme.dart';
import 'package:pinbench_ui/ui/app_button.dart';

class const AutocompleteOptionsView({
  super.key,
  required final ValueNotifier<CodeAutocompleteEditingValue> notifier,
  required final ValueChanged<CodeAutocompleteResult> onSelected,
}) extends StatelessWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size(250, 250);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<CodeAutocompleteEditingValue>(
    valueListenable: notifier,
    builder: (context, value, child) => DecoratedBox(
      decoration: BoxDecoration(
        color: context.appColors.background,
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: context.appColors.border),
        boxShadow: AppElevation.popover,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 250),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          shrinkWrap: true,
          itemCount: value.prompts.length,
          itemBuilder: (context, index) {
            final prompt = value.prompts[index];
            final isSelected = index == value.index;
            return AppTappable(
              onPressed: () => onSelected(value.copyWith(index: index).autocomplete),
              // The keyboard's choice keeps its accent; the pointer's gets the
              // quieter hover fill, so the two can be told apart.
              builder: (context, child, {required hovered}) => ColoredBox(
                color: isSelected
                    ? context.appColors.accent
                    : (hovered ? context.appColors.muted : AppPalette.transparent),
                child: child,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Text(prompt.word),
              ),
            );
          },
        ),
      ),
    ),
  );
}
