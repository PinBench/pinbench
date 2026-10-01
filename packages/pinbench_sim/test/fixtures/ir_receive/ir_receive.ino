// The IRremote library's receive example, cut to what the test reads: every
// decoded press printed as its NEC command. Compiled to ir_receive.hex with
// IRremote 4.7.1 for an Uno (arduino:avr:uno).
#include <IRremote.hpp>

void setup() {
  Serial.begin(9600);
  IrReceiver.begin(2);
}

void loop() {
  if (IrReceiver.decode()) {
    Serial.print("CMD 0x");
    Serial.println(IrReceiver.decodedIRData.command, HEX);
    IrReceiver.resume();
  }
}
