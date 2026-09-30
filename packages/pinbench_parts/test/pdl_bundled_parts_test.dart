import 'package:pinbench_pdl/pinbench_pdl.dart';
import 'package:pinbench_parts/pdl_flutter.dart';

import 'dart:ui' as ui;

import 'package:pinbench_parts/painting/dsl_component_painter.dart';
import 'package:pinbench_parts/painting/grid_system.dart';
import 'package:pinbench_parts/painting/part_painter_registry.dart';
import 'package:pinbench_parts/painting/pdl_svg_cache.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every `.pdl` file this package ships, loaded the way the app loads it.
///
/// The parser tests use string literals; this one uses the real asset bundle,
/// which is the only way to catch the failures that actually bite: an asset
/// directory nobody declared in `pubspec.yaml`, an `SVG` path that resolves to
/// nothing, a pin nudged off the lattice during an artwork tweak. All three
/// are silent at runtime — a part simply does not appear, or appears and
/// cannot be wired.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    PdlSvgCache.reset();
    await PartRegistry.initializeAsync();
  });

  test('every bundled definition loads without a single diagnostic', () {
    expect(
      PartRegistry.diagnostics,
      isEmpty,
      reason:
          'A bundled part must be clean:\n'
          '${PartRegistry.diagnostics.entries.map((e) => '${e.key}\n  ${e.value.join('\n  ')}').join('\n')}',
    );
  });

  test('the catalog is not empty — the registry used to load nothing at all', () {
    // For most of this project's life `assets/parts/` held no .pdl files, so
    // PartRegistry was empty, every definitionId was null, and the whole
    // data-driven path was dead code that looked alive.
    expect(PartRegistry.getAllParts(), isNotEmpty);
  });

  group('for each bundled part', () {
    late List<PartDefinition> parts;

    setUpAll(() => parts = PartRegistry.getAllParts());

    test('ids are unique and stable-looking', () {
      final ids = parts.map((p) => p.id).toList();
      expect(ids.toSet(), hasLength(ids.length), reason: 'duplicate part id');
      for (final id in ids) {
        expect(id, matches(RegExp(r'^[a-z0-9_]+$')), reason: '"$id" should be a lower_snake id');
      }
    });

    test('every pin sits on the connection lattice', () {
      // The same rule grid_alignment_test.dart enforces for hand-written
      // painters. A part that fails this looks perfect and cannot be plugged
      // into a breadboard.
      bool onLattice(double v) =>
          ((v - GridSystem.cellCenter) / GridSystem.pitch -
                  ((v - GridSystem.cellCenter) / GridSystem.pitch).round())
              .abs() <
          0.001;

      for (final part in parts) {
        for (final pin in part.pins) {
          expect(
            onLattice(pin.localOffset.dx) && onLattice(pin.localOffset.dy),
            isTrue,
            reason: '${part.id}.${pin.id} at ${pin.localOffset} is off the lattice',
          );
        }
      }
    });

    test('every pin lies inside the part footprint', () {
      for (final part in parts) {
        for (final pin in part.pins) {
          expect(
            pin.localOffset.dx >= 0 &&
                pin.localOffset.dx <= part.visual.width &&
                pin.localOffset.dy >= 0 &&
                pin.localOffset.dy <= part.visual.height,
            isTrue,
            reason:
                '${part.id}.${pin.id} at ${pin.localOffset} is outside its '
                '${part.visual.width}x${part.visual.height} body',
          );
        }
      }
    });

    test('declared artwork actually loads', () async {
      for (final part in parts) {
        final path = part.visual.svgPath;
        if (path == null) continue;
        await expectLater(
          rootBundle.load(path),
          completes,
          reason: '${part.id} names artwork "$path" that is not in the bundle',
        );
      }
    });

    test('a named PAINTER is registered, and draws in the declared SIZE', () {
      // An unregistered name is not fatal at runtime — the part still loads
      // and draws its VISUALS — so this is where a typo gets caught.
      for (final part in parts) {
        final name = part.visual.painter;
        if (name == null) continue;
        final builder = PartPainterRegistry.find(name);
        expect(
          builder,
          isNotNull,
          reason: '${part.id} names PAINTER "$name", which nothing registers',
        );

        // A painted body smaller than the footprint says where it is, so the
        // part is hit on its body rather than across its whole bounds.
        final body = builder!().bodyRect(part.visual.size);
        if (body != null) {
          // SIZE in millimetres converts to a hair off whole pixels.
          final bounds = (ui.Offset.zero & part.visual.size).inflate(0.01);
          expect(
            bounds.contains(body.topLeft) && bounds.contains(body.bottomRight),
            isTrue,
            reason: "${part.id}: the painter's body $body spills outside SIZE",
          );
        }
      }
    });

    test('behaviour rules evaluate against declared state and properties', () {
      // Catches a rule that reads `prop.typo` and silently yields 0 forever.
      for (final part in parts) {
        final context = PdlEvalContextForPart(part);
        for (final rule in part.behavior) {
          final value = rule.expression.evaluate(context.context);
          expect(value, isNotNull, reason: '${part.id}: "${rule.source}" evaluated to null');
          if (value is num) {
            expect(value.isFinite, isTrue, reason: '${part.id}: "${rule.source}" produced $value');
          }
        }
      }
    });
  });

  test('a bundled part paints without throwing, artwork loaded or not', () async {
    // The painter must survive being asked to draw before its SVG has decoded
    // — which is what happens on the very first frame of every part.
    for (final part in PartRegistry.getAllParts()) {
      final painter = DSLComponentPainter(definition: part, properties: part.defaultProperties());
      final recorder = ui.PictureRecorder();
      painter.paintComponent(ui.Canvas(recorder), part.visual.size);
      recorder.endRecording().dispose();
    }
  });
}

/// Small helper so the behaviour test reads as one line per part.
class PdlEvalContextForPart(final PartDefinition part) {
  PdlEvalContext get context =>
      PdlEvalContext.static(state: part.initialState(), properties: part.defaultProperties());
}
