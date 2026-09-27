// An LED driven through an undersized series resistor:
// pin 13 -> 100 Ω -> LED -> GND.
//
// 100 Ω lets roughly 27.8 mA through the LED. That is over a 5 mm red LED's
// 20 mA rating, and most of the ATmega328P's 40 mA per-pin absolute maximum —
// the classic beginner mistake, and one you cannot see in a simulator that
// treats resistors as decoration.
//
// Try it: select the resistor on the canvas and change its Resistance to 220.
// The solved current drops to about 15 mA and the LED visibly dims, because
// brightness follows current. At 100 Ω it is also drawn with a red cross for
// exceeding its rating. If a simulator shows you the same LED both times, it
// is not solving the circuit.
//
// The LED is held steadily on rather than blinking, so the current settles to
// one value.

const int kLedPin = 13;

void setup() {
  pinMode(kLedPin, OUTPUT);
  digitalWrite(kLedPin, HIGH);
}

void loop() {
  // Nothing to do — the point of this sketch is the circuit, not the code.
}
