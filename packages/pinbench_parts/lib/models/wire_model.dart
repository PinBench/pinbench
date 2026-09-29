import 'package:flutter/widgets.dart';

import '../id_generator.dart';
import 'port_model.dart';
import '../painting/part_palette.dart';

/// A wire connecting two ports on the canvas, with optional [bendPoints] for
/// manual routing and a display [color]. Identified by a process-unique [id]
/// (see [generateId]).
class WireModel {
  final String id;
  final PortLocation start;
  final PortLocation end;
  final List<Offset> bendPoints;
  final Color color;

  WireModel({
    String? id,
    required this.start,
    required this.end,
    this.bendPoints = const [],
    this.color = PartPalette.green,
  }) : id = id ?? IdGenerator.generate('wire');

  /// Generates a process-unique wire id. Delegates to [IdGenerator].
  static String generateId() => IdGenerator.generate('wire');

  WireModel copyWith({
    String? id,
    PortLocation? start,
    PortLocation? end,
    List<Offset>? bendPoints,
    Color? color,
  }) => WireModel(
    id: id ?? this.id,
    start: start ?? this.start,
    end: end ?? this.end,
    bendPoints: bendPoints ?? this.bendPoints,
    color: color ?? this.color,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'start': start.toJson(),
    'end': end.toJson(),
    'bendPoints': bendPoints.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
    'color': color.toARGB32(),
  };

  factory WireModel.fromJson(Map<String, dynamic> json) => WireModel(
    id: json['id'] as String,
    start: PortLocation.fromJson(json['start'] as Map<String, dynamic>),
    end: PortLocation.fromJson(json['end'] as Map<String, dynamic>),
    bendPoints: (json['bendPoints'] as List).map((p) {
      final pm = p as Map<String, dynamic>;
      return Offset((pm['dx'] as num).toDouble(), (pm['dy'] as num).toDouble());
    }).toList(),
    color: Color(json['color'] as int),
  );
}
