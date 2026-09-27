void setup() { pinMode(8, OUTPUT); }

void loop() {
  Serial.println("Running Perizo Buzzer Templae Code");
  tone(8, 85);
  delay(1000);
  noTone(8);
  delay(1000);
}