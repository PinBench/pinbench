import 'package:flutter/widgets.dart';

/// Keyboard/command [Intent]s for the file-explorer sidebar.
///
/// Kept separate from the view so the shortcut/action wiring is declared in one
/// place and the view file stays focused on rendering and state.

class const DeleteNodeIntent() extends Intent;

class const RenameNodeIntent() extends Intent;

class const NewFileIntent() extends Intent;

class const NewFolderIntent() extends Intent;
