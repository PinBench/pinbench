// Voltage divider — two 10 kΩ resistors between pin 8 and ground, with A0 on
// the midpoint. The most common analog circuit there is.
//
// Expected reading: about 510, not 1023.
//
// 510 is what a solved circuit gives you: the divider halves the 5 V, and the
// ~40 Ω of resistance inside the output pin pulls the midpoint a few
// millivolts below a clean 2.500 V. A simulator that ignores resistors reads
// 1023 instead, because A0 ends up connected straight to the driven pin.
//
// Try it: change either resistor, on the canvas or in the .cdl, and the
// reading should track 5 V x Rbottom / (Rtop + Rbottom + 40). Swap the bottom
// one to 20k and it reads about 681; make them 20k over 10k and it reads 341.

const int kDividerTop = 8;

void setup() {
  Serial.begin(9600);
  pinMode(kDividerTop, OUTPUT);
  digitalWrite(kDividerTop, HIGH);  // drive the top of the divider to 5 V

  // The analog solver runs a frame behind the first instruction, so reading
  // A0 immediately would print one misleading 0 before the real value.
  delay(250);
}

void loop() {
  const int raw = analogRead(A0);

  // Integer millivolts rather than a float: printing a double through this
  // emulator's USART renders as "inf", and no part of this demo needs
  // floating point.
  const long millivolts = (long)raw * 5000L / 1023L;

  Serial.print("analogRead(A0) = ");
  Serial.print(raw);
  Serial.print("  ->  ");
  Serial.print(millivolts / 1000);
  Serial.print('.');
  const int frac = (int)(millivolts % 1000);
  if (frac < 100) Serial.print('0');
  if (frac < 10) Serial.print('0');
  Serial.print(frac);
  Serial.println(" V");

  delay(1000);
}
