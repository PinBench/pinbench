import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/edition/edition_provider.dart';

/// The right-hand pane: whatever side panel the build's edition supplies.
///
/// Only ever built when there is one — the layout has no right-hand pane
/// otherwise (see `platController`).
class SidePanelView extends ConsumerWidget {
  const SidePanelView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(editionPanelProvider)?.build(context) ?? const SizedBox.shrink();
}
