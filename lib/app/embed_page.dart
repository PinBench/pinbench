import 'package:flutter/widgets.dart';

import 'package:pinbench_ui/ui/app_scaffold.dart';

import '../layout/views/embed_view.dart';

/// Root of the `?embed=1` render: the canvas and a Run button, nothing else.
///
/// Deliberately not wrapped in `AppShortcuts` the way the main page is. An embed
/// sits inside somebody else’s page, and a Flutter view that swallows Ctrl-F
/// or Cmd-S because it happens to hold focus is a genuinely hostile thing to
/// put in an article.
class const EmbedPage({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const AppScaffold(child: EmbedView());
}
