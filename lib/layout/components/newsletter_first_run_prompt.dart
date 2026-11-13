import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_sim/models/simulation_state.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/ui/app_toast.dart';

import '../../core/newsletter/newsletter.dart';
import '../../features/simulation/providers/simulation_provider.dart';

/// Offers the newsletter once, the first time a simulation starts running.
///
/// That is the moment the app has just done what it promised, which makes it
/// the one time asking is more likely welcome than in the way. A toast rather
/// than a dialog, so the run it interrupts keeps going, and it goes away on its
/// own. Renders nothing; it is mounted once in the layout for its context,
/// which is below the toaster.
class const NewsletterFirstRunPrompt({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(simulationProvider, (previous, next) {
      // Resuming from a pause is not a run starting.
      if (next != SimulationState.running || previous == SimulationState.paused) return;
      final controller = ref.read(newsletterPromptsProvider.notifier);
      if (!controller.claimFirstRunPrompt()) return;
      showAppToast(
        context,
        title: AppStrings.newsletterFirstRunTitle,
        message: AppStrings.newsletterFirstRunBody,
        action: ToastAction(
          label: AppStrings.newsletterSignUp,
          onPressed: () => unawaited(controller.open(NewsletterEntry.firstRun)),
        ),
      );
    });
    return const SizedBox.shrink();
  }
}
