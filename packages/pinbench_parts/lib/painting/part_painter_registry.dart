import '../painters/battery_9v_painter.dart';
import '../painters/cr2032_painter.dart';
import '../painters/diode_1n4148_painter.dart';
import '../painters/ldr_painter.dart';
import '../painters/transistor_painter.dart';
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
    'diode_1n4148': Diode1n4148Painter.new,
    'ldr': LdrPainter.new,
    for (final kind in TransistorKind.values)
      'transistor_${kind.name}': ({isOutline = false, properties}) =>
          TransistorPainter(kind, isOutline: isOutline, properties: properties),
  };

  /// The painter registered as [name], or null.
  static PartPainterBuilder? find(String name) => _painters[name];

  /// Registers [builder] as [name], replacing any painter already there.
  static void register(String name, PartPainterBuilder builder) => _painters[name] = builder;
}
