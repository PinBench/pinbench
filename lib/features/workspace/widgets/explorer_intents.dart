import 'package:flutter/widgets.dart';

/// Keyboard/command [Intent]s for the file-explorer sidebar.
///
/// Kept separate from the view so the shortcut/action wiring is declared in one
/// place and the view file stays focused on rendering and state.

class DeleteNodeIntent extends Intent {
  const DeleteNodeIntent();
}

class RenameNodeIntent extends Intent {
  const RenameNodeIntent();
}

class NewFileIntent extends Intent {
  const NewFileIntent();
}

class NewFolderIntent extends Intent {
  const NewFolderIntent();
}
