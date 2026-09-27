import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_loading_provider.g.dart';

/// True while a workspace is being opened (template, folder, or cloud project).
///
/// Opening pulls in the component registry, parses the `.cdl`, and builds the
/// canvas — enough synchronous+async work that the UI can appear frozen. The
/// layout watches this to overlay a themed spinner over the editor/canvas area
/// so a template click reads as "loading" instead of "hung".
// Kept alive because the things that drive it are: the `WorkspaceFiles` notifier, which is keep-alive.
// A `@Riverpod(keepAlive: true)` provider reading an autoDispose one pins it
// through a `KeepAliveLink` anyway, so this is what already happens at
// runtime — saying it out loud is what `only_use_keep_alive_inside_keep_alive`
// asks for, and it stops the lifetime depending on who happens to be watching.
@Riverpod(keepAlive: true)
class WorkspaceLoading extends _$WorkspaceLoading {
  // Depth-counted so nested opens (e.g. openCloudProject -> openWorkspace) don't
  // clear the spinner when the inner call finishes while the outer is still
  // running. Loading is "on" whenever depth > 0.
  var _depth = 0;

  @override
  bool build() => false;

  void begin() {
    _depth++;
    if (!state) state = true;
  }

  void end() {
    if (_depth > 0) _depth--;
    final loading = _depth > 0;
    if (state != loading) state = loading;
  }

  /// Forcibly clears the depth counter and hides the overlay. Safety net for
  /// navigating away (e.g. back to the welcome screen) while an open is
  /// still in flight or got stuck on an unhandled error — without this, a
  /// mismatched begin()/end() pair would leave the spinner showing forever
  /// with no way for the user to dismiss it.
  void reset() {
    _depth = 0;
    if (state) state = false;
  }
}
