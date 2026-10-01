// Fixture for pico_board_test.dart: one sketch touching every pin facility
// the Pico board emulator reports — a digital output, PWM, a pulled-up input,
// the ADC, both serial ports, I2C (written and probed) and the on-board LED
// — then idling in delay() so the core sleeps in WFI, as most sketches do.
//
// Rebuild after editing (from this folder), with the arduino-pico core
// (rp2040:rp2040) installed. Its `.bin` becomes Intel HEX at 0x10000000,
// exactly what the app's compilers do:
//   arduino-cli compile --fqbn rp2040:rp2040:rpipico --output-dir out pico.ino
//   arm-none-eabi-objcopy -I binary -O ihex --change-addresses 0x10000000 \
//     out/pico.ino.bin pico.hex && rm -rf out

#include <Wire.h>

int loops = 0;

void setup() {
  Serial.begin(115200);
  Serial1.begin(115200);
  pinMode(15, OUTPUT);
  pinMode(14, INPUT_PULLUP);
  pinMode(LED_BUILTIN, OUTPUT);
  analogWrite(16, 64); // 25% of the default 0-255 range

  Wire.begin(); // I2C0 on GP4/GP5
  Wire.beginTransmission(0x3C);
  Wire.write(0x42);
  Serial1.print("i2c ");
  Serial1.println(Wire.endTransmission());

  // An empty write, as every I2C scanner sends. arduino-pico cannot make one
  // with the I2C hardware, so it bit-bangs the address on GP4/GP5 instead.
  Wire.beginTransmission(0x3C);
  Serial1.print("probe ");
  Serial1.println(Wire.endTransmission());
}

void loop() {
  digitalWrite(15, HIGH);
  digitalWrite(LED_BUILTIN, HIGH);
  delay(50);
  digitalWrite(15, LOW);
  digitalWrite(LED_BUILTIN, LOW);
  Serial1.print("a0=");
  Serial1.print(analogRead(A0));
  Serial1.print(" btn=");
  Serial1.println(digitalRead(14));
  Serial.print("usb ");
  Serial.println(loops);
  while (Serial.available()) {
    Serial1.print("echo ");
    Serial1.println((char)Serial.read());
  }
  if (++loops == 5) Serial1.println("DONE");
  delay(50);
}
