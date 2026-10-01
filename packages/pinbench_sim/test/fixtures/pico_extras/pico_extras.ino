// Fixture for pico_board_test.dart: what a Pico sketch reaches beyond the
// basics — Wire moved off its default pins, the on-chip temperature sensor,
// the VSYS sense input, and typed input arriving on Serial1.
//
// Rebuild after editing (from this folder), with the arduino-pico core
// (rp2040:rp2040) installed:
//   arduino-cli compile --fqbn rp2040:rp2040:rpipico --output-dir out pico_extras.ino
//   arm-none-eabi-objcopy -I binary -O ihex --change-addresses 0x10000000 \
//     out/pico_extras.ino.bin pico_extras.hex && rm -rf out

#include <Wire.h>

void setup() {
  Serial1.begin(115200);

  Wire.setSDA(8); // I2C0 on GP8/GP9 instead of GP4/GP5
  Wire.setSCL(9);
  Wire.begin();
  Wire.beginTransmission(0x3C); // an empty write: a scanner's probe
  Serial1.print("probe ");
  Serial1.println(Wire.endTransmission());
  Wire.beginTransmission(0x3C);
  Wire.write(0x07);
  Serial1.print("i2c ");
  Serial1.println(Wire.endTransmission());

  Serial1.print("temp ");
  Serial1.println((int)analogReadTemp());
  Serial1.print("vsys ");
  Serial1.println(analogRead(29)); // GP29: VSYS through a 3:1 divider
  Serial1.println("READY");
}

void loop() {
  while (Serial1.available()) {
    Serial1.print("got ");
    Serial1.println((char)Serial1.read());
  }
}
