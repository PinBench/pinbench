#define SOUND_PIN 2
#define BUZZER_PIN 3

const int MAX_RHYTHMS = 3;
const int MAX_CLAPS = 10;
const long unsigned CLAP_DURATION = 170;

struct Rhythm {
  int intervalCount;
  unsigned long intervals[MAX_CLAPS - 1];
};

Rhythm rhythms[MAX_RHYTHMS];

void setup() {

  Serial.begin(9600);

  pinMode(SOUND_PIN, INPUT);
  pinMode(BUZZER_PIN, OUTPUT);

  ledSetup();
  buttonSetup();

  loadRhythmsFromEEPROM();
}

void loop() {
  ledLoop();
  buttonLoop();
  rhythmLoop();
  playbackLoop();
}