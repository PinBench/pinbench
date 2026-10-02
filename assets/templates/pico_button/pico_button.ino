/*
 * Button — on a Raspberry Pi Pico W.
 *
 * A push button between GP15 and GND, and an LED on GP21 that lights while
 * it is held. No resistor on the button: INPUT_PULLUP switches on a resistor
 * inside the RP2040 that holds GP15 at 3.3 V, so the pin reads HIGH until the
 * button connects it to GND and it reads LOW. Pressed is LOW — the opposite
 * of what most people expect, and the reason the comparison below says LOW.
 *
 * Serial only prints when the state changes. Printing every time round the
 * loop would bury the one line that matters under thousands that don't.
 */

const int BUTTON = 15;
const int LED = 21;

bool wasPressed = false;

void setup() {
  pinMode(BUTTON, INPUT_PULLUP);
  pinMode(LED, OUTPUT);
}

void loop() {
  bool pressed = digitalRead(BUTTON) == LOW;
  digitalWrite(LED, pressed ? HIGH : LOW);

  if (pressed != wasPressed) {
    Serial.println(pressed ? "pressed" : "released");
    wasPressed = pressed;
  }
  delay(10);
}
