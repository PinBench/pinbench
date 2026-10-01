import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/port_model.dart';

import 'package:pinbench_pdl/pinbench_pdl.dart';

import '../pdl_flutter.dart';
import 'base_component_painter.dart';
import 'part_painter_registry.dart';
import 'part_text.dart';
import 'pdl_svg_cache.dart';
import 'port_provider.dart';
import 'part_palette.dart';

/// Draws a part that was described by a `.pdl` file rather than by Dart.
///
/// Two layers, in order: the body — the [PartDefinition.visual] SVG scaled to
/// the part's footprint, or the registered Dart painter its `PAINTER` line
/// names — then any vector `VISUALS` shapes over the top. That order is the
/// whole point of the format — a photograph-accurate body comes from artwork
/// nobody had to write, and only the bits that *change* (a lit LED, a needle,
/// a readout) cost a shape.
///
/// Colours and text come from PDL expressions evaluated against the placed
/// component's live properties and simulation state, so a definition can react
/// without any imperative code.
class DSLComponentPainter({
  required final PartDefinition definition,

  /// The placed component's property map — user-edited values *and* whatever
  /// the simulation has written into it this frame.
  final Map<String, dynamic>? properties,
  super.isOutline = false,
}) extends BaseComponentPainter with PortProvider {
  this
    // Repaint when a piece of artwork finishes decoding, or a font loading:
    // the first frame of a part is usually drawn before its SVG has arrived,
    // and a painted body's text before its face has (see `PartText`).
    : super(repaint: Listenable.merge([PdlSvgCache.revision, PartText.fontsChanged]));

  /// The context PDL expressions in this definition see.
  ///
  /// Simulation state is written back into the same `properties` map the user
  /// edits (that is how every other painter here reads runtime values), so
  /// state resolves against it too, falling back to declared initial values so
  /// a part looks right in the palette before it has ever run.
  PdlEvalContext get _context => PdlEvalContext.static(
    state: {...definition.initialState(), ...?properties},
    properties: {...definition.defaultProperties(), ...?properties},
  );

  /// The painter a `PAINTER` line names, drawing the body in place of an SVG.
  ///
  /// Null for an SVG part, and for a name nothing registers: the shapes still
  /// draw, and `pdl_bundled_parts_test.dart` fails on the missing name.
  late final BaseComponentPainter? _body = switch (definition.visual.painter) {
    final name? => PartPainterRegistry.find(
      name,
    )?.call(isOutline: isOutline, properties: properties),
    null => null,
  };

  /// A painted body knows its own outline; an SVG part fills its bounds.
  @override
  Rect? bodyRect(Size size) => _body?.bodyRect(size);

  /// A painted body may have controls of its own.
  @override
  String? regionAt(Offset localPosition, Size size) => _body?.regionAt(localPosition, size);

  @override
  void paintComponent(Canvas canvas, Size size) {
    final context = _context;
    final body = _body;
    if (body != null) {
      body.paintComponent(canvas, size);
    } else {
      _paintArtwork(canvas, size);
    }

    for (final shape in definition.visual.shapes) {
      _paintShape(canvas, shape, context);
    }
  }

  void _paintArtwork(Canvas canvas, Size size) {
    final path = definition.visual.svgPath;
    if (path == null) return;
    final art = PdlSvgCache.artwork(path);
    if (art == null) return; // still loading, or missing — shapes still draw

    canvas.save();
    // The SVG is authored at whatever size its viewBox says; the part is drawn
    // at its real-world footprint. Scale one onto the other rather than
    // trusting them to match, so artwork can be redrawn at any resolution
    // without touching the .pdl.
    if (art.size.width > 0 && art.size.height > 0) {
      canvas.scale(size.width / art.size.width, size.height / art.size.height);
    }
    if (isOutline) {
      // Ghost preview while dragging, matching the other painters.
      canvas.saveLayer(null, Paint()..color = const Color(0x66FFFFFF));
      canvas.drawPicture(art.picture);
      canvas.restore();
    } else {
      canvas.drawPicture(art.picture);
    }
    canvas.restore();
  }

  void _paintShape(Canvas canvas, ShapeDef shape, PdlEvalContext context) {
    final color = _colorOf(shape, context);
    final paint = Paint()
      ..color = color
      ..strokeWidth = shape.width
      ..style = _isFilled(shape) ? PaintingStyle.fill : PaintingStyle.stroke;

    switch (shape) {
      case LineShapeDef(:final x1, :final y1, :final x2, :final y2):
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
      case CircleShapeDef(:final cx, :final cy, :final radius):
        canvas.drawCircle(Offset(cx, cy), radius, paint);
      case RectShapeDef(:final x, :final y, :final w, :final h, :final radius):
        final rect = Rect.fromLTWH(x, y, w, h);
        if (radius > 0) {
          canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)), paint);
        } else {
          canvas.drawRect(rect, paint);
        }
      case TextShapeDef(:final x, :final y, :final text, :final fontSize):
        final painter = TextPainter(
          text: TextSpan(
            text: '${text.evaluate(context) ?? ''}',
            style: TextStyle(color: color, fontSize: fontSize),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(x, y));
      case _:
        break;
    }
  }

  static bool _isFilled(ShapeDef shape) => switch (shape) {
    CircleShapeDef(:final filled) => filled,
    RectShapeDef(:final filled) => filled,
    TextShapeDef() => true,
    _ => false,
  };

  /// A shape's colour, from its own `color:` expression or from a
  /// `visual.<shape id>` behaviour rule — the latter wins, since that is the
  /// binding a running simulation drives.
  Color _colorOf(ShapeDef shape, PdlEvalContext context) {
    for (final rule in definition.behavior) {
      if (rule.target == PdlTarget.visual && shape.id != null && rule.key == shape.id) {
        final value = rule.expression.evaluate(context);
        if (value is PdlColor) return value.toColor();
        if (value is String) return _named(value);
      }
    }
    final value = shape.colorExpr?.evaluate(context);
    if (value is PdlColor) return value.toColor();
    if (value is String) return _named(value);
    return PartPalette.black;
  }

  /// PDL colours are normally `#rrggbb` literals, but property values arrive
  /// as the words a user picked in the properties panel ("Red"), so those are
  /// resolved too.
  static Color _named(String value) {
    if (value.startsWith('#')) {
      try {
        return pdlParseColor(value).toColor();
      } on PdlExpressionException {
        return PartPalette.black;
      }
    }
    return switch (value.toLowerCase()) {
      'red' => PartPalette.red,
      'green' => PartPalette.green,
      'blue' => PartPalette.blue,
      'yellow' => PartPalette.yellow,
      'orange' => PartPalette.orange,
      'white' => PartPalette.white,
      'black' => PartPalette.black,
      'grey' || 'gray' => PartPalette.grey,
      'transparent' => PartPalette.transparent,
      _ => PartPalette.black,
    };
  }

  @override
  bool shouldRepaintComponent(covariant DSLComponentPainter oldDelegate) =>
      oldDelegate.definition != definition ||
      !mapEquals(oldDelegate.properties, properties) ||
      oldDelegate.isOutline != isOutline;

  /// A definition's pins as connection points, built once per definition —
  /// `getPorts` runs on every paint and hit test.
  static final _ports = Expando<List<ComponentPort>>();

  @override
  List<ComponentPort> getPorts() =>
      _ports[definition] ??= [for (final pin in definition.pins) pin.toPort()];

  @override
  Offset? getPortOffsetById(String id) => definition.pin(id)?.localOffset;
}
