import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:flutter_svg/svg.dart';

import '../../painting/physical_scale.dart';
import '../../painting/base_component_painter.dart';
import '../../painting/port_provider.dart';
import '../../models/port_model.dart';
import '../../painting/paint_node.dart';
import 'parts/arduino_board.dart';
import 'parts/arduino_chip.dart';
import 'parts/arduino_usb_port.dart';
import 'parts/arduino_power_port.dart';
import 'parts/arduino_capacitor.dart';
import 'parts/arduino_reset_button.dart';
import 'parts/arduino_smd_led.dart';
import 'parts/arduino_pins.dart';
import 'parts/arduino_logo.dart';

class ArduinoPainter({super.isOutline = false}) extends BaseComponentPainter with PortProvider {
  this : super(repaint: logoNotifier);

  static final ValueNotifier<bool> logoNotifier = ValueNotifier(false);
  static ui.Image? image;
  static var isLoadSvgTriggered = false;

  static const EdgeInsets padding = EdgeInsets.zero;

  /// Pin spacing in internal units. The painter draws in an [internalSize]
  /// space scaled [_scale]x, so 8 here = 16 canvas px — exactly one breadboard
  /// hole pitch. Together with the group offsets below (internal ≡2 mod 8, so
  /// x2 → ≡4 mod 16, the connection lattice every other part's legs sit on),
  /// this keeps wires to grid-snapped parts vertically straight.
  static const pinPitch = 8.0;

  /// Uno R3 PCB outline. Width is the official 68.6 mm.
  ///
  /// Height is drawn at 52.07 mm rather than the real 53.4, because the two
  /// constraints below cannot both hold at the true size:
  ///
  ///   * both headers must sit on the connection lattice, so each y is ≡2 mod
  ///     8 in internal units (see the pin offsets below);
  ///   * the headers should be inset equally from the top and bottom edges.
  ///
  /// Two values ≡2 mod 8 sum to ≡4 mod 8, but 53.4 mm is 168.19 internal units
  /// (≡0.19 mod 8), so no on-lattice pair is symmetric. 52.07 mm is exactly 164
  /// units, which puts the headers at 10 and 154 with a matching 10-unit inset
  /// at each end. The 1.33 mm trim is the same kind of deliberate adjustment
  /// the KY-037 and servo bodies use.
  static const boardWidthMm = 68.6;
  static const boardHeightMm = 52.07;

  /// Internal units per canvas pixel. Two canvas px per unit puts the 0.1"
  /// header pitch at exactly [pinPitch] units, so the board can be drawn at
  /// its true size without knocking the pins off the lattice.
  static const _scale = 2.0;

  static const boardWidth = boardWidthMm * PhysicalScale.pxPerMm;
  static const boardHeight = boardHeightMm * PhysicalScale.pxPerMm;

  static const internalSize = Size(boardWidth / _scale, boardHeight / _scale);
  static const componentSize = Size(boardWidth, boardHeight);

  // Component Offsets
  static const logoOffset = Offset(50.0, 44.0);
  static const logoSize = Size(130.0, 43.0);
  static const chipOffset = Offset(90.0, 94.0);
  static const chipSize = Size(110.0, 23.6); // DIP-28: 35 × 7.5 mm
  static const usbOffset = Offset(-8.0, 40.0);
  static const powerJackOffset = Offset(-8.0, 120.0);
  static const resetButtonOffset = Offset(5, 5);
  static const capasitorsOffset = Offset(38.0, 124.0);

  // LED Offsets
  static const lLedOffset = Offset(48.0, 40.0);
  static const txOffset = Offset(48.0, 60.0);
  static const onLedOffset = Offset(184.0, 50.0);

  // Pin Offsets. Internal values are ≡2 mod 8 deliberately: ports scale 2x,
  // landing them on the shared connection lattice (≡4 mod 16 = cellCenter
  // mod pitch) where the other components' legs and breadboard holes sit —
  // see [pinPitch]. That's true for y too (10 → 20 px, 154 → 308 px).
  //
  // Nudging these to line the header art up costs straight wires: one unit
  // here is two canvas px, so a value ≡4 or ≡6 mod 8 puts every pin in the
  // group half a pitch off the lattice, and no part snapped to the grid can
  // meet it. Move them in whole steps of 8 — grid_alignment_test says so.
  // Keep y at 154, not 158: 158 is ≡6 mod 8, which puts the whole bottom
  // header half a pitch off the lattice. That exact regression has now
  // happened twice (fixed in 6746880, reverted by 7912f47).
  static const powerPinsOffset = Offset(82.0, 154.0);
  static const analogPinsOffset = Offset(154.0, 154.0);
  static const digitalHighPinsOffset = Offset(50.0, 10.0);
  static const digitalLowPinsOffset = Offset(138.0, 10.0);

  // Pin Labels
  static const digitalHighLabels = ['', '', 'AREF', 'GND', '13', '12', '~11', '~10', '~9', '8'];
  static const digitalLowLabels = ['7', '~6', '~5', '4', '~3', '2', 'TK->1', 'RX<-0'];
  static const powerLabels = ['', 'IOREF', 'RESET', '3.3V', '5V', 'GND', 'GND', 'Vin'];
  static const analogLabels = ['A0', 'A1', 'A2', 'A3', 'A4', 'A5'];

  // Pin Port IDs
  static const digitalHighIds = ['SCL', 'SDA', 'AREF', 'GND_1', '13', '12', '11', '10', '9', '8'];
  static const digitalLowIds = ['7', '6', '5', '4', '3', '2', '1', '0'];
  static const powerIds = ['NC', 'IOREF', 'RESET', '3.3V', '5V', 'GND_2', 'GND_3', 'VIN'];
  static const analogIds = ['A0', 'A1', 'A2', 'A3', 'A4', 'A5'];

  // Layout Engine Tree!
  late final PaintNode _arduinoTree = _buildCanvasTree();

  PaintNode _buildCanvasTree() => CanvasStack(
    size: internalSize,
    children: [
      CanvasPositioned(left: 0, top: 0, child: BoardBackgroundNode(size: internalSize)),
      CanvasPositioned(
        left: logoOffset.dx,
        top: logoOffset.dy,
        child: LogoNode(size: logoSize),
      ),
      CanvasPositioned(
        left: chipOffset.dx,
        top: chipOffset.dy,
        child: ChipNode(size: chipSize),
      ),
      CanvasPositioned(left: usbOffset.dx, top: usbOffset.dy, child: UsbPortNode()),
      CanvasPositioned(left: powerJackOffset.dx, top: powerJackOffset.dy, child: PowerPortNode()),
      CanvasPositioned(
        left: resetButtonOffset.dx,
        top: resetButtonOffset.dy,
        child: ResetButtonNode(),
      ),

      _digitalPins(),
      _powerPins(),
      _analogPins(),

      // Grouped Capacitors
      CanvasPositioned(
        left: capasitorsOffset.dx,
        top: capasitorsOffset.dy,
        child: CanvasRow(
          spacing: 5.0, // 82.5 - 52.5 - 25.0(cap width) = 5.0
          children: [CapacitorNode(), CapacitorNode()],
        ),
      ),

      // L LED
      CanvasPositioned(
        left: lLedOffset.dx,
        top: lLedOffset.dy,
        child: SmdLedNode(label: 'L'),
      ),
      // ON LED
      CanvasPositioned(
        left: onLedOffset.dx,
        top: onLedOffset.dy,
        child: SmdLedNode(label: 'ON', ledColor: const Color(0xFF6EDC5F), labelOnRight: true),
      ),

      // Grouped TX/RX LEDs
      CanvasPositioned(
        left: txOffset.dx,
        top: txOffset.dy,
        child: CanvasColumn(
          spacing: 2.0, // 51.0 - 41.0 - 8.0(led height) = 2.0
          children: [
            SmdLedNode(label: 'TX'),
            SmdLedNode(label: 'RX'),
          ],
        ),
      ),
    ],
  );

  CanvasPositioned _powerPins() => CanvasPositioned(
    left: powerPinsOffset.dx - PinBlockNode.centerInsetX,
    top: powerPinsOffset.dy - PinBlockNode.centerInsetY,
    child: CanvasStack(
      children: [
        CanvasPositioned(child: PinBlockNode(labels: powerLabels, isTop: false)),
        CanvasPositioned(
          left: PinBlockNode.centerInsetX + 6,
          top: -26.0, // Easy single value to change the gap!
          child: BoardLabelLineNode(text: 'POWER', width: 6.5 * pinPitch, textAbove: true),
        ),
      ],
    ),
  );

  CanvasPositioned _analogPins() => CanvasPositioned(
    left: analogPinsOffset.dx - PinBlockNode.centerInsetX,
    top: analogPinsOffset.dy - PinBlockNode.centerInsetY,
    child: CanvasStack(
      children: [
        CanvasPositioned(child: PinBlockNode(labels: analogLabels, isTop: false)),
        CanvasPositioned(
          left: PinBlockNode.centerInsetX - 2,
          top: -26.0, // Easy single value to change the gap!
          child: BoardLabelLineNode(text: 'ANALOG IN', width: 5.5 * pinPitch, textAbove: true),
        ),
      ],
    ),
  );

  CanvasPositioned _digitalPins() => CanvasPositioned(
    left: digitalHighPinsOffset.dx - PinBlockNode.centerInsetX,
    top: digitalHighPinsOffset.dy - PinBlockNode.centerInsetY,
    child: CanvasStack(
      children: [
        CanvasPositioned(child: PinBlockNode(labels: digitalHighLabels)),
        CanvasPositioned(
          left: digitalLowPinsOffset.dx - digitalHighPinsOffset.dx,
          child: PinBlockNode(labels: digitalLowLabels),
        ),
        CanvasPositioned(
          left: 4 * pinPitch + 3.0,
          top: 24.0, // Easy single value to change the gap!
          child: BoardLabelLineNode(
            text: 'DIGITAL (PWM~)',
            width:
                (digitalLowPinsOffset.dx + 7 * pinPitch) -
                (digitalHighPinsOffset.dx + 4 * pinPitch) +
                4.0,
            textAbove: true,
          ),
        ),
      ],
    ),
  );

  void _addPortsForGroup(
    List<ComponentPort> ports,
    List<String> labels,
    List<String> ids,
    Offset startPos,
    double sx,
    double sy,
  ) {
    for (var i = 0; i < labels.length; i++) {
      ports.add(
        ComponentPort(
          id: ids[i],
          name: labels[i].isEmpty ? ids[i] : labels[i],
          localOffset: Offset(
            padding.left * sx + (startPos.dx + i * pinPitch) * sx,
            padding.top * sy + startPos.dy * sy,
          ),
        ),
      );
    }
  }

  @override
  List<ComponentPort> getPorts() {
    final ports = <ComponentPort>[];

    final sx = componentSize.width / internalSize.width;
    final sy = componentSize.height / internalSize.height;

    _addPortsForGroup(ports, powerLabels, powerIds, powerPinsOffset, sx, sy);
    _addPortsForGroup(ports, analogLabels, analogIds, analogPinsOffset, sx, sy);
    _addPortsForGroup(ports, digitalLowLabels, digitalLowIds, digitalLowPinsOffset, sx, sy);
    _addPortsForGroup(ports, digitalHighLabels, digitalHighIds, digitalHighPinsOffset, sx, sy);

    return ports;
  }

  Future<void> loadSvg() async {
    if (isLoadSvgTriggered) return;
    isLoadSvgTriggered = true;

    try {
      final pictureInfo = await vg.loadPicture(
        const SvgAssetLoader('packages/pinbench_parts/assets/parts/arduino/arduino_logo.svg'),
        null,
      );

      image = await pictureInfo.picture.toImage(720, 490);
      logoNotifier.value = !logoNotifier.value;
    } catch (e, stackTrace) {
      // Reported through the framework rather than `AppLogger` on purpose:
      // `FlutterError.onError` is already chained to both the app logger and
      // Crashlytics, so this loses no diagnostics — and it keeps
      // `talker_flutter` out of `parts/`, which is otherwise free of app
      // infrastructure and is the layer meant to become a package.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: stackTrace,
          library: 'parts/painters',
          context: ErrorDescription('loading the Arduino logo SVG'),
        ),
      );
    }
  }

  @override
  void paintComponent(Canvas canvas, Size size) {
    if (image == null) {
      unawaited(loadSvg());
    }

    canvas.save();

    // Scale everything from 250x200 to visual component Size!
    final sx = size.width / internalSize.width;
    final sy = size.height / internalSize.height;

    canvas.translate(padding.left * sx, padding.top * sy);
    canvas.scale(sx, sy);

    _arduinoTree.paint(canvas, Offset.zero);

    canvas.restore();
  }

  @override
  bool shouldRepaintComponent(covariant ArduinoPainter oldDelegate) => false;
}
