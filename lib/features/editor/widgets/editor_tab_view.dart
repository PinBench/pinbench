import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinbench_ui/theme/app_colors.dart';

import 'custom_code_editor.dart';
import 'empty_editor_view.dart';
import '../../workspace/providers/editor_state_provider.dart';

class EditorTabView extends ConsumerWidget {
  final String filePath;
  const EditorTabView({super.key, required this.filePath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorState = ref.watch(editorStateControllerProvider);
    final activeController = editorState.getActiveController(filePath);

    if (filePath.isEmpty || activeController == null) {
      return ColoredBox(color: context.appColors.background, child: const EmptyEditorView());
    }

    return CustomCodeEditor(controller: activeController, filePath: filePath);
  }
}
