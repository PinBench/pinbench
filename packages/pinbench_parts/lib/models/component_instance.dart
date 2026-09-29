import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../part_registry.dart';
import '../id_generator.dart';
import '../pdl_flutter.dart';
import 'breadboard_state.dart';
import '../painting/base_component_painter.dart';
import '../painting/port_provider.dart';
import 'part_model.dart';
import 'port_model.dart';

/// A **component**: one part placed on the canvas. Holds the [part] it is an
/// instance of plus the instance state — [position], rotation/flip, optional
/// custom size, a stable [key], and a free-form [properties] map (see
/// `ComponentProps`).
///
/// The part/component split is the vocabulary of this package's README: a
/// [PartModel] is the catalog entry (one LED type), this is a placed one (the
/// three LEDs in *this* circuit), and each `id := Type { … }` element in a
/// `.cdl` file becomes one of these.
///
/// Provides the geometry the renderer and hit-testing rely on ([currentSize],
/// [pivotOffset], [getPortOffset]) accounting for rotation, flip and scaling.
class ComponentInstance({
  required var Offset position,
  required final PartModel part,
  var double rotationAngle = 0.0,
  var bool flipHorizontal = false,
  var bool flipVertical = false,
  var double? customWidth,
  var double? customHeight,
  Map<String, dynamic>? properties,
  LocalKey? key,
}) {
  static Map<String, dynamic> _getDefaultProperties(PartModel part) {
    // What the part itself declares wins, and it is also the only form that
    // can be right: the name matching below reads "OLED Display" as an LED and
    // "Photoresistor" as a resistor, which is exactly the kind of collision a
    // declared default avoids. New parts should use [PartModel.defaults].
    if (part.defaults.isNotEmpty) return Map<String, dynamic>.from(part.defaults);

    final componentName = part.name;
    if (componentName.toLowerCase().contains('led')) {
      return {ComponentProps.color: 'Red'};
    } else if (componentName.toLowerCase().contains('resistor')) {
      // Plain ohms, matching what the `.cdl` stores. A unit here would only
      // show up in the properties panel and would then differ between a part
      // dropped fresh and the same part loaded back from a file.
      return {ComponentProps.resistance: '220'};
    } else if (componentName == PartNames.potentiometer) {
      return {ComponentProps.potentiometerValue: '0.5'};
    }
    return {};
  }

  Map<String, dynamic> properties = properties ?? _getDefaultProperties(part);
  Offset? hoveredLocalPosition;
  BreadboardHoverState? breadboardHover;
  Size get baseSize => Size(customWidth ?? part.size.width, customHeight ?? part.size.height);

  // Cached geometry — computed on first access, fresh per instance (copyWith).
  List<Offset>? _cachedRotatedCorners;
  Offset? _cachedPivotOffset;
  Size? _cachedCurrentSize;

  List<Offset> _computeRotatedCorners() {
    final w = baseSize.width;
    final h = baseSize.height;
    final c = math.cos(rotationAngle);
    final s = math.sin(rotationAngle);

    // Corners relative to topCenter (w/2, 0)
    final points = [Offset(-w / 2, 0), Offset(w / 2, 0), Offset(-w / 2, h), Offset(w / 2, h)];

    return points.map((p) => Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c)).toList();
  }

  List<Offset> get _getRotatedCorners => _cachedRotatedCorners ??= _computeRotatedCorners();

  Offset get pivotOffset => _cachedPivotOffset ??= () {
    final corners = _getRotatedCorners;
    final minX = corners.map((p) => p.dx).reduce(math.min);
    final minY = corners.map((p) => p.dy).reduce(math.min);
    return Offset(-minX, -minY);
  }();

  Size get currentSize => _cachedCurrentSize ??= () {
    final corners = _getRotatedCorners;
    final minX = corners.map((p) => p.dx).reduce(math.min);
    final maxX = corners.map((p) => p.dx).reduce(math.max);
    final minY = corners.map((p) => p.dy).reduce(math.min);
    final maxY = corners.map((p) => p.dy).reduce(math.max);
    return Size(maxX - minX, maxY - minY);
  }();

  /// This instance's ports in the component's own unrotated space, from
  /// whichever source defines them — a PDL definition's pins or the painter's
  /// static ports. Empty for parts that discover ports dynamically (the
  /// breadboard, whose holes are found by hit-testing rather than listed).
  ///
  /// Use [getPortOffset] to place one of these on the canvas; that's what
  /// applies scale, flip and rotation.
  List<ComponentPort> get ports {
    if (part.definitionId != null) {
      final def = PartRegistry.getPart(part.definitionId!);
      if (def != null && def.pins.isNotEmpty) {
        return [
          for (final pin in def.pins)
            ComponentPort(id: pin.id, name: pin.name, localOffset: pin.localOffset),
        ];
      }
    }

    final painter = part.getPainter(properties: properties);
    if (painter is! PortProvider) return const [];
    return (painter! as PortProvider).getPorts();
  }

  ComponentPort? getPortById(String id) {
    if (part.definitionId != null) {
      final def = PartRegistry.getPart(part.definitionId!);
      if (def != null) {
        for (final pin in def.pins) {
          if (pin.id == id) {
            return ComponentPort(id: pin.id, name: pin.name, localOffset: pin.localOffset);
          }
        }
      }
    }

    final painter = part.getPainter();
    if (painter is! PortProvider) return null;

    final staticPorts = (painter! as PortProvider).getPorts();
    for (final p in staticPorts) {
      if (p.id == id) return p;
    }

    return null;
  }

  Offset? getPortOffset(String portId) {
    Offset? baseOffset;

    if (part.definitionId != null) {
      final def = PartRegistry.getPart(part.definitionId!);
      if (def != null) {
        for (final pin in def.pins) {
          if (pin.id == portId) {
            baseOffset = pin.localOffset;
            break;
          }
        }
      }
    }

    if (baseOffset == null) {
      final painter = part.getPainter();
      if (painter is PortProvider) {
        baseOffset = (painter! as PortProvider).getPortOffsetById(portId);
      }
    }

    return baseOffset == null ? null : localToNodeOffset(baseOffset);
  }

  /// A point in the component's own unrotated space, as an offset from this
  /// instance's [position] — scale, flip and rotation applied.
  ///
  /// The inverse of [absoluteToLocal], and what [getPortOffset] is built on.
  /// Exposed for the geometry a painter doesn't list as ports: a breadboard's
  /// holes are found by hit-testing in local space and still need placing on
  /// the canvas (see `SnapGuideHelper`).
  Offset localToNodeOffset(Offset local) {
    {
      final baseOffset = local;
      // Calculate scaling factors for the ports if size changed
      final scaleX = baseSize.width / part.size.width;
      final scaleY = baseSize.height / part.size.height;

      final scaledOffset = Offset(baseOffset.dx * scaleX, baseOffset.dy * scaleY);

      final w = baseSize.width;

      // Calculate rotation center of the unrotated component (topCenter)
      final cx = w / 2;
      const cy = 0.0;

      // Apply flip
      var fx = scaledOffset.dx;
      var fy = scaledOffset.dy;
      if (flipHorizontal) fx = w - fx;
      if (flipVertical) fy = baseSize.height - fy;

      // Translate to center
      final dx = fx - cx;
      final dy = fy - cy;

      // Rotate by angle
      final c = math.cos(rotationAngle);
      final s = math.sin(rotationAngle);
      final rx = dx * c - dy * s;
      final ry = dx * s + dy * c;

      // Translate back to the new bounding box's coordinate system
      return pivotOffset + Offset(rx, ry);
    }
  }

  Offset absoluteToLocal(Offset absolutePosition) {
    final baseSize = part.size;
    final scaleX = baseSize.width / part.size.width;
    final scaleY = baseSize.height / part.size.height;

    // Remove component position and pivot
    final delta = absolutePosition - (position + pivotOffset);

    // Un-rotate
    final c = math.cos(-rotationAngle);
    final s = math.sin(-rotationAngle);
    final ux = delta.dx * c - delta.dy * s;
    final uy = delta.dx * s + delta.dy * c;

    // Un-translate from center
    final cx = baseSize.width / 2;
    const cy = 0.0;
    var fx = ux + cx;
    var fy = uy + cy;

    // Un-flip
    if (flipHorizontal) fx = baseSize.width - fx;
    if (flipVertical) fy = baseSize.height - fy;

    // Un-scale
    return Offset(fx / scaleX, fy / scaleY);
  }

  final LocalKey key = key ?? ValueKey(IdGenerator.generate('node'));
  Rect get rect => position & currentSize;

  /// Whether [canvasPosition] is on this part as *drawn*, rather than merely
  /// inside [rect].
  ///
  /// The two differ a lot for a small part: an LED's bounds are a 56×56 box
  /// holding a 5 mm lens and two legs, and the rest is air that belongs to
  /// whatever is underneath — usually a breadboard whose holes should still
  /// hover. See [BaseComponentPainter.hitArea]; parts that fill their bounds
  /// (the breadboard, PCB modules) answer the same as [rect].
  bool covers(Offset canvasPosition) {
    if (!rect.contains(canvasPosition)) return false; // cheap reject first
    final painter = part.getPainter(properties: properties);
    if (painter == null) return true;
    return painter.hitArea(part.size).contains(absoluteToLocal(canvasPosition));
  }

  ComponentInstance copyWith({
    Offset? position,
    Offset? hoveredLocalPosition,
    BreadboardHoverState? breadboardHover,
    PartModel? part,
    double? rotationAngle,
    bool? flipHorizontal,
    bool? flipVertical,
    double? customWidth,
    double? customHeight,
    bool clearCustomWidth = false,
    bool clearCustomHeight = false,
    Map<String, dynamic>? properties,
    LocalKey? key,
  }) {
    final newNode = ComponentInstance(
      position: position ?? this.position,
      part: part ?? this.part,
      rotationAngle: rotationAngle ?? this.rotationAngle,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      customWidth: clearCustomWidth ? null : (customWidth ?? this.customWidth),
      customHeight: clearCustomHeight ? null : (customHeight ?? this.customHeight),
      properties: properties ?? Map.from(this.properties),
      key: key ?? this.key,
    );
    newNode.hoveredLocalPosition = hoveredLocalPosition ?? this.hoveredLocalPosition;
    newNode.breadboardHover = breadboardHover ?? this.breadboardHover;
    return newNode;
  }

  Map<String, dynamic> toJson() => {
    'id': nodeKeyToId(key),
    'position': {'dx': position.dx, 'dy': position.dy},
    'part': part.toJson(),
    'rotationAngle': rotationAngle,
    'flipHorizontal': flipHorizontal,
    'flipVertical': flipVertical,
    'customWidth': customWidth,
    'customHeight': customHeight,
    'properties': properties,
  };

  factory fromJson(Map<String, dynamic> json) {
    final pos = json['position'] as Map<String, dynamic>;
    return ComponentInstance(
      key: ValueKey<String>(json['id'] as String),
      position: Offset((pos['dx'] as num).toDouble(), (pos['dy'] as num).toDouble()),
      part: PartModel.fromJson(json['part'] as Map<String, dynamic>),
      rotationAngle: (json['rotationAngle'] as num?)?.toDouble() ?? 0.0,
      flipHorizontal: json['flipHorizontal'] as bool? ?? false,
      flipVertical: json['flipVertical'] as bool? ?? false,
      customWidth: (json['customWidth'] as num?)?.toDouble(),
      customHeight: (json['customHeight'] as num?)?.toDouble(),
      properties: json['properties'] != null
          ? Map<String, dynamic>.from(json['properties'] as Map)
          : null,
    );
  }
}
