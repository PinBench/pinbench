// Blink on a Raspberry Pi Pico W: an LED on GP16, and the board's own LED.
const int LED = 16;

void setup() {
  pinMode(LED, OUTPUT);
  pinMode(LED_BUILTIN, OUTPUT);
}

void loop() {
  Serial.println("Hello from the Pico W");
  digitalWrite(LED, HIGH);
  digitalWrite(LED_BUILTIN, HIGH);
  delay(500);
  digitalWrite(LED, LOW);
  digitalWrite(LED_BUILTIN, LOW);
  delay(500);
}
