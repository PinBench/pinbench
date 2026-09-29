import 'package:flutter/widgets.dart';

import '../theme/text.dart';
import '../theme/tokens.dart';

class const SidebarScaffold({
  super.key,
  required final String title,
  final Widget? toolbar,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(child: Text(title, style: AppTextStyles.largePrimary(context))),
            ?toolbar,
          ],
        ),
      ),
      Expanded(child: child),
    ],
  );
}
