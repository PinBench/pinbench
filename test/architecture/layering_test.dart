import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The module map, enforced.
///
/// The map describes a stack — `core` (infrastructure), `parts` (the circuit
/// domain) and `shared` (the UI kit) at the bottom, `features` on top of
/// them, `layout`/`shell`/`app` as the chrome that arranges features — and
/// until this file existed nothing checked that the code agreed. It mostly
/// did, but the exceptions were the expensive kind: the simulation engine
/// could not name its own inputs without importing the canvas, and every part
/// painter pulled a "canvas widget" in for two geometry constants.
///
/// The point is not to be clean today. It is that a dependency, once added,
/// is invisible — nobody reviewing a one-line import sees that it welded two
/// features together. So each rule below carries an allowlist of what is
/// already wrong, and a matching test that fails when an allowance stops
/// being needed. The lists can only shrink. Deleting the last entry from one
/// turns that rule into a real boundary.
void main() {
  // ---------------------------------------------------------------------------
  // The layer model
  // ---------------------------------------------------------------------------

  /// The layer a `lib/` path belongs to. Each feature is its own layer, so
  /// `features/canvas` and `features/simulation` are as separate here as
  /// `core` and `shared` are.
  String layerOf(String path) {
    final parts = path.split('/');
    if (parts.length < 2 || parts.first != 'lib') return 'other';
    if (parts[1] == 'features') return parts.length > 2 ? 'features/${parts[2]}' : 'features';
    return parts[1];
  }

  /// The chrome: what arranges features into an app. Anything here may depend
  /// on a feature; the reverse is what this file is guarding against.
  const chrome = {'app', 'layout', 'shell'};

  bool isFeature(String layer) => layer.startsWith('features/');

  // ---------------------------------------------------------------------------
  // Reading the import graph
  // ---------------------------------------------------------------------------

  const packagePrefix = 'package:pinbench/';

  /// Matches the first URI of an `import`/`export`. A conditional directive
  /// (`import 'x_stub.dart' if (dart.library.io) 'x_io.dart';`) contributes
  /// only its default, which is fine — the alternatives are siblings of it.
  final directive = RegExp(r"^\s*(?:import|export)\s+'([^']+)'", multiLine: true);

  /// Resolves an import URI to a `lib/…` path, or null for anything outside
  /// this package (`dart:ui`, `package:flutter/…`).
  String? resolve(String fromFile, String uri) {
    if (uri.startsWith(packagePrefix)) return 'lib/${uri.substring(packagePrefix.length)}';
    if (uri.contains(':')) return null;

    final segments = [...fromFile.split('/')..removeLast(), ...uri.split('/')];
    final stack = <String>[];
    for (final segment in segments) {
      if (segment == '.' || segment.isEmpty) continue;
      if (segment == '..') {
        if (stack.isNotEmpty) stack.removeLast();
      } else {
        stack.add(segment);
      }
    }
    return stack.join('/');
  }

  /// Every internal dependency in `lib/`, as (importing file, imported file)
  /// with both sides normalised to `lib/…`.
  final edges = <(String from, String to)>[];
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.path.replaceAll(r'\', '/'))
      .toList();

  for (final file in libFiles) {
    for (final match in directive.allMatches(File(file).readAsStringSync())) {
      final target = resolve(file, match.group(1)!);
      if (target != null) edges.add((file, target));
    }
  }

  setUpAll(() {
    // A resolver that silently produced nothing would make every rule below
    // pass for the wrong reason.
    expect(edges, isNotEmpty, reason: 'no imports parsed out of lib/ — the resolver is broken');
  });

  /// Runs one rule: collects the offending edges, drops the ones an allowlist
  /// forgives, and reports both what is newly wrong and what the allowlist no
  /// longer needs to forgive.
  void enforce({
    required String rule,
    required bool Function(String from, String to) violates,
    required String Function(String from, String to) key,
    required Set<String> allowed,
    required String fix,
  }) {
    final violations = <String>{};
    for (final (from, to) in edges) {
      if (violates(from, to)) violations.add(key(from, to));
    }

    final fresh = violations.difference(allowed)..toList().sort();
    expect(
      fresh,
      isEmpty,
      reason:
          'New violations of "$rule":\n'
          '${(fresh.toList()..sort()).map((v) => '  $v').join('\n')}\n\n$fix\n\n'
          'If the dependency is genuinely the right call, add it to the '
          'allowlist in this file with a comment saying why.',
    );

    final stale = allowed.difference(violations);
    expect(
      stale,
      isEmpty,
      reason:
          'These entries in the "$rule" allowlist are no longer violated:\n'
          '${(stale.toList()..sort()).map((v) => '  $v').join('\n')}\n\n'
          'Delete them. The list is a ratchet — leaving a spent entry in it '
          'quietly re-opens the door someone just closed.',
    );
  }

  // ---------------------------------------------------------------------------
  // The rules
  // ---------------------------------------------------------------------------

  /// Four of this file's rules have been retired this way, not relaxed: the
  /// circuit domain, the `.cdl` format, the simulation engine and the UI kit
  /// were each a directory in `lib/` with a rule guarding it, and are each now
  /// a package the compiler guards instead — a package simply cannot import
  /// the app that depends on it. `shared/ depends on no feature and no chrome`
  /// was the last of them to go; there is no `lib/shared/` to check.
  ///
  /// A rule whose subject moves out has to be deleted rather than left in
  /// place, or it keeps passing while checking nothing.
  ///
  /// What is *not* compiler-enforced is someone adding the app back as a
  /// dependency of the package to get at one convenient thing, at which point
  /// the extraction is undone and nothing fails. That is what this checks.
  ///
  /// The other half of the boundary — painters belong to the domain, not to
  /// the UI — is recorded in that package's README: `PortProvider` is a
  /// painter mixin, so a painter is where a part's pin geometry is defined,
  /// and `CircuitNetlist.build` asks the painter where the ports are, inside
  /// the simulation isolate. Splitting them would leave the simulation unable
  /// to find a component's pins.
  test('the packages do not depend on the app', () {
    final offenders = <String>[];

    for (final package in const [
      'pinbench_parts',
      'pinbench_pdl',
      'pinbench_cdl',
      'pinbench_sim',
      'pinbench_ai',
      'pinbench_ui',
      'pinbench_terminal',
      'pinbench_cloud',
      'pinbench_pro',
    ]) {
      final files = Directory(
        'packages/$package/lib',
      ).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

      for (final file in files) {
        if (file.readAsStringSync().contains(packagePrefix)) {
          offenders.add('${file.path.replaceAll(r'\', '/')} imports the app');
        }
      }

      // A dependency key, not a substring: every package's own name and its
      // sibling dependencies start with `pinbench_`.
      if (RegExp(
        r'^\s+pinbench:',
        multiLine: true,
      ).hasMatch(File('packages/$package/pubspec.yaml').readAsStringSync())) {
        offenders.add('packages/$package/pubspec.yaml depends on the app');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '${offenders.join('\n')}\n\n'
          'These are the pieces of this codebase that stand alone. If one needs '
          'something from the app, either it belongs in the package or the '
          'caller should pass it in.',
    );
  });

  /// The two file formats are packages of their own so that something other
  /// than this app — a VS Code extension, a linter, a command-line converter —
  /// can read and write `.pdl` and `.cdl` exactly as the app does. That only
  /// holds while they are plain Dart: one Flutter import, or one dependency on
  /// a package that has them, and they can no longer be used outside a
  /// Flutter app.
  test('the file-format packages are pure Dart', () {
    final offenders = <String>[];

    for (final package in const ['pinbench_pdl', 'pinbench_cdl']) {
      final files = Directory(
        'packages/$package/lib',
      ).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

      for (final file in files) {
        final source = file.readAsStringSync();
        for (final banned in ['package:flutter/', 'dart:ui', 'package:pinbench']) {
          final ownPackage = 'package:$package/';
          final hits = RegExp(
            "import '${RegExp.escape(banned)}[^']*'",
          ).allMatches(source).where((m) => !m.group(0)!.contains(ownPackage));
          for (final hit in hits) {
            offenders.add('${file.path.replaceAll(r'\', '/')}: ${hit.group(0)}');
          }
        }
      }

      final pubspec = File('packages/$package/pubspec.yaml').readAsStringSync();
      final deps = pubspec.substring(
        pubspec.indexOf('dependencies:'),
        pubspec.contains('dev_dependencies:') ? pubspec.indexOf('dev_dependencies:') : null,
      );
      if (RegExp(r'^\s+(flutter|pinbench\w*):', multiLine: true).hasMatch(deps)) {
        offenders.add(
          'packages/$package/pubspec.yaml depends on Flutter or another package of ours',
        );
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '${offenders.join('\n')}\n\n'
          'Keep the format packages free of Flutter and of the rest of the app. '
          'Anything that needs a Color, an Offset or a placed part belongs in '
          'pinbench_parts (pdl_flutter.dart, lib/cdl/).',
    );
  });

  /// `core/` is infrastructure: auth, cloud repositories, telemetry,
  /// platform capabilities. Three files break that, each for its own reason,
  /// and each is worth fixing separately.
  test('core/ depends on no feature and no chrome', () {
    enforce(
      rule: 'core/ depends on no feature and no chrome',
      violates: (from, to) {
        final target = layerOf(to);
        return layerOf(from) == 'core' && (isFeature(target) || chrome.contains(target));
      },
      key: (from, _) => from,
      allowed: const {
        // The router used to be here: routes name the pages they route to, so
        // one in core/ pulled in both the chrome and the workspace providers
        // its redirects read. It is `app/router.dart` now, which is where the
        // pages are — and every caller was already chrome.

        // Watches editor and simulation state to emit spans. Inverting it —
        // features handing their events to a telemetry sink — is the right
        // shape, and is why nothing else in core/ knows a feature exists.
        'lib/core/telemetry/telemetry_listener.dart',
      },
      fix:
          'core/ is infrastructure. Invert the dependency (let the feature '
          'register with core) or move the file into the feature it serves.',
    );
  });

  /// Features are arranged *by* the chrome, so they should not reach back up
  /// into it. Every current exception is the same one: a feature widget
  /// opening a pane or a tab by driving `AppLayoutController` directly.
  test('features do not reach up into the chrome', () {
    enforce(
      rule: 'features do not reach up into the chrome',
      violates: (from, to) => isFeature(layerOf(from)) && chrome.contains(layerOf(to)),
      key: (from, to) => '$from -> $to',
      // Empty, and it is the second rule in this file to get there.
      //
      // Six entries were the same thing: a feature reading
      // `appLayoutControllerProvider` to open, close or focus a tab, or to
      // reveal a pane. `ChromeCommands` in `core/chrome/` is the surface they
      // were asking for, bound in `app/chrome_bindings.dart`.
      //
      // The seventh was an editor tab drawing itself with `ChromeTab`, and the
      // comment here used to excuse it as "presentation with no layout state
      // in it". That was wrong — `ChromeTab` reads the layout controller and
      // the problem count. What was actually misplaced was `editor_tab_item`
      // itself: a tab in the chrome's tab strip, placed only by `layout.dart`,
      // filed under a feature. It lives in `layout/components/` now, beside
      // the tab it draws with.
      allowed: const {},
      fix:
          'Have the chrome place the widget (see layout/leaf_registry.dart) or '
          'pass a callback down, rather than the feature commanding the layout.',
    );
  });

  /// Direction-level, not file-level: the risk being managed is a *new* pair
  /// of features becoming entangled, not one more import along a pair that
  /// is already entangled.
  ///
  /// Read an entry as "this feature is allowed to know that one exists". The
  /// list is directional — `workspace -> canvas` does not license
  /// `canvas -> workspace`, which is what keeps a one-way dependency from
  /// quietly becoming a cycle.
  test('cross-feature dependencies stay on the allowlist', () {
    enforce(
      rule: 'cross-feature dependencies stay on the allowlist',
      violates: (from, to) {
        final source = layerOf(from);
        final target = layerOf(to);
        return isFeature(source) && isFeature(target) && source != target;
      },
      key: (from, to) => '${layerOf(from).split('/')[1]} -> ${layerOf(to).split('/')[1]}',
      allowed: const {
        // The assistant reads the workspace to build its context. Writing
        // proposals back used to be listed here too, until the `.cdl` parser
        // became `package:pinbench_cdl` and the auto-layout — which is about
        // *assistant output*, not about the format — moved in beside its
        // only caller.
        'ai -> workspace',

        // Canvas widgets that read run state — the toolbar's play/stop, the
        // read-only lock while simulating, live values in the properties
        // panel. Placing them from the chrome would remove this edge.
        'canvas -> simulation',

        // `simulation -> canvas` and `simulation -> workspace` used to be here.
        // They are gone: the simulation now names three ports of its own —
        // `SimulationCanvas`, `SimulationSketch`, `SimulationDiagnostics` — and
        // `lib/app/simulation/` binds them to the features that implement
        // them. Note the direction that survived: `canvas -> simulation`,
        // which is a widget reading run state, is the cheap one to keep.

        // Editor tabs are workspace files.
        //
        // `editor -> canvas` used to sit beside this, for "the code editor
        // forwards canvas intents so a shortcut works with focus in the
        // editor". The intents were never the canvas's: `SaveIntent` is what
        // Cmd-S means in a text buffer, and the file declaring it had a section
        // headed "App-chrome intents" in it. They are
        // `core/shortcuts/app_intents.dart` now.
        'editor -> workspace',

        // `workspace -> canvas` and `canvas -> workspace` used to sit here —
        // between them, the last cycle between any two features in this app.
        // Both are gone. The `.cdl` sync names a `SyncableCanvas` and the
        // canvas implements it without knowing; "which circuit is on screen"
        // moved out of the sync service to `core/chrome/active_circuit_file`,
        // which is what the canvas toolbar's View Code button had been
        // reaching across a feature boundary to ask for.
        //
        // What is left below is a spanning tree, not a graph: three edges,
        // no two of them pointing back at each other.
      },
      fix:
          'Two features that need the same vocabulary usually want it in '
          'parts/models/; two that need to talk usually want the chrome or a '
          'provider to mediate.',
    );
  });
}
