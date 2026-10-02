/*
 * OLED display — on a Raspberry Pi Pico W.
 *
 * A 0.96" SSD1306 module on the I2C bus. Four wires: GND and VCC for power,
 * SDA to GP26 and SCL to GP27 for the data, and power from 3V3(OUT) — these
 * modules run happily on 3.3 V. All four are on one edge of the board.
 *
 * The RP2040 has two I2C blocks, and neither is fixed to a pair of pins: any
 * even GPIO can be SDA and the odd one beside it SCL. GP26 and GP27 belong to
 * the second block, which the sketch knows as Wire1 — two lines in setup()
 * put it on those pins, something an Uno simply cannot do.
 *
 * The one idea worth taking away is that drawing and showing are separate.
 * Every print and shape goes into a buffer in the Pico's memory; nothing
 * reaches the glass until display() sends the whole picture across at once.
 * That is why the screen never flickers halfway through a redraw — and why a
 * sketch that draws beautifully and forgets display() shows nothing at all.
 */

#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// 128 x 64 pixels, on the Wire1 bus, with no reset pin — which is how the
// 4-pin modules are built, so -1 is what they always want.
Adafruit_SSD1306 display(128, 64, &Wire1, -1);

int count = 0;

void setup() {
  // Before Wire starts: the bus goes where the wires are.
  Wire1.setSDA(26);
  Wire1.setSCL(27);

  // 0x3C is the address on nearly every module. The rest answer on 0x3D, and
  // there is a jumper on the back that picks — if the screen stays dark, this
  // is the first thing to check, here and on real hardware alike.
  display.begin(SSD1306_SWITCHCAPVCC, 0x3C);

  // The library draws its own logo on startup. Wipe it before drawing.
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
}

void loop() {
  // 1. Start from a blank buffer, or the last frame shows through this one.
  display.clearDisplay();

  // 2. Draw. The cursor is in pixels from the top-left, and text size is a
  //    whole-number multiple of the 6 x 8 font — so size 2 is 12 x 16.
  display.setTextSize(2);
  display.setCursor(0, 0);
  display.println(F("Hello!"));

  display.setTextSize(1);
  display.setCursor(0, 24);
  display.print(F("counting: "));
  display.println(count);

  // 3. Send the buffer to the screen. Nothing above this line was visible.
  display.display();

  count++;
  delay(500);
}
