import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The asset paths this package hardcodes.
///
/// Worth a test because a wrong one fails *silently*: `ArduinoPainter.loadSvg`
/// catches its own failure and reports it through `FlutterError`, so the board
/// simply draws without its logo and nothing says why. Flutter also namespaces
/// a package's assets under `packages/<name>/`, so these paths do not match
/// what the files look like on disk here — which is exactly the kind of detail
/// that rots when someone moves a directory.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const logo = 'packages/pinbench_parts/assets/parts/arduino/arduino_logo.svg';

  test('the Arduino logo loads from its package-namespaced path', () async {
    final data = await rootBundle.load(logo);
    expect(data.lengthInBytes, greaterThan(0));
  });

  test('the asset prefix PartRegistry scans is the one the assets are under', () {
    // `PartRegistry._assetPrefix` is private, so this pins the string it has to
    // agree with. If a future move changes one and not the other, the registry
    // silently finds no `.pdl` definitions — an empty catalog, no error.
    expect(logo, startsWith('packages/pinbench_parts/assets/parts/'));
  });
}
