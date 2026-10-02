/*
 * Fade — on a Raspberry Pi Pico W.
 *
 * An LED on GP21 that brightens and dims, smoothly, from a pin that can only
 * be on or off. analogWrite() does it with PWM: the pin switches thousands of
 * times a second, and the share of each cycle it spends on — the duty — is
 * how bright the LED looks. 0 is always off, 255 always on, 128 on half the
 * time.
 *
 * Every GPIO on the RP2040 can do PWM, unlike the Uno, where only the pins
 * marked ~ can.
 */

const int LED = 21;

void setup() {
  pinMode(LED, OUTPUT);
}

void loop() {
  for (int level = 0; level <= 255; level += 5) {
    analogWrite(LED, level);
    delay(20);
  }
  for (int level = 255; level >= 0; level -= 5) {
    analogWrite(LED, level);
    delay(20);
  }
}
