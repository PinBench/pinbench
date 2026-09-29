import 'syntax_utils.dart';

final langCdl = buildSyntaxMode(
  name: 'CDL',
  aliases: ['cdl'],
  keywords: {
    'keyword': ['Circuit', 'Wire'],
    'type': [
      // Component type tokens written before `{` in the element form.
      'ArduinoUno',
      'LED',
      'Resistor',
      'PushButton',
      'PiezoBuzzer',
      'MicSensor',
      'HalfBreadboard',
      'FullBreadboard',
      'Potentiometer',
      'Capacitor',
      'ServoMotor',
      'OLEDDisplay',
    ],
    'built_in': [
      'true',
      'false',
      'green',
      'red',
      'blue',
      'yellow',
      'cyan',
      'pink',
      'orange',
      'black',
      'white',
      'transparent',
    ],
  },
);
