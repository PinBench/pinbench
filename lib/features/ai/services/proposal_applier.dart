import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pinbench_parts/cdl/circuit_parser.dart';
import 'package:pinbench_ai/circuit_auto_layout.dart';
import 'package:pinbench_ai/models/file_proposal.dart';

import '../../../core/utils/logger.dart';
import '../../../core/parts/part_registry_provider.dart';
import '../../workspace/providers/workspace_files_provider.dart';
import '../../workspace/services/template_service.dart';

/// Writes an accepted [FileProposal] into the workspace.
///
/// Nothing here happens without the user pressing Apply — the model only ever
/// produces text. Applying a circuit re-renders the canvas for free, because
/// the file it writes is the same `.cdl` the canvas/code sync already watches.
class ProposalApplier {
  /// Creates an applier bound to [ref].
  const ProposalApplier(this.ref);

  static const _log = AppLogger('app.ai.apply');

  /// Riverpod handle used to reach the workspace and template services.
  final Ref ref;

  /// Applies [proposal] and returns the path written.
  ///
  /// Creates a blank workspace first if none is open, so the assistant works
  /// straight from the welcome screen instead of demanding the user go make a
  /// project before they can ask for one.
  Future<String> apply(FileProposal proposal) async {
    final files = ref.read(workspaceFilesProvider.notifier);
    if (ref.read(workspaceFilesProvider).workspacePath == null) {
      final path = await ref.read(templateServiceProvider).createBlankWorkspace();
      await files.openWorkspace(path, isTemporary: true);
    }

    final fileName = _targetFileName(proposal);
    final content = proposal.kind == ProposalKind.circuit
        ? await _laidOut(proposal.content)
        : proposal.content;
    final written = await files.writeWorkspaceFile(fileName, content);
    if (written == null) {
      throw StateError('No workspace is open to write $fileName into.');
    }
    return written;
  }

  /// Re-lays out a generated circuit before it is written.
  ///
  /// The model decides what connects to what; the app decides where things
  /// sit. Asking a language model for coordinates produces parts stranded far
  /// from the pins they wire to and, at worst, parts overlapping the board —
  /// which the netlist reads as terminals touching, i.e. a short circuit.
  ///
  /// Falls back to the model's own text if anything here fails: a circuit that
  /// renders badly still beats an Apply button that does nothing.
  Future<String> _laidOut(String cdl) async {
    try {
      final components = await ref.read(partRegistryProvider.future);
      final applied = CircuitParser.applyToCanvas(CircuitParser.parse(cdl), components);
      if (applied.nodes.isEmpty) return cdl;

      CircuitAutoLayout.arrange(applied.nodes, applied.wires);
      return CircuitParser.generate(applied.nodes, applied.wires);
    } catch (e) {
      _log.error('Could not lay out the generated circuit; writing it as-is', error: e);
      return cdl;
    }
  }

  /// Where [proposal] should land in the current workspace.
  ///
  /// The model's suggested name is only a fallback. What decides it is the
  /// workspace: a sketch overwrites the file that actually gets compiled, and
  /// for a new one the name is forced — `arduino-cli` requires the `.ino` to be
  /// named after its folder, so a free choice here produces a project that
  /// silently will not build.
  String _targetFileName(FileProposal proposal) {
    final state = ref.read(workspaceFilesProvider);
    final workspacePath = state.workspacePath;

    switch (proposal.kind) {
      case ProposalKind.circuit:
        final existing = state.mainCdlPath ?? _firstFileWithExtension('.cdl');
        return existing == null ? 'circuit.cdl' : p.basename(existing);

      case ProposalKind.sketch:
        final existing = state.mainInoPath ?? _firstFileWithExtension('.ino');
        if (existing != null) return p.basename(existing);
        return workspacePath == null ? 'sketch.ino' : '${p.basename(workspacePath)}.ino';
    }
  }

  /// The first workspace file with [extension], or null if there is none.
  /// Scanned in the explorer's (alphabetical) order, so the choice is stable
  /// across applies rather than depending on filesystem enumeration order.
  String? _firstFileWithExtension(String extension) {
    for (final file in ref.read(workspaceFilesProvider).files) {
      if (p.extension(file.path).toLowerCase() == extension) return file.path;
    }
    return null;
  }
}
