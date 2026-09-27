const unsigned long _RHYTHM_TIMEOUT = 3000;

const float _RHYTHM_TOLERANCE = 0.25f;  // 25% Error tolerance

enum RhythmState {
  RHYTHM_IDLE,
  RHYTHM_RECORDING,
  RHYTHM_DETECTING,
  RHYTHM_RECOGNIZING,
};

RhythmState _rhythmState = RHYTHM_IDLE;

int _slot = -1;
int _rhythmLedPin = -1;
Rhythm _recordingRhythm;

unsigned long _startTime = 0;
unsigned long _lastClapTime = 0;
bool _firstClapDetected = false;

void rhythmLoop() {
  if (_rhythmState == RHYTHM_IDLE) return;

  switch (_rhythmState) {
    case RHYTHM_RECORDING:
    case RHYTHM_DETECTING:
      recordRhythm();
      break;
    case RHYTHM_RECOGNIZING:
      recognizeRhythm();
      break;
  }
}

void startRecording(int slot) {
  _slot = slot;
  _startTime = millis();
  _rhythmLedPin = getLEDPin(slot);
  _recordingRhythm.intervalCount = 0;
  _firstClapDetected = false;
  Serial.println("Rhythm recording start");
  _rhythmState = RHYTHM_RECORDING;
}

void stopRecording() {

  setLedOff();

  if (_rhythmState == RHYTHM_DETECTING) {
    _rhythmState = RHYTHM_RECOGNIZING;
    return;
  }

  _rhythmState = RHYTHM_IDLE;
  saveRhythm();
}

void startDetection() {

  startLedCycle();
  _startTime = millis();
  _recordingRhythm.intervalCount = 0;
  _firstClapDetected = false;
  Serial.println("Rhythm detection start");
  _rhythmState = RHYTHM_DETECTING;
}

void stopDetection() {
  _rhythmState = RHYTHM_IDLE;
  setLedOff();
}

void saveRhythm() {

  rhythms[_slot] = _recordingRhythm;
  saveRhythmToEEPROM(_slot, _recordingRhythm);
}

void recordRhythm() {

  unsigned long currentTime = millis();

  if (!_firstClapDetected && (currentTime - _startTime > _RHYTHM_TIMEOUT)) {
    Serial.println("Rhythm timeout reached (no claps detected), nothing saved");
    stopRecording();
    return;
  }

  if (_firstClapDetected) {

    if (_recordingRhythm.intervalCount >= MAX_CLAPS - 1) {
      Serial.println("Max claps reached, rhythm saved");
      stopRecording();
      return;
    }

    else if (currentTime - _lastClapTime > _RHYTHM_TIMEOUT) {
      Serial.println("Rhythm timeout reached (after claps), rhythm saved");
      stopRecording();
      return;
    }
  }

  static bool prevClapState = false;
  bool currentClapState = digitalRead(SOUND_PIN) == HIGH;

  if (currentClapState && !prevClapState) {

    if (!_firstClapDetected) {
      _firstClapDetected = true;
      _lastClapTime = currentTime;
      _recordingRhythm.intervalCount++;
      _recordingRhythm.intervals[0] = 0;
      Serial.println("Clap 0 at interval 0");
    }

    else if (currentTime - _lastClapTime > CLAP_DURATION) {

      int count = _recordingRhythm.intervalCount;
      int interval = currentTime - _lastClapTime;
      
      _lastClapTime = currentTime;

      _recordingRhythm.intervalCount++;
      _recordingRhythm.intervals[count] = interval;

      String str = "Clap ";
      str += count;
      str += " interval ";
      str += interval;

      Serial.println(str);
    }
  }
  
  prevClapState = currentClapState;
}

void recognizeRhythm() {

  unsigned long currentTime = millis();

  int count = _recordingRhythm.intervalCount;

  if (currentTime - _startTime > _RHYTHM_TIMEOUT && count > 0) {

    int matchedSlot = matchRhythm();

    if (matchedSlot != -1) {

      String str = "Matched rhythm: ";
      str += matchedSlot;

      Serial.println("Rhythm detection stop");
      Serial.println(str);

      stopDetection();
      playRhythm(matchedSlot);
      return;
    }
  }

  Serial.println("Rhythm detection stop, no match found");

  stopDetection();
  startLedBlink();
}

int matchRhythm() {

  if (_recordingRhythm.intervalCount < 1) return -1;

  for (int i = 0; i < MAX_RHYTHMS; i++) {

    Rhythm rhythm = rhythms[i];

    if (rhythm.intervalCount < 1 || rhythm.intervalCount != _recordingRhythm.intervalCount) continue;

    bool match = true;

    for (int j = 1; j < _recordingRhythm.intervalCount; j++) {  // Start from 1 because first interval is always 0

      long x = rhythm.intervals[j];
      long y = _recordingRhythm.intervals[j];

      if (y == 0) {  // Avoid division by zero
        if (x != 0) {
          match = false;
          break;
        }
        continue;
      }

      float errorRatio = abs(x - y) / (float)y;

      String str = "ErrorRatio ";
      str += errorRatio;
      str += " at ";
      str += j;

      Serial.println(str);

      if (errorRatio > _RHYTHM_TOLERANCE) {
        match = false;
        break;
      }
    }

    if (match) return i;
  }

  return -1;
}