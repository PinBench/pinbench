#define BUTTON_0_PIN 7
#define BUTTON_1_PIN 6
#define BUTTON_2_PIN 5

const int _BUTTON_COUNT = 3;

Button _buttons[_BUTTON_COUNT] = {
  Button(BUTTON_0_PIN, 0),
  Button(BUTTON_1_PIN, 1),
  Button(BUTTON_2_PIN, 2)
};

void buttonSetup() {
  for (int i = 0; i < _BUTTON_COUNT; i++) {
    _buttons[i].init();
    _buttons[i].setSinglePressCallback(onSinglePress);
    _buttons[i].setDoublePressCallback(onDoublePress);
    _buttons[i].setLongPressCallback(onLongPress);
  }
}


void buttonLoop() {
  for (int i = 0; i < _BUTTON_COUNT; i++) {
 
    _buttons[i].update();
  }
}

void onSinglePress(int button) {

  String str = "Button pressed: ";
  str += button;
  Serial.println(str);

  playRhythm(button);
}

void onDoublePress(int button) {

  String str = "Button double pressed: ";
  str += button;
  Serial.println(str);

  startDetection();
}

void onLongPress(int button) {

  String str = "Button long pressed: ";
  str += button;
  Serial.println(str);

  startRecording(button);
}