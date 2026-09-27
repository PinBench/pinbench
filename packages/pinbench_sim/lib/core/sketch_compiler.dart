/// Turns a sketch into the Intel HEX image the emulator runs.
///
/// A port, so the engine does not have to know *how* a sketch is built. That
/// answer is genuinely host-specific and platform-dependent: native builds run
/// a local `arduino-cli`, the web posts to a remote compile service, and when
/// neither is available it falls back to a template's precompiled hex. None of
/// that is the emulator's business — it needs bytes.
///
/// Builds [workspacePath] if given — a whole sketch directory, so multi-file
/// projects and libraries work — otherwise builds the single-file `code`.
///
/// Throws on failure. The exception's message is shown to the user verbatim in
/// the Problems pane, so it should read as a compiler error rather than a
/// stack trace.
///
/// A function rather than an interface: there is no state to hold, and the one
/// implementation (`workspaceSketchCompiler`) is a two-line delegation.
typedef SketchCompiler = Future<String> Function({String? workspacePath, required String code});
