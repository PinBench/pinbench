import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/app_icons.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_icon_button.dart';

import '../../core/updates/update_providers.dart';
import '../../core/updates/update_status.dart';
import 'update_dialog.dart';

/// A title-bar button that exists only while there is an update to take.
///
/// This is how the launch-time check reaches the user. A modal at startup
/// would interrupt someone who opened the app to look at a circuit, and a
/// toast would be gone before they looked up — a button that quietly appears
/// and stays until it is dealt with is the shape that fits both.
class UpdateBadgeButton extends ConsumerWidget {
  const UpdateBadgeButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(updateControllerProvider);
    if (status is! UpdateAvailable) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconButton(
          icon: AppIcons.update,
          tooltip: AppStrings.updatesAvailable(status.version?.toString()),
          onPressed: () => unawaited(showUpdateDialog(context, ref)),
        ),
        Gap.hMd,
      ],
    );
  }
}
