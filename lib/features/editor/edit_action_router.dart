import 'package:flutter/widgets.dart';

import 'package:re_editor/re_editor.dart';

import 'widgets/custom_code_editor.dart';

/// Which surface an Edit action should act on.
enum EditSurface { textField, codeEditor, canvas }

/// Tracks which editable surface the user last focused and routes Edit-menu
/// actions (undo/redo, cut/copy/paste, select-all) to it.
///
/// Both the native [PlatformMenuBar] Edit menu (`shell/menus/edit_menu.dart`)
/// and the web in-app menu (`layout/bars/title/web_menu_bar.dart`) share this so
/// clipboard/history actions work everywhere the user can edit — plain text
/// fields, the re_editor code editor, and the canvas.
///
/// The re_editor code editor drops focus the moment a menu is clicked (plain
/// text fields and the canvas keep theirs), so reading focus at click time is
/// unreliable. Instead we remember the surface on every focus change and ignore
/// focus moving to the menu, which keeps this pointing at the real target.
class EditActionRouter {
  EditSurface? _surface;
  FocusNode? _textFieldFocus;
  CodeLineEditingController? _codeController;

  /// Begin listening for focus changes. Call once from the owner's `initState`.
  void startTracking() {
    FocusManager.instance.addListener(_onFocusChange);
  }

  /// Stop listening. Call from the owner's `dispose`.
  void stopTracking() {
    FocusManager.instance.removeListener(_onFocusChange);
  }

  void _onFocusChange() {
    final focus = FocusManager.instance.primaryFocus;
    final context = focus?.context;
    if (context == null) return; // Focus lost to the menu: keep the last surface.
    final codeEditor = context.findAncestorWidgetOfExactType<CustomCodeEditor>();
    if (context.findAncestorStateOfType<EditableTextState>() != null) {
      _surface = EditSurface.textField;
      _textFieldFocus = focus;
    } else if (codeEditor != null) {
      // Grab the focused editor's controller now; by the time a menu item runs
      // the editor has lost focus, so we can no longer resolve it from context.
      _surface = EditSurface.codeEditor;
      _codeController = codeEditor.controller;
    } else if (focus?.debugLabel == 'CanvasFocusNode') {
      _surface = EditSurface.canvas;
    }
    // Any other focus (menu buttons, misc widgets) leaves the surface unchanged.
  }

  /// Dispatches an Edit action to the surface the user was last editing: a plain
  /// [EditableText] field (via [textIntent]), the re_editor code editor (via
  /// [codeAction] on its active controller), or the canvas ([canvasFallback]).
  void route({
    Intent? textIntent,
    void Function(CodeLineEditingController controller)? codeAction,
    VoidCallback? canvasFallback,
  }) {
    switch (_surface) {
      case EditSurface.textField:
        final context = _textFieldFocus?.context;
        if (textIntent != null && context != null && context.mounted) {
          Actions.maybeInvoke(context, textIntent);
        }
      case EditSurface.codeEditor:
        final controller = _codeController;
        if (codeAction != null && controller != null) codeAction(controller);
      case EditSurface.canvas:
      case null:
        canvasFallback?.call();
    }
  }
}
