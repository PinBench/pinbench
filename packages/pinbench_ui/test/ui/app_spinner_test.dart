import 'dart:convert';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_ui/ui/app_spinner.dart';
import 'package:pinbench_ui/ui/app_icon_button.dart';
import 'package:pinbench_ui/theme/app_icons.dart';
import 'package:pinbench_ui/theme/testing.dart';

/// The spinner has to *spin* — turn about its own centre — and it did not.
///
/// forui's `FCircularProgress` rotates the loader glyph about the centre of
/// its layout box. The glyph is centred in that box only at its natural size:
/// squeeze the box smaller and the ink lands low and to the right, so the
/// rotation swings it around a point it is not centred on. That is a wobble,
/// not a spin, and it shipped — in an icon button whose spinner sat inside a
/// padding, which is exactly the squeeze that causes it.
///
/// Nothing about that is visible to a finder: both the wobbling and the
/// correct spinner have the same widget tree, the same size, and the same
/// centre. So this renders the thing and measures the pixels.
void main() {
  setUpAll(loadLucide);

  /// The centre of the circle the arc lies on.
  ///
  /// Not the ink's bounding box or its centroid: the glyph is an *open* arc,
  /// so both of those legitimately move as it turns even when the spin is
  /// perfect. The circle underneath it does not — that is the invariant.
  Future<Offset> arcCentre(WidgetTester tester, Finder target) async {
    final image = await captureInk(tester, target);
    final points = <Offset>[];
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (image.lit(x, y)) points.add(Offset(x.toDouble(), y.toDouble()));
      }
    }
    expect(points.length, greaterThan(50), reason: 'the spinner should have drawn something');
    return fitCircle(points);
  }

  /// Samples a full turn and reports how far the fitted centre drifts.
  Future<double> orbitRadius(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(appTestApp(Center(child: child)));
    final target = find.byType(AppSpinner);

    final centres = <Offset>[];
    for (var step = 0; step < 8; step++) {
      centres.add(await arcCentre(tester, target));
      // An eighth of forui's one-second turn.
      await tester.pump(const Duration(milliseconds: 125));
    }

    final mean = centres.reduce((a, b) => a + b) / centres.length.toDouble();
    return centres.map((c) => (c - mean).distance).reduce((a, b) => a > b ? a : b);
  }

  testWidgets('spins about its own centre rather than orbiting', (tester) async {
    // 1 logical pixel of drift over a full turn. The bug this pins measured
    // ~5px on a 32px spinner, and a correct spin measures a fraction of one
    // (the arc is rasterised, so the fit is not exact).
    expect(await orbitRadius(tester, const AppSpinner(size: 32)), lessThan(1));
  });

  testWidgets('spins in place even when its box is squeezed', (tester) async {
    // The squeeze is the whole bug: a parent that offers less room than the
    // glyph needs must not be able to knock it off its own axis.
    expect(
      await orbitRadius(tester, const SizedBox.square(dimension: 24, child: AppSpinner(size: 32))),
      lessThan(1),
    );
  });

  testWidgets('an icon button spins in place while loading', (tester) async {
    // The call site the wobble actually shipped in.
    expect(
      await orbitRadius(
        tester,
        const AppIconButton(icon: AppIcons.run, isLoading: true, size: AppIconButtonSize.xlarge),
      ),
      lessThan(1),
    );
  });
}

// --- Measuring -------------------------------------------------------------

/// The lucide icon font, loaded from `forui_assets` on disk.
///
/// `flutter test` renders unloaded fonts as an identical placeholder box for
/// every glyph, so without this the measurements below would be of a square,
/// not of the spinner — and they would agree with each other while measuring
/// nothing.
Future<void> loadLucide() async {
  final config =
      jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map<String, dynamic>;
  final package = (config['packages'] as List).cast<Map<String, dynamic>>().firstWhere(
    (p) => p['name'] == 'forui_assets',
  );
  final root = Uri.parse(package['rootUri'] as String);
  final directory = root.isAbsolute
      ? root.toFilePath()
      : File('.dart_tool/${root.toFilePath()}').absolute.path;
  final bytes = File('$directory/assets/lucide.ttf').readAsBytesSync();

  await (FontLoader(
    'packages/forui_assets/ForuiLucideIcons',
  )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

/// A rasterised widget, as "is this pixel inked" queries.
class InkImage(final int width, final int height, final Uint8List _rgba) {
  /// Alpha, not colour: the spinner paints in the theme's primary onto a
  /// transparent boundary, and that colour has no red in it at all.
  bool lit(int x, int y) => _rgba[(y * width + x) * 4 + 3] > 60;
}

Future<InkImage> captureInk(WidgetTester tester, Finder target) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.ancestor(of: target, matching: find.byType(RepaintBoundary)).first,
  );
  late InkImage captured;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = (await image.toByteData())!;
    captured = InkImage(image.width, image.height, data.buffer.asUint8List());
  });
  return captured;
}

/// Least-squares circle through [points] (Kåsa's linearisation), returning
/// its centre.
Offset fitCircle(List<Offset> points) {
  var sx = 0.0;
  var sy = 0.0;
  var sxx = 0.0;
  var syy = 0.0;
  var sxy = 0.0;
  var sz = 0.0;
  var szx = 0.0;
  var szy = 0.0;
  for (final p in points) {
    final z = p.dx * p.dx + p.dy * p.dy;
    sx += p.dx;
    sy += p.dy;
    sxx += p.dx * p.dx;
    syy += p.dy * p.dy;
    sxy += p.dx * p.dy;
    sz += z;
    szx += z * p.dx;
    szy += z * p.dy;
  }
  final n = points.length.toDouble();
  final matrix = [
    [2 * sxx, 2 * sxy, sx, szx],
    [2 * sxy, 2 * syy, sy, szy],
    [2 * sx, 2 * sy, n, sz],
  ];

  for (var i = 0; i < 3; i++) {
    var pivot = i;
    for (var r = i + 1; r < 3; r++) {
      if (matrix[r][i].abs() > matrix[pivot][i].abs()) pivot = r;
    }
    final swap = matrix[i];
    matrix[i] = matrix[pivot];
    matrix[pivot] = swap;

    for (var r = 0; r < 3; r++) {
      if (r == i) continue;
      final factor = matrix[r][i] / matrix[i][i];
      for (var c = i; c < 4; c++) {
        matrix[r][c] -= factor * matrix[i][c];
      }
    }
  }

  return Offset(matrix[0][3] / matrix[0][0], matrix[1][3] / matrix[1][1]);
}
