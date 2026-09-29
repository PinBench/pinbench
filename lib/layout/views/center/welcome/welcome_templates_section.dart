import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_parts/models/component_instance.dart';
import 'package:pinbench_parts/models/wire_model.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/theme/app_colors.dart';
import 'package:pinbench_ui/theme/app_icons.dart';
import 'package:pinbench_ui/ui/app_spinner.dart';

import 'welcome_list_tile.dart';
import '../../../../app/router.dart';
import '../../../../features/canvas/widgets/components/circuit_preview.dart';
import '../../../../features/workspace/services/template_service.dart';

/// The Welcome screen's "Templates" card: bundled example circuits, each with
/// a rendered circuit-preview thumbnail (falls back to a plain icon while
/// the preview loads or if it fails to parse).
///
/// The thumbnails are built only once their tile is at or near the viewport.
/// Asking for all of them up front meant parsing every bundled circuit and
/// laying out every component painter before the welcome screen could settle —
/// measured at ~200ms of work for nine templates, most of them below the fold
/// and several never looked at.
class const WelcomeTemplatesSection({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(availableTemplatesProvider);

    return templatesAsync.when(
      data: (templates) {
        if (templates.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Text(AppStrings.noTemplatesFoundMessage),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: templates.map((template) {
            final label = template
                .split('_')
                .map((word) {
                  if (word.isEmpty) return '';
                  return word.substring(0, 1).toUpperCase() + word.substring(1);
                })
                .join(' ');

            // Both branches build the same tile at the same size — the tile
            // falls back to an icon box with the thumbnail's footprint — so a
            // thumbnail arriving never moves anything.
            Widget tile(({List<ComponentInstance> nodes, List<WireModel> wires})? preview) =>
                WelcomeListTile(
                  icon: AppIcons.hint,
                  title: label,
                  subtitle: AppStrings.templateTileSubtitle,
                  leading: preview == null
                      ? null
                      : Container(
                          width: AppChrome.tileThumbSize,
                          height: AppChrome.tileThumbSize,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: context.appColors.accent,
                            borderRadius: AppRadii.smAll,
                          ),
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: CircuitPreview(nodes: preview.nodes, wires: preview.wires),
                        ),
                  // Deep-links the template so the browser URL, back/forward,
                  // and refresh all reflect it on the web; the route then opens
                  // the workspace on every platform.
                  onTap: () => TemplateRoute(template: template).go(context),
                );

            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _WhenNearViewport(
                placeholder: tile(null),
                // The `watch` lives in here on purpose: a provider is only
                // reached — and its circuit only parsed — once this builds.
                builder: (context) => Consumer(
                  builder: (context, ref, _) =>
                      tile(ref.watch(templateCircuitPreviewProvider(template)).value),
                ),
              ),
            );
          }).toList(),
        );
      },
      loading: () => const Center(
        child: Padding(padding: EdgeInsets.all(AppSpacing.xxl), child: AppSpinner()),
      ),
      error: (err, stack) => const Text(AppStrings.templatesLoadErrorMessage),
    );
  }
}

/// Shows [placeholder] until this widget is at or near the viewport, then
/// [builder] — and keeps it from then on.
///
/// The Welcome screen is one long scroll view, so every tile in it is *built*
/// whether or not it is on screen. That is cheap for a row of text and not at
/// all cheap for a rendered circuit, which is why the thumbnail waits for its
/// tile to be worth drawing.
///
/// Sticky once shown: a thumbnail that unbuilt itself on scrolling away would
/// throw away the parse and redo it on the way back, and would flicker at the
/// boundary.
class const _WhenNearViewport({
  required final Widget placeholder,
  required final WidgetBuilder builder,
}) extends StatefulWidget {
  @override
  State<_WhenNearViewport> createState() => _WhenNearViewportState();
}

class _WhenNearViewportState extends State<_WhenNearViewport> {
  /// How far beyond the viewport still counts as near, so a thumbnail is
  /// already there by the time it is scrolled to rather than appearing under
  /// the reader's eye. Roughly three tiles' worth.
  static const _margin = 200.0;

  var _reached = false;
  ScrollPosition? _scroll;

  @override
  void initState() {
    super.initState();
    // After the first frame: this needs its own geometry, which does not exist
    // until it has been laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scroll?.removeListener(_check);
    _scroll = Scrollable.maybeOf(context)?.position;
    _scroll?.addListener(_check);
  }

  @override
  void dispose() {
    _scroll?.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (_reached || !mounted) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    // Measured against the window rather than the scroll viewport's own rect:
    // it needs no knowledge of which scrollable it is in, and a tile off the
    // top of the window is as invisible as one off the bottom. With no
    // MediaQuery to ask, everything counts as visible — the safe answer.
    final viewportHeight = MediaQuery.maybeSizeOf(context)?.height ?? double.infinity;
    final top = box.localToGlobal(Offset.zero).dy;
    if (top < viewportHeight + _margin && top + box.size.height > -_margin) {
      setState(() => _reached = true);
    }
  }

  @override
  Widget build(BuildContext context) => _reached ? widget.builder(context) : widget.placeholder;
}
