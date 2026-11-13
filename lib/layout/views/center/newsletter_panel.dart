import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/strings.dart';
import 'package:pinbench_ui/theme/text.dart';
import 'package:pinbench_ui/theme/tokens.dart';
import 'package:pinbench_ui/ui/app_button.dart';

import '../../../core/newsletter/newsletter.dart';

/// Settings' way to the newsletter, there for good — unlike the welcome card
/// and the first-run toast, which stop asking once answered.
class const NewsletterPanel({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(AppStrings.newsletterBody, style: AppTextStyles.smallMuted(context)),
      Gap.vMd,
      AppButton(
        size: AppButtonSize.sm,
        onPressed: () =>
            unawaited(ref.read(newsletterPromptsProvider.notifier).open(NewsletterEntry.settings)),
        child: const Text(AppStrings.newsletterSignUp),
      ),
    ],
  );
}
