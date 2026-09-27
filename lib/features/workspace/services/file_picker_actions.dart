import 'package:file_selector/file_selector.dart';
import 'package:pinbench_ui/strings.dart';

import '../providers/workspace_files_provider.dart';

/// Shared file-picker command bodies used by both the native `PlatformMenuBar`
/// (`shell/menus/…`) and the in-app web menu bar (`WebMenuBar`). Keeping the
/// picker configuration and the follow-up workspace call in one place stops the
/// two menu surfaces from drifting (e.g. accepting different file extensions).

const _sketchTypeGroups = [
  XTypeGroup(
    label: AppStrings.sketchesFileTypeGroupLabel,
    extensions: ['ino', 'cdl', 'pdl', 'txt'],
  ),
];

const _zipTypeGroups = [
  XTypeGroup(label: AppStrings.zipFileTypeGroupLabel, extensions: ['zip']),
];

/// Prompts for a sketch/circuit file and opens it into [files], if one is
/// chosen.
Future<void> pickAndOpenFile(WorkspaceFiles files) async {
  final file = await openFile(acceptedTypeGroups: _sketchTypeGroups);
  if (file != null) await files.openSingleFile(file.path);
}

/// Prompts for a destination and exports the current workspace of [files] as a
/// zip archive, if a location is chosen.
Future<void> pickAndExportWorkspaceZip(WorkspaceFiles files) async {
  final location = await getSaveLocation(
    suggestedName: 'workspace.zip',
    acceptedTypeGroups: _zipTypeGroups,
  );
  if (location != null) await files.exportWorkspaceToZip(location.path);
}
