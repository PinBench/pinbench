// Fixture for i2c_read_test.dart: reads a served I2C device the way real
// sensor libraries do, and reports each result over Serial.
//
// Rebuild after editing (from this folder):
//   arduino-cli compile --fqbn arduino:avr:uno --output-dir . i2c_read.ino
//   mv i2c_read.ino.hex i2c_read.hex && rm -f i2c_read.ino.*

#include <Wire.h>

const uint8_t DEVICE = 0x68;   // served by the test
const uint8_t ABSENT = 0x50;   // nothing on the bus

// Write the register pointer, then read [count] bytes after a repeated start.
uint8_t readRegisters(uint8_t reg, uint8_t *out, uint8_t count) {
  Wire.beginTransmission(DEVICE);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return 0;
  uint8_t got = Wire.requestFrom(DEVICE, count);
  for (uint8_t i = 0; i < got; i++) out[i] = Wire.read();
  return got;
}

void printHex(const char *label, const uint8_t *bytes, uint8_t count) {
  Serial.print(label);
  for (uint8_t i = 0; i < count; i++) {
    if (bytes[i] < 0x10) Serial.print('0');
    Serial.print(bytes[i], HEX);
  }
  Serial.println();
}

void setup() {
  Serial.begin(115200);
  Wire.begin();
  uint8_t buf[6];

  // One register, like a WHO_AM_I check.
  printHex("WHO=", buf, readRegisters(0x75, buf, 1));

  // Six consecutive registers in one read, like an accelerometer sample.
  printHex("ACC=", buf, readRegisters(0x3B, buf, 6));

  // Write a register, then read it back, like setting an RTC.
  Wire.beginTransmission(DEVICE);
  Wire.write(0x6B);
  Wire.write(0x5A);
  Wire.endTransmission();
  printHex("BACK=", buf, readRegisters(0x6B, buf, 1));

  // An address with nothing behind it is not acknowledged.
  Wire.beginTransmission(ABSENT);
  Serial.print("ABSENT=");
  Serial.println(Wire.endTransmission());

  Serial.println("DONE");
}

void loop() {}
