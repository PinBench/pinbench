import 'package:flutter/foundation.dart' show kIsWeb;

/// What the current platform can actually do, so feature code asks "is X
/// possible" instead of branching on `kIsWeb` directly.
///
/// Scoped to checks that gate a real behavior/data difference (persistence,
/// filesystem access, compile backend). Purely visual `kIsWeb` checks (hiding
/// window chrome, showing a web-only banner, …) stay inline at their call
/// site — there's no reusable "capability" name for those, just a rendering
/// choice, so wrapping them here would rename `kIsWeb` without clarifying
/// anything.
abstract final class PlatformCapabilities {
  /// Whether the recent-workspaces list can be resolved against a local
  /// filesystem. False on web, which has no durable disk to check paths
  /// against.
  static bool get supportsRecentWorkspaces => !kIsWeb;

  /// Whether workspace files live on a real local filesystem (vs. the web's
  /// in-memory store), so directory-level operations like duplicating a
  /// workspace or zipping it via a native archiver are possible.
  static bool get supportsLocalFilesystem => !kIsWeb;

  /// Whether Arduino sketches are compiled by a local `arduino-cli`
  /// toolchain. False on web, which compiles custom sketches via a remote
  /// compile service instead (PinBench/compile-server) and falls back to
  /// bundled precompiled template hex files when none is configured.
  static bool get supportsLocalCompile => !kIsWeb;
}
