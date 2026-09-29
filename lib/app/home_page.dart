import 'package:flutter/widgets.dart';

import '../layout/layout.dart';
import '../shell/shortcuts/app_shortcuts.dart';

class const HomePage({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const AppShortcuts(child: Layout());
}
