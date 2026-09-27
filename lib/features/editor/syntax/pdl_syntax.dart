import 'syntax_utils.dart';

final langPdl = buildSyntaxMode(
  name: 'PDL',
  aliases: ['pdl'],
  keywords: {
    'keyword': [
      'PART',
      'SIZE',
      'CENTER',
      'SVG',
      'STATE',
      'PINS',
      'PHYSICS',
      'SPICE',
      'PROPERTIES',
      'SHAPES',
    ],
    'type': ['circle', 'rect', 'line', 'resistor', 'diode', 'voltage_source'],
    'built_in': ['true', 'false', 'pin'],
  },
);
