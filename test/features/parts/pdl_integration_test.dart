import 'package:pinbench_parts/models/part_model.dart';
import 'package:pinbench_parts/painting/pdl_svg_cache.dart';
import 'package:pinbench_parts/part_registry.dart';
import 'package:pinbench/core/parts/part_registry_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The data-driven part path, exercised the way the *app* sees it.
///
/// `pinbench_parts` has its own tests for this, but they run in a context where the
/// asset manifest lists this package's files bare (`assets/parts/…`). An app
/// depending on the package sees them namespaced
/// (`packages/pinbench_parts/assets/parts/…`), and the registry originally matched
/// only one of those spellings — so it loaded nothing under `flutter test` in
/// the package, and would have loaded nothing in the app had the mismatch gone
/// the other way. Neither failure is loud: an empty catalog is not an error,
/// it is just a palette with fewer parts in it.
///
/// So this test exists specifically to pin the app-side spelling.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    PdlSvgCache.reset();
    await PartRegistry.initializeAsync();
  });

  test('the app finds the bundled .pdl parts, with no diagnostics', () {
    expect(PartRegistry.diagnostics, isEmpty, reason: PartRegistry.diagnostics.toString());
    expect(PartRegistry.getAllParts(), isNotEmpty);
  });

  test('a relative SVG path resolves to the package-namespaced asset key', () {
    final ldr = PartRegistry.getPart('ldr');
    expect(ldr, isNotNull, reason: 'the reference part should be in the catalog');
    expect(ldr!.visual.svgPath, 'packages/pinbench_parts/assets/parts/ldr/ldr.svg');
  });

  test('a declared CATEGORY reaches the palette', () async {
    // Every .pdl part landed in `other` until the provider carried this
    // through — silently, because a part in the wrong palette group still
    // works, it is just filed where nobody looks for it.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final parts = await container.read(partRegistryProvider.future);

    final ldr = parts.firstWhere((p) => p.definitionId == 'ldr');
    expect(ldr.category, PartCategory.sensors);

    final cell = parts.firstWhere((p) => p.definitionId == 'cr2032');
    expect(cell.category, PartCategory.basic);
  });

  test('that artwork actually decodes, at the size its viewBox declares', () async {
    final ldr = PartRegistry.getPart('ldr')!;
    final path = ldr.visual.svgPath!;

    // First ask returns null and starts the load — that is the contract the
    // painter relies on to draw something on frame one.
    expect(PdlSvgCache.artwork(path), isNull);

    for (var i = 0; i < 100 && PdlSvgCache.artwork(path) == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(PdlSvgCache.hasFailed(path), isFalse, reason: 'the SVG failed to decode');
    final art = PdlSvgCache.artwork(path);
    expect(art, isNotNull, reason: 'the SVG never finished decoding');
    expect(
      art!.size.width,
      76,
      reason: 'the painter scales the part footprint onto this intrinsic size',
    );
    expect(art.size.height, 38);
  });
}
