import 'syntax_utils.dart';

final langPdl = buildSyntaxMode(
  name: 'PDL',
  aliases: ['pdl'],
  keywords: {
    // Every directive the parser knows (see `PdlParser`).
    'keyword': [
      'PART',
      'ID',
      'ALIAS',
      'CATEGORY',
      'DESCRIPTION',
      'SIZE',
      'ORIGIN',
      'SVG',
      'PAINTER',
      'LOGIC',
      'CONFIGURATION',
      'PINS',
      'PROPERTIES',
      'STATE',
      'BEHAVIOR',
      'VISUALS',
      'PHYSICS',
    ],
    // VISUALS shapes, then PHYSICS types.
    'type': [
      'RECT',
      'CIRCLE',
      'LINE',
      'resistor',
      'capacitor',
      'diode',
      'voltageSource',
      'npn',
      'pnp',
      'nmos',
      'pmos',
      'npnDarlington',
      'pnpDarlington',
      'rgbLed',
      'ledArray',
      'spdt',
    ],
    'built_in': ['true', 'false', 'pin'],
  },
);
