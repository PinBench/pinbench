import 'package:flutter/widgets.dart';

import 'package:pinbench_ui/ui/app_divider.dart';

class CanvasToolGroupDivider extends StatelessWidget {
  const CanvasToolGroupDivider({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(height: 24, child: AppDivider.toolbar());
}
