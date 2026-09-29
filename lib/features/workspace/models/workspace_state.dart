import 'dart:io';

class const WorkspaceState({
  final String? workspacePath,
  final List<FileSystemEntity> files = const [],
  final String? activeFilePath,
  final bool isTemporary = false,

  /// The cloud project this workspace is linked to, or `null` if it's purely
  /// local. When set, saves also push each changed file to the backend
  /// and remote changes are pulled in live.
  ///
  /// Deliberately `null` when [viewingSharedProjectId] is set — a viewer has no
  /// live link, so nothing can be pushed.
  final String? cloudProjectId,

  /// The cloud project this workspace is a **read-only copy of**, set
  /// when someone opens a share link for a project they cannot edit.
  ///
  /// The files are on local disk and freely editable — that is the point, so a
  /// visitor can poke at the circuit and then save it as their own. What they
  /// cannot do is write back to the original, and that is enforced by there
  /// being no cloud link at all rather than by hiding a button:
  /// [cloudProjectId] stays null, so no save path reaches the cloud. The
  /// security rules reject such a write independently.
  final String? viewingSharedProjectId,

  /// Display name of the shared project, for the "you are viewing X" banner.
  final String? viewingSharedProjectName,

  /// Path of the `.ino` sketch to compile/simulate. When null, the first open
  /// `.ino` is used. Lets a multi-sketch workspace pick which one runs.
  final String? mainInoPath,

  /// Path of the `.cdl` circuit to drive the simulation canvas. When null, the
  /// active circuit tab is used.
  final String? mainCdlPath,

  /// Path of a user-supplied precompiled `.hex`. When set, runs load this HEX
  /// directly and skip the arduino-cli / remote compile step entirely.
  final String? precompiledHexPath,

  /// In-memory contents of that hex, read once when it is picked rather than
  /// re-read per run — the file may be anywhere on disk, or nowhere at all on
  /// the web. Always set and cleared with [precompiledHexPath].
  final String? precompiledHexContent,
}) {
  /// Whether this workspace is a read-only view of someone else's project.
  bool get isViewingShared => viewingSharedProjectId != null;

  WorkspaceState copyWith({
    bool? isTemporary,
    String? workspacePath,
    String? activeFilePath,
    List<FileSystemEntity>? files,
    String? cloudProjectId,
    bool clearCloudProjectId = false,
    String? viewingSharedProjectId,
    String? viewingSharedProjectName,
    bool clearViewingShared = false,
    String? mainInoPath,
    bool clearMainInoPath = false,
    String? mainCdlPath,
    bool clearMainCdlPath = false,
    String? precompiledHexPath,
    String? precompiledHexContent,
    bool clearPrecompiledHexPath = false,
  }) => WorkspaceState(
    files: files ?? this.files,
    isTemporary: isTemporary ?? this.isTemporary,
    workspacePath: workspacePath ?? this.workspacePath,
    activeFilePath: activeFilePath ?? this.activeFilePath,
    cloudProjectId: clearCloudProjectId ? null : (cloudProjectId ?? this.cloudProjectId),
    viewingSharedProjectId: clearViewingShared
        ? null
        : (viewingSharedProjectId ?? this.viewingSharedProjectId),
    viewingSharedProjectName: clearViewingShared
        ? null
        : (viewingSharedProjectName ?? this.viewingSharedProjectName),
    mainInoPath: clearMainInoPath ? null : (mainInoPath ?? this.mainInoPath),
    mainCdlPath: clearMainCdlPath ? null : (mainCdlPath ?? this.mainCdlPath),
    precompiledHexPath: clearPrecompiledHexPath
        ? null
        : (precompiledHexPath ?? this.precompiledHexPath),
    precompiledHexContent: clearPrecompiledHexPath
        ? null
        : (precompiledHexContent ?? this.precompiledHexContent),
  );
}
