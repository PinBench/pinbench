import 'package:flutter/widgets.dart';

import '../../models/part_model.dart';
import '../../models/port_model.dart';
import '../../painting/base_component_painter.dart';
import '../../painting/path_art.dart';
import '../../painting/part_text.dart';
import '../../painting/port_provider.dart';
import 'pico_w_art.dart';

/// One castellated pin: its port id, the name it is known by, and the few
/// letters printed beside it.
typedef _Pin = (String id, String name, String label);

/// Draws a Raspberry Pi Pico W lying down, micro-USB to the left, with its 40
/// pins on the connection lattice so it straddles a breadboard's channel the
/// way the real one does (its rows are 0.7" apart, seven holes).
///
/// The board's own silkscreen numbers only pins 1, 2, 39 and 40; the pinout is
/// on the back. Here each pin's name is printed beside it instead, because the
/// canvas shows nothing on hover and the top is the only side there is.
///
/// Port ids follow the sketch: a GPIO is its number (`'15'` is GP15, what
/// `digitalWrite(15, …)` drives), grounds are `GND_1`–`GND_8` in pin order,
/// and the supplies are `'3.3V'` (3V3 OUT) and `'5V'` (VBUS), the names every
/// part that takes power from a board already looks for. See
/// `BoardProfile.picoW`.
class PicoWPainter({final Map<String, dynamic>? properties, super.isOutline})
    extends BaseComponentPainter
    with PathArtPainter, PortProvider {
  static const width = 344.0;
  static const height = 152.0;
  static const componentSize = Size(width, height);

  /// Pins 1–20, left to right along the bottom edge.
  static const bottomPins = <_Pin>[
    ('0', 'GP0', 'GP0'),
    ('1', 'GP1', 'GP1'),
    ('GND_1', 'GND', 'GND'),
    ('2', 'GP2', 'GP2'),
    ('3', 'GP3', 'GP3'),
    ('4', 'GP4 (SDA)', 'GP4'),
    ('5', 'GP5 (SCL)', 'GP5'),
    ('GND_2', 'GND', 'GND'),
    ('6', 'GP6', 'GP6'),
    ('7', 'GP7', 'GP7'),
    ('8', 'GP8', 'GP8'),
    ('9', 'GP9', 'GP9'),
    ('GND_3', 'GND', 'GND'),
    ('10', 'GP10', 'GP10'),
    ('11', 'GP11', 'GP11'),
    ('12', 'GP12', 'GP12'),
    ('13', 'GP13', 'GP13'),
    ('GND_4', 'GND', 'GND'),
    ('14', 'GP14', 'GP14'),
    ('15', 'GP15', 'GP15'),
  ];

  /// Pins 40–21, left to right along the top edge.
  static const topPins = <_Pin>[
    ('5V', 'VBUS', 'VBUS'),
    ('VSYS', 'VSYS', 'VSYS'),
    ('GND_8', 'GND', 'GND'),
    ('3V3_EN', '3V3_EN', 'EN'),
    ('3.3V', '3V3(OUT)', '3V3'),
    ('ADC_VREF', 'ADC_VREF', 'VREF'),
    ('28', 'GP28 (A2)', 'GP28'),
    ('GND_7', 'AGND', 'AGND'),
    ('27', 'GP27 (A1)', 'GP27'),
    ('26', 'GP26 (A0)', 'GP26'),
    ('RUN', 'RUN', 'RUN'),
    ('22', 'GP22', 'GP22'),
    ('GND_6', 'GND', 'GND'),
    ('21', 'GP21', 'GP21'),
    ('20', 'GP20', 'GP20'),
    ('19', 'GP19', 'GP19'),
    ('18', 'GP18', 'GP18'),
    ('GND_5', 'GND', 'GND'),
    ('17', 'GP17', 'GP17'),
    ('16', 'GP16', 'GP16'),
  ];

  /// Where the pins sit: one hole pitch apart, both rows on the lattice.
  static const _firstPinX = 20.0;
  static const _topRowY = 20.0;
  static const _bottomRowY = 132.0;
  static const _pitch = 16.0;

  static final _ports = [
    for (final (i, (id, name, _)) in topPins.indexed)
      ComponentPort(id: id, name: name, localOffset: Offset(_firstPinX + i * _pitch, _topRowY)),
    for (final (i, (id, name, _)) in bottomPins.indexed)
      ComponentPort(id: id, name: name, localOffset: Offset(_firstPinX + i * _pitch, _bottomRowY)),
  ];

  @override
  List<ComponentPort> getPorts() => _ports;

  /// The board, and the micro-USB socket overhanging its end.
  @override
  Rect bodyRect(Size size) => Rect.fromPoints(PicoWArt.at(-1.3, 0), PicoWArt.at(51, 21));

  @override
  Size get designSize => componentSize;

  @override
  List<PathArtLayer> get layers => _layers;

  static final _layers = <PathArtLayer>[
    (PicoWArt.board, const Color(0xFF2E9A4A)),
    (PicoWArt.antennaKeepOut, const Color(0xFF4DB262)),
    (PicoWArt.pads, const Color(0xFFD6AE52)),
    (PicoWArt.holes, const Color(0xFF26302A)),
    (PicoWArt.antenna, const Color(0xFFC79F45)),
    (PicoWArt.usbShell, const Color(0xFFB9BEC4)),
    (PicoWArt.usbPlate, const Color(0xFFD9DDE1)),
    (PicoWArt.chips, const Color(0xFF232323)),
    (PicoWArt.metal, const Color(0xFFC4C8CC)),
    (PicoWArt.buttonBody, const Color(0xFFBFC3C7)),
    (PicoWArt.buttonCap, const Color(0xFFF2F0E8)),
    (PicoWArt.shield, const Color(0xFFA9AEB4)),
    (PicoWArt.shieldLid, const Color(0xFFC9CDD1)),
    (PicoWArt.led, const Color(0xFFE8E4D2)),
  ];

  bool get isLedOn => properties?[ComponentProps.isOn] == true;

  @override
  void paintText(Canvas canvas) {
    for (final (i, pin) in topPins.indexed) {
      _label(pin.$3).paint(canvas, PicoWArt.labelCentre(i, top: true), angle: PicoWArt.labelAngle);
    }
    for (final (i, pin) in bottomPins.indexed) {
      _label(pin.$3).paint(canvas, PicoWArt.labelCentre(i, top: false), angle: PicoWArt.labelAngle);
    }
    _chip.paint(canvas, PicoWArt.at(23.5, 10.5));
    _model.paint(canvas, PicoWArt.at(39.3, 10.5));
    _bootsel.paint(canvas, PicoWArt.at(8.3, 7.9));
    _ledLegend.paint(canvas, PicoWArt.at(8.6, 14.05));
  }

  /// The on-board LED, lit — it follows GP25, `LED_BUILTIN`.
  @override
  void paintOverlay(Canvas canvas) {
    if (!isLedOn) return;
    final centre = PicoWArt.ledCentre;
    canvas.drawCircle(
      centre,
      PicoWArt.mm(1.6),
      Paint()
        ..color = const Color(0x8862FF7A)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: centre, width: PicoWArt.mm(1.6), height: PicoWArt.mm(0.9)),
        Radius.circular(PicoWArt.mm(0.15)),
      ),
      Paint()..color = const Color(0xFF7CFF8E),
    );
  }

  @override
  bool shouldRepaintComponent(covariant PicoWPainter oldDelegate) => oldDelegate.isLedOn != isLedOn;

  static const _silk = Color(0xFFF2F2EE);
  static final _labels = <String, PartText>{};
  static PartText _label(String text) =>
      _labels[text] ??= PartText(text, capHeight: 4.2, color: _silk, maxWidth: 16);

  static const _chip = PartText('RP2-B2', capHeight: 4.2, color: Color(0xFFBDBDBD));
  static const _model = PartText('Pico W', capHeight: 7, color: Color(0xFF7D838A));
  static const _bootsel = PartText('BOOTSEL', capHeight: 3.2, color: _silk);
  static const _ledLegend = PartText('LED', capHeight: 3.2, color: _silk);
}
