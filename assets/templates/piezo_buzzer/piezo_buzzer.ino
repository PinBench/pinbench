void setup() { pinMode(8, OUTPUT); }

void loop() {
  Serial.println("Running Piezo Buzzer Template Code");
  tone(8, 85);
  delay(1000);
  noTone(8);
  delay(1000);
}