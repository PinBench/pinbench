import '../painters/axial_diode/axial_diode_painter.dart';
import '../painters/battery_9v/battery_9v_painter.dart';
import '../painters/cr2032/cr2032_painter.dart';
import '../painters/electrolytic_capacitor/electrolytic_capacitor_painter.dart';
import '../painters/ir_receiver/ir_receiver_painter.dart';
import '../painters/ldr/ldr_painter.dart';
import '../painters/rgb_led/rgb_led_painter.dart';
import '../painters/seven_segment/seven_segment_painter.dart';
import '../painters/slide_switch_spdt/slide_switch_spdt_painter.dart';
import '../painters/to220/to220_painter.dart';
import '../painters/transistor/transistor_painter.dart';
import 'base_component_painter.dart';

/// Builds a part's painter for one placed instance.
typedef PartPainterBuilder = BaseComponentPainter Function({
  bool isOutline,
  Map<String, dynamic>? properties,
});

/// The Dart painters a `.pdl` part can draw its body with, by the name its
/// `PAINTER` line gives.
///
/// This is how a part keeps everything but its drawing as data: pins,
/// properties, behaviour and physics stay in the `.pdl`, and only the artwork
/// is code — typically vector paths generated from a design tool rather than
/// written by hand. See `DSLComponentPainter`, which hands its body to these.
abstract final class PartPainterRegistry {
  static final Map<String, PartPainterBuilder> _painters = {
    'battery_9v': Battery9vPainter.new,
    'cr2032': Cr2032Painter.new,
    for (final (name, kind) in const [
      ('diode_1n4007', DiodeKind.rectifier),
      ('diode_1n4148', DiodeKind.switching),
      ('diode_1n5819', DiodeKind.schottky),
    ])
      name: ({isOutline = false, properties}) =>
          AxialDiodePainter(kind, isOutline: isOutline, properties: properties),
    'capacitor_electrolytic': ElectrolyticCapacitorPainter.new,
    'ir_receiver': IrReceiverPainter.new,
    'ldr': LdrPainter.new,
    'rgb_led': RgbLedPainter.new,
    'seven_segment': SevenSegmentPainter.new,
    'slide_switch_spdt': SlideSwitchSpdtPainter.new,
    for (final kind in TransistorKind.values)
      'transistor_${kind.name}': ({isOutline = false, properties}) =>
          TransistorPainter(kind, isOutline: isOutline, properties: properties),
    for (final (name, kind) in const [
      ('to220_power_nmos', To220Kind.powerNmos),
      ('to220_power_pmos', To220Kind.powerPmos),
      ('to220_tip120', To220Kind.tip120),
    ])
      name: ({isOutline = false, properties}) =>
          To220Painter(kind, isOutline: isOutline, properties: properties),
  };

  /// The painter registered as [name], or null.
  static PartPainterBuilder? find(String name) => _painters[name];

  /// Registers [builder] as [name], replacing any painter already there.
  static void register(String name, PartPainterBuilder builder) => _painters[name] = builder;
}
