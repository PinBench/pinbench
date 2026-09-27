#define SOUND_PIN 3 // Digital output of the KY-037 sensor
#define BUZZER_PIN 4 // Piezo buzzer

const int MAX_CLAPS = 20;
unsigned long intervals[MAX_CLAPS];
int clapCount = 0;

unsigned long lastClapTime = 0;
bool recording = false;
int lastSoundState = LOW;

void setup() {
  Serial.begin(9600);
  pinMode(SOUND_PIN, INPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  Serial.println("Rhythm Recorder Started.");
  Serial.println("Make some noise (e.g. clap) to start recording!");
}

void loop() {
  int soundState = digitalRead(SOUND_PIN);
  unsigned long currentTime = millis();

  // Edge detection: only trigger when transitioning from LOW to HIGH
  if (soundState == HIGH && lastSoundState == LOW) {
    if (!recording) {
      // First clap: start recording
      recording = true;
      clapCount = 0;
      lastClapTime = currentTime;
      Serial.println("Recording started... Clap the rhythm!");
    } else {
      // Subsequent claps (with 100ms debounce to prevent echo/bounce)
      if (currentTime - lastClapTime > 100 && clapCount < MAX_CLAPS) {
        intervals[clapCount] = currentTime - lastClapTime;
        clapCount++;
        lastClapTime = currentTime;
        
        Serial.print("Clap ");
        Serial.println(clapCount);
      }
    }
  }
  
  lastSoundState = soundState;

  // Stop recording if 3 seconds have passed since the last clap
  if (recording && (currentTime - lastClapTime > 3000)) {
    recording = false;
    Serial.println("Recording stopped. Playing back rhythm...");
    
    // Playback
    // Play the first clap (simulating a phone keypad tone)
    tone(BUZZER_PIN, 1336, 80);

    for (int i = 0; i < clapCount; i++) {
      // Delay by the exact recorded interval
      delay(intervals[i]);
      
      tone(BUZZER_PIN, 1336, 80);
    }
    
    // Wait for the last tone to finish
    delay(150);
    
    Serial.println("Playback finished. Waiting for new rhythm...");
    clapCount = 0;
  }
}