import 'package:flutter/widgets.dart';

import '../theme/text.dart';
import '../theme/tokens.dart';

class SidebarScaffold extends StatelessWidget {
  final String title;
  final Widget? toolbar;
  final Widget child;

  const SidebarScaffold({super.key, required this.title, this.toolbar, required this.child});

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
