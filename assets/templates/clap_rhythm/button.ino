class Button {
public:

  typedef void (*Callback)(int);

  Button(int pin, int id)
    : pin_(pin), id_(id) {
  }

  void init() {
    pinMode(pin_, INPUT_PULLUP);
  }

  void setSinglePressCallback(Callback callBack) {
    _singlePressCallback = callBack;
  }

  void setDoublePressCallback(Callback callBack) {
    _doublePressCallback = callBack;
  }

  void setLongPressCallback(Callback callBack) {
    _longPressCallback = callBack;
  }

  void update() {

    unsigned long currentTime = millis();
    bool currentReading = digitalRead(pin_) == LOW;

    if (currentReading != _lastButtonPressState) {
      _lastDebounceTime = currentTime;
      String s = "Btn "; s += id_; s += " raw: "; s += currentReading;
      Serial.println(s);
    }

    if ((currentTime - _lastDebounceTime) > _DEBOUNCE_DURATION) {
      if (currentReading != _debouncedState) {
        _debouncedState = currentReading;
        String s2 = "Btn "; s2 += id_; s2 += " dbg: "; s2 += _debouncedState;
        Serial.println(s2);
      }
    }

    _lastButtonPressState = currentReading;

    bool isPressed = _debouncedState;

    switch (_currentState) {
      case BUTTON_IDLE:

        if (isPressed) {
          _pressCount = 0;
          _pressStartTime = currentTime;
          _currentState = BUTTON_PRESSED;
          _longPressTriggered = false;
        }
        break;

      case BUTTON_PRESSED:

        // Increase counter if relased in short time means a single press
        if (!isPressed) { 
          _pressCount++;
          _pressStartTime = currentTime;
          _currentState = BUTTON_RELEASED;
        }

        else if (currentTime - _pressStartTime > _LONG_PRESS_DURATION && _longPressCallback) {
          _longPressCallback(id_);
          _longPressTriggered = true;
          _currentState = BUTTON_WAIT_RELEASE;
        }
        break;

      case BUTTON_RELEASED:

        if (isPressed) {
          // Another press detected
          _pressStartTime = currentTime;
          _currentState = BUTTON_PRESSED;
        }

        if (currentTime - _pressStartTime > _DOUBLE_PRESS_WINDOW) {
          // Timeout - execute appropriate callback

          if (_pressCount == 1 && _singlePressCallback) {
            _singlePressCallback(id_);
          }

          else if (_pressCount == 2 && _doublePressCallback) {
            _doublePressCallback(id_);
          }

          _currentState = BUTTON_IDLE;
        }
        break;

      case BUTTON_WAIT_RELEASE:

        if (!isPressed) {
          _currentState = BUTTON_IDLE;
        }
        break;
    }
  }

private:

  enum _State {
    BUTTON_IDLE,
    BUTTON_PRESSED,
    BUTTON_RELEASED,
    BUTTON_WAIT_RELEASE
  };

  _State _currentState = BUTTON_IDLE;

  const int pin_;
  const int id_;

  const unsigned long _DEBOUNCE_DURATION = 5;
  const unsigned long _DOUBLE_PRESS_WINDOW = 400;
  const unsigned long _LONG_PRESS_DURATION = 800;

  bool _longPressTriggered = false;
  bool _lastButtonPressState = false;
  bool _debouncedState = false;

  int _pressCount = 0;
  unsigned long _lastDebounceTime = 0;
  unsigned long _pressStartTime = 0;

  Callback _singlePressCallback = nullptr;
  Callback _doublePressCallback = nullptr;
  Callback _longPressCallback = nullptr;
};