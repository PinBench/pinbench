import 'package:flutter/widgets.dart';

import '../layout/layout.dart';
import '../shell/shortcuts/app_shortcuts.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => const AppShortcuts(child: Layout());
}
