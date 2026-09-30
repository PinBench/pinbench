import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_ui/widgets/sidebar_scaffold.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_text_field.dart';
import 'package:pinbench_ui/ui/app_accordion.dart';
import 'package:pinbench_ui/ui/app_spinner.dart';

import 'palette_component.dart';
import '../../../../core/parts/part_registry_provider.dart';

class const PartsSidebarView({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<PartsSidebarView> createState() => _PartsSidebarViewState();
}

class _PartsSidebarViewState extends ConsumerState<PartsSidebarView> {
  var _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final componentsAsync = ref.watch(partRegistryProvider);

    return SidebarScaffold(
      title: AppStrings.partsSidebarTitle,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: AppTextField(
              placeholder: AppStrings.searchComponentsPlaceholder,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.toLowerCase();
                });
              },
            ),
          ),
          Expanded(
            child: componentsAsync.when(
              loading: () => const Center(child: AppSpinner()),
              error: (e, st) => Center(child: Text(AppStrings.genericErrorMessage(e))),
              data: (allComponents) {
                final filtered = allComponents
                    .where(
                      (c) =>
                          [c.name, ...c.aliases].any((n) => n.toLowerCase().contains(_searchQuery)),
                    )
                    .toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text(AppStrings.noComponentsFoundMessage));
                }

                // Group by category
                final grouped = <PartCategory, List<PartModel>>{};
                for (final c in filtered) {
                  grouped.putIfAbsent(c.category, () => []).add(c);
                }

                // Build Accordion
                return SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: AppAccordion(
                      sections: [
                        for (final entry in grouped.entries)
                          AppAccordionSection(
                            title: entry.key.name[0].toUpperCase() + entry.key.name.substring(1),
                            child: _buildGrid(entry.value),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<PartModel> components) => LayoutBuilder(
    builder: (context, constraints) {
      var crossAxisCount = 3;
      if (constraints.maxWidth <= 250) {
        crossAxisCount = 1;
      } else if (constraints.maxWidth <= 400) {
        crossAxisCount = 2;
      } else {
        crossAxisCount = 3;
      }

      const spacing = 8.0;
      const childAspectRatio = 0.6;
      final availableWidth = constraints.maxWidth;
      final usableWidth = availableWidth > 0 ? availableWidth : 1.0;
      final itemWidth = (usableWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;
      final itemHeight = itemWidth / childAspectRatio;

      final rowCount = (components.length / crossAxisCount).ceil();
      final totalHeight = rowCount > 0 ? (rowCount * itemHeight + (rowCount - 1) * spacing) : 0.0;

      return SizedBox(
        height: totalHeight,
        width: usableWidth,
        child: Stack(
          children: List.generate(components.length, (index) {
            final col = index % crossAxisCount;
            final row = index ~/ crossAxisCount;
            final left = col * (itemWidth + spacing);
            final top = row * (itemHeight + spacing);

            return AnimatedPositioned(
              key: ValueKey(components[index].name),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              left: left,
              top: top,
              width: itemWidth,
              height: itemHeight,
              child: PaletteComponent(part: components[index]),
            );
          }),
        ),
      );
    },
  );
}
