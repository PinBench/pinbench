// Fixture for sensor_sketches_test.dart: the four I2C sensor parts read
// through the libraries tutorials use, then two analog ones through the ADC,
// each result reported over Serial.
//
// Rebuild after editing (from this folder), with these libraries installed:
// Adafruit MPU6050, BH1750 (claws), RTClib, Adafruit AHTX0.
//   arduino-cli compile --fqbn arduino:avr:uno --output-dir . sensors.ino
//   mv sensors.ino.hex sensors.hex && rm -f sensors.ino.*

#include <Wire.h>
#include <Adafruit_MPU6050.h>
#include <BH1750.h>
#include <RTClib.h>
#include <Adafruit_AHTX0.h>

Adafruit_MPU6050 mpu;
BH1750 light;
RTC_DS1307 rtc;
Adafruit_AHTX0 aht;

void setup() {
  Serial.begin(115200);
  Wire.begin();
  sensors_event_t a, b, c;

  // AD0 is tied high in the test circuit, so the IMU is at 0x69 and the
  // clock can have 0x68.
  Serial.print("MPU=");
  Serial.println(mpu.begin(0x69));
  mpu.getEvent(&a, &b, &c);
  Serial.print("AZ=");
  Serial.println(a.acceleration.z, 1);

  Serial.print("BH=");
  Serial.println(light.begin());
  delay(200);
  Serial.print("LUX=");
  Serial.println(light.readLightLevel(), 0);

  Serial.print("RTC=");
  Serial.println(rtc.begin());
  Serial.print("RUN=");
  Serial.println(rtc.isrunning());
  rtc.adjust(DateTime(2026, 9, 30, 12, 34, 56));
  DateTime now = rtc.now();
  Serial.print("NOW=");
  Serial.print(now.year());
  Serial.print('-');
  Serial.print(now.month());
  Serial.print('-');
  Serial.print(now.day());
  Serial.print(' ');
  Serial.print(now.hour());
  Serial.print(':');
  Serial.print(now.minute());
  Serial.print(':');
  Serial.println(now.second());
  Serial.print("RUN=");
  Serial.println(rtc.isrunning());

  Serial.print("AHT=");
  Serial.println(aht.begin());
  aht.getEvent(&a, &b);
  Serial.print("RH=");
  Serial.println(a.relative_humidity, 1);
  Serial.print("T=");
  Serial.println(b.temperature, 1);

  // Read last: the ADC only sees the analog solve once a frame has run.
  Serial.print("A0=");
  Serial.println(analogRead(A0));
  Serial.print("A1=");
  Serial.println(analogRead(A1));

  Serial.println("DONE");
}

void loop() {}
