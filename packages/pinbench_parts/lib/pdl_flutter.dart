import 'package:flutter/widgets.dart';
import 'package:pinbench_pdl/pinbench_pdl.dart';

import 'models/port_model.dart';

/// Where the `.pdl` format meets Flutter.
///
/// `pinbench_pdl` is pure Dart so tools outside the app can read the format;
/// its geometry and colours are plain values. These extensions turn them into
/// the types the canvas draws with, in one place, so the rest of the app reads
/// `pin.localOffset` and `visual.size` exactly as it did when the model was
/// Flutter-typed.

extension PdlPointOffset on PdlPoint {
  Offset toOffset() => Offset(x, y);
}

extension PdlColorFlutter on PdlColor {
  Color toColor() => Color(value);
}

extension PinDefPort on PinDef {
  /// [position] as a canvas offset.
  Offset get localOffset => position.toOffset();

  /// The pin as a placed part's connection point.
  ComponentPort toPort() => ComponentPort(id: id, name: name, localOffset: localOffset, type: type);
}

extension VisualDefFlutter on VisualDef {
  /// Where the part's origin sits inside its footprint.
  Offset get centerOffset => origin.toOffset();

  Size get size => Size(width, height);
}
