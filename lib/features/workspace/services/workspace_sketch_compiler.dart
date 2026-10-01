import 'package:pinbench_parts/models/board_profile.dart';
import 'package:pinbench_sim/core/sketch_compiler.dart';

import 'compiler_service.dart';

/// Binds the simulation engine's [SketchCompiler] port to this app's
/// `CompilerService`.
///
/// The two-method split lives here rather than in the port: whether a build
/// has a whole workspace directory or only a buffer of code is a workspace
/// question, and `CompilerService` already answers it in the way each platform
/// needs — a local `arduino-cli`, a remote compile service, or a template's
/// precompiled hex.
Future<String> workspaceSketchCompiler({
  String? workspacePath,
  required String code,
  required BoardProfile board,
}) => workspacePath != null
    ? CompilerService.compileWorkspace(workspacePath, board: board)
    : CompilerService.compile(code, board: board);
