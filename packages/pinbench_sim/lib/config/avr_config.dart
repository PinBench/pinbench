class AVRConfig {
  static const clockFrequency = 16000000;
  static const targetFps = 60;
  static const int frameBudgetMs = 1000 ~/ targetFps; // 16
  static const int cyclesPerFrame = clockFrequency ~/ targetFps; // 266,666
  static const digitalPinCount = 14; // pins 0–13
  static const analogPinOffset = 14; // A0 maps to pin 14
  static const analogPinCount = 6; // A0–A5

  // Digital pins exposed to the SPICE circuit as driven voltage sources.
  // Includes the PWM-capable pins 3/5/6 (Timer0/2) alongside 9/10/11 (Timer1/2)
  // so analogWrite() on any of them drives an attached LED.
  static const spicePins = ['3', '5', '6', '8', '9', '10', '11', '12', '13'];

  // Analog input channels (A0–A5) read back from the circuit into the ADC,
  // so analogRead() reflects external voltages (dividers, sensors, pots).
  static const analogInputPorts = ['A0', 'A1', 'A2', 'A3', 'A4', 'A5'];
}
