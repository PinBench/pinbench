import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinbench_parts/painters/led_painter.dart';
import 'package:pinbench_parts/models/part_model.dart';

/// Renders the LED painter and sums the alpha channel as a proxy for how much
/// light it emits (brighter LED + glow => more total alpha).
Future<int> _totalInk(Map<String, dynamic> properties) async {
  const pad = 24.0;
  final w = (LEDPainter.width + pad * 2).ceil();
  final h = (LEDPainter.height + pad * 2).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..translate(pad, pad);
  LEDPainter(properties: properties).paint(canvas, const Size(LEDPainter.width, LEDPainter.height));

  final image = await recorder.endRecording().toImage(w, h);
  final bytes = (await image.toByteData())!.buffer.asUint8List();

  var ink = 0;
  for (var i = 3; i < bytes.length; i += 4) {
    ink += bytes[i]; // alpha
  }
  return ink;
}

void main() {
  group('LEDPainter.brightnessFraction', () {
    test('defaults to fully bright when unset', () {
      expect(LEDPainter().brightnessFraction, 1.0);
    });

    test('reads and clamps the brightness value', () {
      expect(LEDPainter(properties: const {'brightness': 0.5}).brightnessFraction, 0.5);
      expect(LEDPainter(properties: const {'brightness': 2.0}).brightnessFraction, 1.0);
      expect(LEDPainter(properties: const {'brightness': -1.0}).brightnessFraction, 0.0);
    });
  });

  group('LEDPainter brightness rendering', () {
    test('a brighter LED emits more light than a dim one, which beats off', () async {
      final full = await _totalInk({
        ComponentProps.isOn: true,
        ComponentProps.color: 'Red',
        ComponentProps.brightness: 1.0,
      });
      final dim = await _totalInk({
        ComponentProps.isOn: true,
        ComponentProps.color: 'Red',
        ComponentProps.brightness: 0.25,
      });
      final off = await _totalInk({ComponentProps.isOn: false, ComponentProps.color: 'Red'});

      expect(full, greaterThan(dim));
      expect(dim, greaterThan(off));
    });
  });

  test("the LED's legs are drawn as mirror images of each other", () async {
    // Its bounds, its ports and even its ink's centre were always symmetric —
    // what leaned was the shape: only the anode kinked in from its lead
    // column, so the posts showing through the lens sat left of centre and the
    // part read as off-centre in the palette however the tile placed it.
    //
    // Compared against its own mirror rather than by centre of mass: the lens
    // outweighs a leg by twenty to one, so a lopsided leg barely moves the
    // centroid but is obvious here. Only the band below the dome's highlight
    // is compared, since that highlight is a deliberate top-left asymmetry.
    const scale = 4.0;
    final image = _renderLed(scale);
    final mismatch = await _mirrorMismatch(
      image,
      fromY: (LEDPainter.bodyHeight * 0.55 * scale).round(),
    );

    expect(
      mismatch,
      lessThan(0.02),
      reason: '${(mismatch * 100).toStringAsFixed(1)}% of the legs do not mirror',
    );
  });
}

/// How much of the ink below [fromY] fails to match its mirror image, as a
/// fraction of the ink there. 0 is perfectly symmetric.
Future<double> _mirrorMismatch(ui.Image image, {required int fromY}) async {
  final data = (await image.toByteData())!;
  int alphaAt(int x, int y) => data.getUint8((y * image.width + x) * 4 + 3);

  var differing = 0;
  var ink = 0;
  for (var y = fromY; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final here = alphaAt(x, y);
      final mirrored = alphaAt(image.width - 1 - x, y);
      if (here > 16 || mirrored > 16) ink++;
      if ((here - mirrored).abs() > 32) differing++;
    }
  }
  return ink == 0 ? 0 : differing / ink;
}

ui.Image _renderLed(double scale) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(scale);
  LEDPainter(properties: const {ComponentProps.color: 'Red'})
      .paint(canvas, const Size(LEDPainter.width, LEDPainter.height));
  return recorder.endRecording().toImageSync(
    (LEDPainter.width * scale).ceil(),
    (LEDPainter.height * scale).ceil(),
  );
}
