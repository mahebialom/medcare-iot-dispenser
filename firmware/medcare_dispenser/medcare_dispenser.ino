#include <credentials.h> //importing user private data from another
#include <Arduino.h>
#include <Wire.h>
#include <SPI.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <Preferences.h>
#include <Stepper.h>
#include <FirebaseClient.h>
#include <ArduinoJson.h>
#include <RTClib.h>
#include <ESP32Servo.h>
#include <DFRobotDFPlayerMini.h>
#include <MFRC522.h>
#include <time.h>


//  STEPPER PINS
#define STEP_PIN_IN1 26
#define STEP_PIN_IN2 27
#define STEP_PIN_IN3 14
#define STEP_PIN_IN4 12

//  OTHER PINS
#define PIN_SERVO 25
#define PIN_IR 34
#define PIN_DF_RX 16
#define PIN_DF_TX 17
#define PIN_BUZZER 4
#define PIN_RFID_SS 5
#define PIN_RFID_RST 33
#define PIN_BUTTON 0

//  STEPPER CONFIG
#define STEPS_PER_REV 2048
#define STEPS_PER_SLOT 410
#define STEPPER_RPM 5
#define NUM_SLOTS 5

//  360° CONTINUOUS SERVO CONSTANTS
#define SERVO_STOP 1500
#define SERVO_OPEN_SPEED 1350
#define SERVO_CLOSE_SPEED 1650
#define SERVO_RUN_TIME 1470
#define SERVO_CLOSE_TIME 1400

//  FC-51 IR SENSOR
#define FC51_BLOCKED LOW
#define FC51_CLEAR HIGH

//  PERIOD SCHEDULING
#define PERIOD_MORNING 0  //  8:00 AM – 11:59 AM
#define PERIOD_LUNCH 1    // 12:00 PM –  3:59 PM
#define PERIOD_NIGHT 2    //  6:00 PM – 10:59 PM
#define PERIOD_EXACT 3    // Specific hour:minute


#define MAX_SCHEDULES_PER_SLOT 3

//  TIMING
#define FINGER_SAFETY_MS 2000
#define RETURN_WAIT_MS 90000
#define RETURN_NAG_MS 30000
#define MISSED_NAG_MS 30000
#define LONG_PRESS_MS 3000
#define SHORT_PRESS_MIN 100
#define STOCK_WARN_LOW 7
#define STOCK_WARN_CRITICAL 3

//  AUDIO TRACK NUMBERS
#define AUDIO_READY 1
#define AUDIO_ROTATING 2
#define AUDIO_TAKE_NOW 3
#define AUDIO_TAKEN 4
#define AUDIO_RETURN_STRIP 5
#define AUDIO_SAFETY_CLOSING 6
#define AUDIO_LID_CLOSED 7
#define AUDIO_ALL_DONE 8
#define AUDIO_RFID_CORRECT 9
#define AUDIO_RFID_WRONG 10
#define AUDIO_NAME_BASE 11
#define AUDIO_REFILL_ENTER 16
#define AUDIO_REFILL_OPEN 17
#define AUDIO_REFILL_NEXT 18
#define AUDIO_REFILL_EXIT 19
#define AUDIO_LOW_STOCK 20
#define AUDIO_REMINDER 21
#define AUDIO_NOT_RETURNED 22
#define AUDIO_NEXT_MEDICINE 23
#define AUDIO_QUEUE_BASE 24
#define AUDIO_PERIOD_MORNING 29
#define AUDIO_PERIOD_LUNCH 30
#define AUDIO_PERIOD_NIGHT 31
#define AUDIO_ALREADY_TAKEN 32
#define AUDIO_NOTHING_DUE 33
#define AUDIO_MISSED_PERIOD 34

//PERIOD DEFINE
const uint8_t PERIOD_START[3] = { 8, 12, 17 };
const uint8_t PERIOD_END[3] = { 11, 16, 23 };
const uint8_t PERIOD_END_HOUR[3] = { 11, 16, 23 };
const char* PERIOD_NAMES[4] = { "Morning", "Lunch", "Night", "Exact" };

//  SCHEDULE ENTRY
struct ScheduleEntry {
  uint8_t period;
  uint8_t hour;
  uint8_t minute;
  bool active;
  bool takenToday;
};

//  SLOT DATA STRUCTURE
struct SlotConfig {
  char medicineName[40];
  char dose[16];
  uint8_t quantity;
  bool enabled;
  bool lowStockAlerted;
  uint8_t rfidUID[4];
  ScheduleEntry schedules[MAX_SCHEDULES_PER_SLOT];
  uint8_t numSchedules;
};

//  STATE MACHINE STATES
enum DispenserState {
  STATE_IDLE,
  STATE_ROTATING,
  STATE_LID_OPEN_WAITING,
  STATE_STRIP_TAKEN,
  STATE_SAFETY_DELAY,
  STATE_CLOSING_LID,
  STATE_REFILL_OPEN,         // lid open at this slot, waiting for old item removed
  STATE_REFILL_WAIT_RETURN,  // waiting for new medicine to be inserted
  STATE_REFILL_CLOSING,
};

//  QUEUE ITEM
struct DoseQueueItem {
  uint8_t slot;
  uint8_t schedIdx;
};

//  GLOBAL VARIABLES
SlotConfig slots[NUM_SLOTS];
DispenserState state = STATE_IDLE;
int currentSlot = 0;
int activeSlot = -1;
int activeSchedIdx = -1;
int refillSlot = 0;
bool refillCloseTimerActive = false;
bool lidIsOpen = false;

unsigned long stateEnteredAt = 0;
unsigned long nagTimer = 0;
unsigned long safetyStart = 0;
unsigned long refillCloseStart = 0;
unsigned long lastNTPSync = 0;

#define QUEUE_CAPACITY (NUM_SLOTS * MAX_SCHEDULES_PER_SLOT)
DoseQueueItem dispQueue[NUM_SLOTS * MAX_SCHEDULES_PER_SLOT];
int qHead = 0;
int qTail = 0;
int qCount = 0;
int qTotal = 0;

//  FIREBASE (new async FirebaseClient library by Mobizt)
void processFirebaseResult(AsyncResult& aResult);
void streamResultCallback(AsyncResult& aResult);

UserAuth fbUserAuth(FIREBASE_API_KEY, FIREBASE_USER, FIREBASE_PASS);
FirebaseApp fbApp;

WiFiClientSecure fbSSL;
WiFiClientSecure fbStreamSSL;

using AsyncClient = AsyncClientClass;
AsyncClient fbClient(fbSSL);
AsyncClient fbStreamClient(fbStreamSSL);

RealtimeDatabase Database;
AsyncResult fbAuthResult;

bool fbConnected = false;
bool fbStreamStarted = false;
bool scheduleChanged = false;
bool refillCmdFromApp = false;

unsigned long lastSchedCheck = 0;
unsigned long lastHeartbeat = 0;
unsigned long lastStockCheck = 0;
unsigned long lastFullFetch = 0;

bool btnDown = false;
unsigned long btnDownAt = 0;

//  OBJECTS
RTC_DS3231 rtc;
Servo lidServo;
Stepper myStepper(STEPS_PER_REV, STEP_PIN_IN1, STEP_PIN_IN3, STEP_PIN_IN2, STEP_PIN_IN4);
HardwareSerial dfSerial(2);
DFRobotDFPlayerMini dfPlayer;
MFRC522 rfid(PIN_RFID_SS, PIN_RFID_RST);
Preferences nvs;

//  FORWARD DECLARATIONS
void syncRTCfromNTP();
void connectWiFi();
void setupFirebase();
void loadSlotsFromNVS();
void saveSlotsToNVS();
void fetchSlotsFromFirebase();
void pushSlotToFirebase(int i);
void pushEvent(const char* type, int slot, const char* status);
void pushHeartbeat();
void checkSchedule();
void checkPeriodEnd();
void checkStockLevels();
void resetDailyFlags();
void beginDispense(int slot, int schedIdx);
void dispenseFromQueue(bool fromQueue = false);
void enterRefillMode();
void refillAdvanceSlot();
void exitRefillMode();
void queueItem(int slot, int schedIdx);
bool dequeueItem(DoseQueueItem& out);
void clearQueue();
void announceQueueCount(int n);
int getCurrentPeriod(uint8_t hour);
void announcePeriod(int period);
bool allDosesDoneToday();
void rotateTo(int target);
void stopStepper();
void openLid();
void closeLidSlowly();
uint8_t readFC51Stable();
bool medicinePresent();
bool medicineAbsent();
bool medicineReturned();
void buzz(int n, int onMs = 150, int offMs = 80);
void speak(uint8_t track);
void speakName(int slot);
void pollRFID();
bool matchRFID(int slot);
void handleButton();
void handleStateMachine();





void setup() {
  Serial.begin(115200);
  Serial.println(F("\n[MedCare] Booting..."));

  pinMode(STEP_PIN_IN1, OUTPUT);
  pinMode(STEP_PIN_IN2, OUTPUT);
  pinMode(STEP_PIN_IN3, OUTPUT);
  pinMode(STEP_PIN_IN4, OUTPUT);
  stopStepper();
  myStepper.setSpeed(STEPPER_RPM);

  pinMode(PIN_IR, INPUT);
  pinMode(PIN_BUZZER, OUTPUT);
  pinMode(PIN_BUTTON, INPUT_PULLUP);
  digitalWrite(PIN_BUZZER, LOW);

  lidServo.attach(PIN_SERVO);
  lidServo.writeMicroseconds(SERVO_STOP);
  delay(500);

  Wire.begin(21, 22);
  if (!rtc.begin()) {
    Serial.println(F("[RTC] ERROR — check SDA→21 SCL→22"));
  } else {
    if (rtc.lostPower()) {
      rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
      Serial.println(F("[RTC] Power lost — reset to compile time"));
    }
    DateTime n = rtc.now();
    Serial.printf("[RTC] %04d-%02d-%02d %02d:%02d:%02d\n",
                  n.year(), n.month(), n.day(), n.hour(), n.minute(), n.second());
  }

  dfSerial.begin(9600, SERIAL_8N1, PIN_DF_RX, PIN_DF_TX);
  delay(1200);
  if (dfPlayer.begin(dfSerial)) {
    dfPlayer.volume(30);
    dfPlayer.EQ(DFPLAYER_EQ_NORMAL);
    Serial.println(F("[DFPlayer] OK"));
  } else {
    Serial.println(F("[DFPlayer] ERROR — check SD card/wiring"));
  }

  SPI.begin(18, 19, 23, PIN_RFID_SS);
  rfid.PCD_Init();
  delay(100);
  Serial.println(F("[RFID] OK"));

  loadSlotsFromNVS();
  Serial.println(F("[NVS] Config loaded"));

  connectWiFi();
  if (WiFi.isConnected()) {
    syncRTCfromNTP();
    setupFirebase();
  }

  if (currentSlot != 0) {
    Serial.println(F("[Boot] Forcing current slot to 0"));
    currentSlot = 0;
    saveSlotsToNVS();  // Save the new position
    Serial.println(F("[Boot] Current slot set to 0"));
  }

  //buzz(2);
  speak(AUDIO_READY);
  Serial.println(F("[MedCare] Ready"));
}





void loop() {
  pollRFID();
  handleButton();
  handleStateMachine();

  if (state == STATE_IDLE && millis() - lastSchedCheck > 20000) {
    lastSchedCheck = millis();
    checkSchedule();
    checkPeriodEnd();
    DateTime now = rtc.now();
    if (now.hour() == 0 && now.minute() == 0) resetDailyFlags();
  }

  if (millis() - lastStockCheck > 600000) {
    lastStockCheck = millis();
    checkStockLevels();
  }


  if (WiFi.isConnected() && millis() - lastNTPSync > 86400000) {
    lastNTPSync = millis();
    syncRTCfromNTP();
  }

  if (fbConnected && millis() - lastFullFetch > 3600000) {
    lastFullFetch = millis();
    fetchSlotsFromFirebase();
    Serial.println(F("[Firebase] Hourly re-fetch"));
  }

  if (scheduleChanged) {
    scheduleChanged = false;
    fetchSlotsFromFirebase();
  }
  if (refillCmdFromApp && state == STATE_IDLE) {
    refillCmdFromApp = false;
    enterRefillMode();
  }

  if (fbConnected && millis() - lastHeartbeat > 120000) {
    lastHeartbeat = millis();
    pushHeartbeat();
  }

  //  FIREBASE — new async library: pump the auth/task queues once per loop, detect readiness, and (re)start the SSE stream.
  //  The library reconnects the stream internally on timeout/auth refresh, so no manual endStream/beginStream retry is needed here.
  fbApp.loop();
  Database.loop();

  if (fbApp.ready() && !fbConnected) {
    fbConnected = true;
    Serial.println(F("[Firebase] Authenticated"));
    fetchSlotsFromFirebase();
  }

  if (fbConnected && !fbStreamStarted) {
    fbStreamStarted = true;
    String path = "/dispensers/";
    path += DEVICE_ID;
    Database.get(fbStreamClient, path, streamResultCallback, true /* SSE mode */, "streamTask");
    Serial.println(F("[Firebase] Stream requested"));
  }

  // Drains the no-callback auth AsyncResult; harmless if unused.
  processFirebaseResult(fbAuthResult);

  delay(50);
}


void syncRTCfromNTP() {
  if (!WiFi.isConnected()) return;
  Serial.println(F("[NTP] Syncing..."));
  configTime(6 * 3600, 0, "pool.ntp.org", "time.google.com");
  struct tm timeinfo;
  if (getLocalTime(&timeinfo, 5000)) {
    rtc.adjust(DateTime(
      timeinfo.tm_year + 1900,
      timeinfo.tm_mon + 1,
      timeinfo.tm_mday,
      timeinfo.tm_hour,
      timeinfo.tm_min,
      timeinfo.tm_sec));
    Serial.printf("[NTP] Synced: %02d:%02d:%02d\n",
                  timeinfo.tm_hour, timeinfo.tm_min, timeinfo.tm_sec);
  } else {
    Serial.println(F("[NTP] Failed — keeping RTC time"));
  }
}


//  STATE MACHINE
void handleStateMachine() {
  unsigned long now = millis();

  switch (state) {

    case STATE_IDLE: break;
    case STATE_ROTATING: break;

    case STATE_LID_OPEN_WAITING:
      {
        if (medicineAbsent()) {
          delay(300);
          Serial.println(F("[Dispense] Strip removed"));
          // buzz(2);
          speak(AUDIO_TAKEN);
          delay(400);
          speakName(activeSlot);
          delay(400);
          speak(AUDIO_RETURN_STRIP);
          stateEnteredAt = now;
          nagTimer = now;
          state = STATE_STRIP_TAKEN;
        }
        if (now - nagTimer > MISSED_NAG_MS) {
          nagTimer = now;
          //buzz(5, 100);
          speak(AUDIO_REMINDER);
          pushEvent("medicine_not_taken", activeSlot, "nag");
        }
        break;
      }

    case STATE_STRIP_TAKEN:
      {
        if (medicineReturned()) {
          delay(300);
          Serial.println(F("[Dispense] Strip returned"));
          speak(AUDIO_SAFETY_CLOSING);
          //buzz(1, 300);
          safetyStart = now;
          state = STATE_SAFETY_DELAY;
        }
        if (now - nagTimer > RETURN_NAG_MS) {
          nagTimer = now;
          //buzz(3, 200);
          speak(AUDIO_NOT_RETURNED);
        }
        if (now - stateEnteredAt > RETURN_WAIT_MS) {
          Serial.println(F("[Dispense] Return timeout — closing"));
          safetyStart = now;
          state = STATE_SAFETY_DELAY;
        }
        break;
      }

    case STATE_SAFETY_DELAY:
      {
        if (now - safetyStart >= FINGER_SAFETY_MS) {
          state = STATE_CLOSING_LID;
        }
        break;
      }

    case STATE_CLOSING_LID:
      {
        closeLidSlowly();
        //buzz(1);
        speak(AUDIO_LID_CLOSED);

        if (activeSlot >= 0 && activeSchedIdx >= 0) {
          slots[activeSlot].schedules[activeSchedIdx].takenToday = true;
          if (slots[activeSlot].quantity > 0)
            slots[activeSlot].quantity--;
          saveSlotsToNVS();

          if (fbConnected) {
            pushEvent("medicine_taken", activeSlot, "taken");
            pushSlotToFirebase(activeSlot);
          }
          checkStockLevels();
          Serial.printf("[Dispense] Slot %d schedule %d done\n", activeSlot, activeSchedIdx);
        }
        activeSlot = -1;
        activeSchedIdx = -1;

        if (qCount > 0) {
          delay(1500);
          speak(AUDIO_NEXT_MEDICINE);
          delay(600);
          dispenseFromQueue(true);
        } else {
          if (allDosesDoneToday()) {
            delay(1500);
            speak(AUDIO_ALL_DONE);
            //buzz(5, 200, 100);
          }
          if (currentSlot != 0) {
            Serial.println(F("[Home] Returning to slot 0"));
            delay(800);
            rotateTo(0);
          }
          state = STATE_IDLE;
        }
        break;
      }

    case STATE_REFILL_OPEN:
      {
        // Waiting for the empty strip to be pulled out of this slot
        if (medicineAbsent()) {
          delay(300);
          Serial.printf("[Refill] Slot %d emptied — insert new medicine\n", refillSlot);
          stateEnteredAt = now;
          nagTimer = now;
          state = STATE_REFILL_WAIT_RETURN;
          break;
        }
        if (now - nagTimer > RETURN_NAG_MS) {
          nagTimer = now;
          Serial.printf("[Refill] Still waiting — remove slot %d to continue\n", refillSlot);
          //buzz(1, 200);
        }
        if (now - stateEnteredAt > RETURN_WAIT_MS) {
          Serial.printf("[Refill] Slot %d timed out waiting for removal — skipping\n", refillSlot);
          refillAdvanceSlot();
        }
        break;
      }

    case STATE_REFILL_WAIT_RETURN:
      {
        // Waiting for the new strip to be placed back in.
        if (medicineReturned()) {
          delay(300);
          Serial.printf("[Refill] Slot %d refilled\n", refillSlot);
          //buzz(2);
          refillAdvanceSlot();
          break;
        }
        if (now - nagTimer > RETURN_NAG_MS) {
          nagTimer = now;
          Serial.printf("[Refill] Waiting for new medicine in slot %d\n", refillSlot);
          //buzz(1, 200);
        }
        if (now - stateEnteredAt > RETURN_WAIT_MS) {
          Serial.printf("[Refill] Slot %d timed out waiting for insert — skipping\n", refillSlot);
          refillAdvanceSlot();
        }
        break;
      }

    case STATE_REFILL_CLOSING:
      {
        if (now - refillCloseStart >= FINGER_SAFETY_MS) {
          refillCloseTimerActive = false;
          closeLidSlowly();
          speak(AUDIO_REFILL_EXIT);
          //buzz(3, 100);
          pushEvent("refill_mode", -1, "exited");
          saveSlotsToNVS();
          if (fbConnected) {
            for (int i = 0; i < NUM_SLOTS; i++) pushSlotToFirebase(i);
          }
          state = STATE_IDLE;
        }
        break;
      }
  }
}


//  QUEUE FUNCTIONS
void queueItem(int slot, int schedIdx) {
  if (qCount >= QUEUE_CAPACITY) return;
  dispQueue[qTail].slot = slot;
  dispQueue[qTail].schedIdx = schedIdx;
  qTail = (qTail + 1) % QUEUE_CAPACITY;
  qCount++;
  Serial.printf("[Queue] Added slot %d sched %d (%s) — size: %d\n",
                slot, schedIdx, slots[slot].medicineName, qCount);
}

bool dequeueItem(DoseQueueItem& out) {
  if (qCount == 0) return false;
  out = dispQueue[qHead];
  qHead = (qHead + 1) % QUEUE_CAPACITY;
  qCount--;
  return true;
}

void clearQueue() {
  qHead = 0;
  qTail = 0;
  qCount = 0;
  qTotal = 0;
}

void announceQueueCount(int n) {
  if (n >= 1 && n <= 5) speak(AUDIO_QUEUE_BASE + n - 1);
}

bool allDosesDoneToday() {
  for (int i = 0; i < NUM_SLOTS; i++) {
    if (!slots[i].enabled) continue;
    for (int j = 0; j < slots[i].numSchedules; j++) {
      if (!slots[i].schedules[j].active) continue;
      if (!slots[i].schedules[j].takenToday) return false;
    }
  }
  return true;
}

void dispenseFromQueue(bool fromQueue) {
  if (!fromQueue && state != STATE_IDLE) return;

  DoseQueueItem item;
  while (dequeueItem(item)) {
    int s = item.slot;
    int j = item.schedIdx;
    if (slots[s].enabled && slots[s].quantity > 0 && j < slots[s].numSchedules && slots[s].schedules[j].active && !slots[s].schedules[j].takenToday) {
      Serial.printf("[Queue] Next: slot %d sched %d (%s) | %d left\n", s, j, slots[s].medicineName, qCount);
      beginDispense(s, j);
      return;
    }
    Serial.printf("[Queue] Skipping slot %d sched %d — conditions changed\n", s, j);
  }

  Serial.println(F("[Queue] Exhausted"));
  if (allDosesDoneToday()) {
    delay(1500);
    speak(AUDIO_ALL_DONE);
    //buzz(5, 200, 100);
  }
  if (currentSlot != 0) {
    Serial.println(F("[Home] Returning to slot 0"));
    delay(800);
    rotateTo(0);
  }
  state = STATE_IDLE;
}

//  PERIOD HELPER FUNCTIONS
int getCurrentPeriod(uint8_t hour) {
  for (int p = 0; p < 3; p++) {
    if (hour >= PERIOD_START[p] && hour <= PERIOD_END[p]) return p;
  }
  return -1;
}

void announcePeriod(int period) {
  if (period == PERIOD_MORNING) speak(AUDIO_PERIOD_MORNING);
  else if (period == PERIOD_LUNCH) speak(AUDIO_PERIOD_LUNCH);
  else if (period == PERIOD_NIGHT) speak(AUDIO_PERIOD_NIGHT);
}

void checkSchedule() {
  DateTime now = rtc.now();
  uint8_t hour = now.hour();
  uint8_t min = now.minute();
  bool found = false;

  for (int i = 0; i < NUM_SLOTS; i++) {
    if (!slots[i].enabled) continue;
    if (slots[i].quantity == 0) continue;

    for (int j = 0; j < slots[i].numSchedules; j++) {
      ScheduleEntry& sc = slots[i].schedules[j];
      if (!sc.active) continue;
      if (sc.takenToday) continue;

      bool due = false;
      if (sc.period == PERIOD_EXACT) {
        due = (hour == sc.hour && min == sc.minute);
      } else {
        due = (hour == PERIOD_START[sc.period] && min == 0);
      }

      if (due) {
        queueItem(i, j);
        found = true;
        Serial.printf("[Schedule] Slot %d sched %d due — %s (%s)\n", i, j, slots[i].medicineName, PERIOD_NAMES[sc.period]);
      }
    }
  }

  if (!found) return;

  int period = getCurrentPeriod(hour);
  if (period >= 0) {
    announcePeriod(period);
    delay(400);
  }

  qTotal = qCount;
  if (qTotal > 1) {
    announceQueueCount(qTotal);
    delay(400);
  }

  dispenseFromQueue();
}

void checkPeriodEnd() {
  DateTime now = rtc.now();
  if (now.minute() != 59) return;

  for (int p = 0; p < 3; p++) {
    if (now.hour() != PERIOD_END_HOUR[p]) continue;

    for (int i = 0; i < NUM_SLOTS; i++) {
      if (!slots[i].enabled) continue;
      if (slots[i].quantity == 0) continue;

      for (int j = 0; j < slots[i].numSchedules; j++) {
        ScheduleEntry& sc = slots[i].schedules[j];
        if (!sc.active) continue;
        if (sc.period != p) continue;
        if (sc.takenToday) continue;

        Serial.printf("[Missed] Slot %d sched %d — %s period ended\n", i, j, PERIOD_NAMES[p]);
        //buzz(4, 200, 80);
        speak(AUDIO_MISSED_PERIOD);
        pushEvent("medicine_missed", i, "missed_period_end");
      }
    }
  }
}

//  BEGIN DISPENSE
void beginDispense(int slot, int schedIdx) {
  activeSlot = slot;
  activeSchedIdx = schedIdx;
  Serial.printf("[Dispense] Slot %d sched %d: %s\n", slot, schedIdx, slots[slot].medicineName);

  //buzz(1);
  speak(AUDIO_ROTATING);

  state = STATE_ROTATING;
  rotateTo(slot);
  openLid();
  delay(300);

  speakName(slot);
  delay(300);
  speak(AUDIO_TAKE_NOW);

  stateEnteredAt = millis();
  nagTimer = millis();
  state = STATE_LID_OPEN_WAITING;
}

//  BUTTON HANDLER
void handleButton() {
  bool pressed = (digitalRead(PIN_BUTTON) == LOW);

  if (pressed && !btnDown) {
    btnDown = true;
    btnDownAt = millis();
    return;
  }

  if (!pressed && btnDown) {
    btnDown = false;
    unsigned long held = millis() - btnDownAt;
    if (held < SHORT_PRESS_MIN) return;

    bool longPress = (held >= LONG_PRESS_MS);

    //   REFILL MODE: short = advance slot, long = exit
    if (state == STATE_REFILL_OPEN || state == STATE_REFILL_WAIT_RETURN) {
      if (longPress) {
        exitRefillMode();
      } else {
        Serial.printf("[BTN] Refill: advancing slot %d\\n", refillSlot);
        speak(AUDIO_REFILL_NEXT);
        refillAdvanceSlot();
      }
      return;
    }

    //  NORMAL MODE: only when IDLE
    if (state != STATE_IDLE) return;

    if (longPress) {
      Serial.println(F("[BTN] Long press → Refill mode"));
      enterRefillMode();
      return;
    }

    //  SHORT PRESS: find and queue all due medicines
    Serial.println(F("[BTN] Short press → checking due medicines"));
    DateTime now = rtc.now();
    uint8_t hour = now.hour();
    uint8_t minute = now.minute();
    int period = getCurrentPeriod(hour);

    Serial.printf("[BTN] Time=%02d:%02d | Period=%d\n", hour, minute, period);

    clearQueue();
    bool anyFound = false;
    bool anyDueTaken = false;

    for (int i = 0; i < NUM_SLOTS; i++) {
      if (!slots[i].enabled || slots[i].quantity == 0) continue;

      for (int j = 0; j < slots[i].numSchedules; j++) {
        ScheduleEntry& sc = slots[i].schedules[j];
        if (!sc.active) continue;

        bool due = false;
        if (sc.period == PERIOD_EXACT) {
          int sched = sc.hour * 60 + sc.minute;
          int curr = hour * 60 + minute;
          due = (abs(curr - sched) <= 30);
        } else {
          due = ((int)sc.period == period && period >= 0);
        }

        if (!due) continue;
        anyFound = true;

        if (sc.takenToday) {
          anyDueTaken = true;
        } else {
          queueItem(i, j);
        }
      }
    }

    Serial.printf("[BTN] Found=%d Taken=%d Queue=%d\n", anyFound, anyDueTaken, qCount);

    if (qCount > 0) {
      if (period >= 0) {
        announcePeriod(period);
        delay(400);
      }
      qTotal = qCount;
      if (qTotal > 1) {
        announceQueueCount(qTotal);
        delay(400);
      }
      dispenseFromQueue();

    } else if (anyFound && anyDueTaken) {
      Serial.println(F("[BTN] All already taken"));
      speak(AUDIO_ALREADY_TAKEN);

    } else {
      Serial.println(F("[BTN] Nothing due now"));
      speak(AUDIO_NOTHING_DUE);
    }
  }
}

//  RFID CHECK
void pollRFID() {
  if (!rfid.PICC_IsNewCardPresent()) return;
  if (!rfid.PICC_ReadCardSerial()) return;

  Serial.printf("[RFID] Card: %02X:%02X:%02X:%02X\n",
                rfid.uid.uidByte[0],
                rfid.uid.uidByte[1],
                rfid.uid.uidByte[2],
                rfid.uid.uidByte[3]);

  if (rfid.uid.uidByte[0] == 0x03 && rfid.uid.uidByte[1] == 0x9C && rfid.uid.uidByte[2] == 0x11 && rfid.uid.uidByte[3] == 0xFD) {
    buzz(1);
    speak(11);
  } else if (rfid.uid.uidByte[0] == 0x23 && rfid.uid.uidByte[1] == 0x4B && rfid.uid.uidByte[2] == 0x10 && rfid.uid.uidByte[3] == 0xFD) {
    buzz(1);
    speak(12);
  } else if (rfid.uid.uidByte[0] == 0x43 && rfid.uid.uidByte[1] == 0x3D && rfid.uid.uidByte[2] == 0x44 && rfid.uid.uidByte[3] == 0xFC) {
    buzz(1);
    speak(13);
  } else if (rfid.uid.uidByte[0] == 0x99 && rfid.uid.uidByte[1] == 0x47 && rfid.uid.uidByte[2] == 0x16 && rfid.uid.uidByte[3] == 0x05) {
    buzz(1);
    speak(14);
  } else if (rfid.uid.uidByte[0] == 0x33 && rfid.uid.uidByte[1] == 0x19 && rfid.uid.uidByte[2] == 0xBD && rfid.uid.uidByte[3] == 0xFC) {
    buzz(1);
    speak(15);
  } else {
    Serial.println("Unknown Card");
  }

  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();
}

bool matchRFID(int slot) {
  bool hasUID = false;
  for (int i = 0; i < 4; i++) {
    if (slots[slot].rfidUID[i] != 0) {
      hasUID = true;
      break;
    }
  }
  if (!hasUID) return false;
  for (int i = 0; i < 4; i++) {
    if (rfid.uid.uidByte[i] != slots[slot].rfidUID[i]) return false;
  }
  return true;
}

//  REFILL MODE
void enterRefillMode() {
  if (state != STATE_IDLE) return;
  refillSlot = 0;
  //buzz(3, 200, 100);
  speak(AUDIO_REFILL_ENTER);
  delay(400);
  pushEvent("refill_mode", -1, "entered");

// Lid opens once here and stays open for the whole refill session, it only closes after slot 4 (or on a long press to exit early).
  rotateTo(0);
  openLid();
  speakName(0);
  speak(AUDIO_REFILL_OPEN);
  speak(AUDIO_REFILL_NEXT);

  stateEnteredAt = millis();
  nagTimer = millis();
  state = STATE_REFILL_OPEN;
}

// Moves refill to the next slot (lid stays open), or — once slot 4 is
// done — starts the single end-of-refill lid close. Called both when
// the FC51 sensor confirms a refill and when a wait times out.
void refillAdvanceSlot() {
  refillSlot++;
  if (refillSlot >= NUM_SLOTS) {
    speak(AUDIO_SAFETY_CLOSING);
    //buzz(1, 300);
    refillCloseStart = millis();
    refillCloseTimerActive = true;
    state = STATE_REFILL_CLOSING;
  } else {
    rotateTo(refillSlot);
    speakName(refillSlot);
    speak(AUDIO_REFILL_NEXT);
    stateEnteredAt = millis();
    nagTimer = millis();
    state = STATE_REFILL_OPEN;
  }
}

void exitRefillMode() {
  Serial.println(F("[Refill] Exiting"));
  speak(AUDIO_SAFETY_CLOSING);
  //buzz(1, 300);
  delay(FINGER_SAFETY_MS);
  closeLidSlowly();
  speak(AUDIO_REFILL_EXIT);
  //buzz(3, 100);
  pushEvent("refill_mode", -1, "exited");
  saveSlotsToNVS();
  if (fbConnected) {
    for (int i = 0; i < NUM_SLOTS; i++) pushSlotToFirebase(i);
  }
  state = STATE_IDLE;
}

//  STEPPER ROTATION
void rotateTo(int target) {
  int diff = (target - currentSlot + NUM_SLOTS) % NUM_SLOTS;

  if (diff == 0) {
    Serial.printf("[Motor] Already at slot %d\n", target);
    return;
  }

  int steps = diff * STEPS_PER_SLOT;
  Serial.printf("[Motor] Slot %d → %d | %d steps CW\n",
                currentSlot, target, steps);

  myStepper.setSpeed(STEPPER_RPM);
  myStepper.step(steps);
  stopStepper();

  currentSlot = target;
  delay(300);

  Serial.printf("[Motor] At slot %d\n", currentSlot);
}

void stopStepper() {
  digitalWrite(STEP_PIN_IN1, LOW);
  digitalWrite(STEP_PIN_IN2, LOW);
  digitalWrite(STEP_PIN_IN3, LOW);
  digitalWrite(STEP_PIN_IN4, LOW);
}

//  LID SERVO
void openLid() {
  if (lidIsOpen) return;
  Serial.println(F("[Lid] Opening..."));
  lidServo.writeMicroseconds(SERVO_OPEN_SPEED);
  delay(SERVO_RUN_TIME);
  lidServo.writeMicroseconds(SERVO_STOP);
  lidIsOpen = true;
  Serial.println(F("[Lid] Open"));
}

void closeLidSlowly() {
  if (!lidIsOpen) return;
  Serial.println(F("[Lid] Closing..."));
  lidServo.writeMicroseconds(SERVO_CLOSE_SPEED);
  delay(SERVO_CLOSE_TIME);
  lidServo.writeMicroseconds(SERVO_STOP);
  lidIsOpen = false;
  Serial.println(F("[Lid] Closed"));
}

//  FC-51 IR SENSOR
uint8_t readFC51Stable() {
  int blocked = 0, clear = 0;
  for (int i = 0; i < 5; i++) {
    (digitalRead(PIN_IR) == FC51_BLOCKED) ? blocked++ : clear++;
    delay(8);
  }
  return (blocked >= 3) ? FC51_BLOCKED : FC51_CLEAR;
}

bool medicinePresent() {
  return readFC51Stable() == FC51_BLOCKED;
}
bool medicineAbsent() {
  return readFC51Stable() == FC51_CLEAR;
}
bool medicineReturned() {
  return readFC51Stable() == FC51_BLOCKED;
}

//  ACTIVE BUZZER
void buzz(int n, int onMs, int offMs) {
  for (int i = 0; i < n; i++) {
    digitalWrite(PIN_BUZZER, HIGH);
    delay(onMs);
    digitalWrite(PIN_BUZZER, LOW);
    delay(offMs);
  }
}

//  AUDIO
void speak(uint8_t track) {
  dfPlayer.play(track);
  delay(2800);
}

void speakName(int slot) {
  dfPlayer.play(AUDIO_NAME_BASE + slot);
  delay(3000);
}

//  STOCK LEVEL CHECK
void checkStockLevels() {
  for (int i = 0; i < NUM_SLOTS; i++) {
    if (!slots[i].enabled) continue;
    int qty = slots[i].quantity;

    if (qty == 0) {
      slots[i].enabled = false;
      saveSlotsToNVS();
      speak(AUDIO_LOW_STOCK);
      //buzz(4, 200);
      Serial.printf("[Stock] Slot %d EMPTY — disabled\n", i);
      pushEvent("stock_empty", i, "empty");
      if (fbConnected) pushSlotToFirebase(i);

    } else if (qty <= STOCK_WARN_CRITICAL && !slots[i].lowStockAlerted) {
      slots[i].lowStockAlerted = true;
      saveSlotsToNVS();
      speak(AUDIO_LOW_STOCK);
      //buzz(3, 150);
      Serial.printf("[Stock] Slot %d CRITICAL: %d\n", i, qty);
      pushEvent("stock_critical", i, "critical");

    } else if (qty <= STOCK_WARN_LOW && qty > STOCK_WARN_CRITICAL && !slots[i].lowStockAlerted) {
      slots[i].lowStockAlerted = true;
      saveSlotsToNVS();
      //buzz(2, 100);
      Serial.printf("[Stock] Slot %d LOW: %d\n", i, qty);
      pushEvent("stock_low", i, "low");

    } else if (qty > STOCK_WARN_LOW && slots[i].lowStockAlerted) {
      slots[i].lowStockAlerted = false;
      slots[i].enabled = true;
      saveSlotsToNVS();
      Serial.printf("[Stock] Slot %d restocked: %d\n", i, qty);
      pushEvent("stock_refilled", i, "ok");
      if (fbConnected) pushSlotToFirebase(i);
    }
  }
}

//  DAILY RESET
void resetDailyFlags() {
  for (int i = 0; i < NUM_SLOTS; i++) {
    for (int j = 0; j < MAX_SCHEDULES_PER_SLOT; j++) {
      slots[i].schedules[j].takenToday = false;
    }
    slots[i].lowStockAlerted = false;
  }
  saveSlotsToNVS();
  if (fbConnected)
    for (int i = 0; i < NUM_SLOTS; i++) pushSlotToFirebase(i);
  Serial.println(F("[Scheduler] Midnight reset"));
}

//  NVS
void loadSlotsFromNVS() {
  nvs.begin("medcare", true);
  currentSlot = nvs.getInt("curSlot", 0);
  for (int i = 0; i < NUM_SLOTS; i++) {
    char key[20];
    snprintf(key, sizeof(key), "s%d_name", i);
    String n = nvs.getString(key, String("Slot ") + (i + 1));
    strlcpy(slots[i].medicineName, n.c_str(), 40);

    snprintf(key, sizeof(key), "s%d_dose", i);
    String d = nvs.getString(key, "--");
    strlcpy(slots[i].dose, d.c_str(), 16);

    snprintf(key, sizeof(key), "s%d_qty", i);
    slots[i].quantity = nvs.getUChar(key, 0);
    snprintf(key, sizeof(key), "s%d_en", i);
    slots[i].enabled = nvs.getBool(key, false);
    snprintf(key, sizeof(key), "s%d_alt", i);
    slots[i].lowStockAlerted = nvs.getBool(key, false);
    snprintf(key, sizeof(key), "s%d_num", i);
    slots[i].numSchedules = nvs.getUChar(key, 1);

    for (int b = 0; b < 4; b++) {
      snprintf(key, sizeof(key), "s%d_u%d", i, b);
      slots[i].rfidUID[b] = nvs.getUChar(key, 0);
    }

    for (int j = 0; j < MAX_SCHEDULES_PER_SLOT; j++) {
      snprintf(key, sizeof(key), "s%d_c%d_per", i, j);
      slots[i].schedules[j].period = nvs.getUChar(key, PERIOD_EXACT);
      snprintf(key, sizeof(key), "s%d_c%d_hr", i, j);
      slots[i].schedules[j].hour = nvs.getUChar(key, 8);
      snprintf(key, sizeof(key), "s%d_c%d_min", i, j);
      slots[i].schedules[j].minute = nvs.getUChar(key, 0);
      snprintf(key, sizeof(key), "s%d_c%d_act", i, j);
      slots[i].schedules[j].active = nvs.getBool(key, (j == 0));
      snprintf(key, sizeof(key), "s%d_c%d_tak", i, j);
      slots[i].schedules[j].takenToday = nvs.getBool(key, false);
    }
  }
  nvs.end();
}

void saveSlotsToNVS() {
  nvs.begin("medcare", false);
  nvs.putInt("curSlot", currentSlot);
  for (int i = 0; i < NUM_SLOTS; i++) {
    char key[20];
    snprintf(key, sizeof(key), "s%d_name", i);
    nvs.putString(key, slots[i].medicineName);
    snprintf(key, sizeof(key), "s%d_dose", i);
    nvs.putString(key, slots[i].dose);
    snprintf(key, sizeof(key), "s%d_qty", i);
    nvs.putUChar(key, slots[i].quantity);
    snprintf(key, sizeof(key), "s%d_en", i);
    nvs.putBool(key, slots[i].enabled);
    snprintf(key, sizeof(key), "s%d_alt", i);
    nvs.putBool(key, slots[i].lowStockAlerted);
    snprintf(key, sizeof(key), "s%d_num", i);
    nvs.putUChar(key, slots[i].numSchedules);

    for (int b = 0; b < 4; b++) {
      snprintf(key, sizeof(key), "s%d_u%d", i, b);
      nvs.putUChar(key, slots[i].rfidUID[b]);
    }

    for (int j = 0; j < MAX_SCHEDULES_PER_SLOT; j++) {
      snprintf(key, sizeof(key), "s%d_c%d_per", i, j);
      nvs.putUChar(key, slots[i].schedules[j].period);
      snprintf(key, sizeof(key), "s%d_c%d_hr", i, j);
      nvs.putUChar(key, slots[i].schedules[j].hour);
      snprintf(key, sizeof(key), "s%d_c%d_min", i, j);
      nvs.putUChar(key, slots[i].schedules[j].minute);
      snprintf(key, sizeof(key), "s%d_c%d_act", i, j);
      nvs.putBool(key, slots[i].schedules[j].active);
      snprintf(key, sizeof(key), "s%d_c%d_tak", i, j);
      nvs.putBool(key, slots[i].schedules[j].takenToday);
    }
  }
  nvs.end();
  Serial.println(F("[NVS] Saved"));
}

//  WIFI
void connectWiFi() {
  Serial.printf("[WiFi] Connecting to %s", WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  WiFi.setSleep(false);
  WiFi.setAutoReconnect(true);

  for (int t = 0; t < 40 && WiFi.status() != WL_CONNECTED; t++) {
    delay(500);
    Serial.print(".");
  }
  if (WiFi.isConnected())
    Serial.printf("\n[WiFi] IP: %s, RSSI: %d\n", WiFi.localIP().toString().c_str(), WiFi.RSSI());
  else
    Serial.println(F("\n[WiFi] Offline — NVS only"));
}

//  FIREBASE — SETUP (new async FirebaseClient library)
void setupFirebase() {
  Serial.println(F("[Firebase] Initializing..."));

  // The SSL client options depend on the SSL client used (WiFiClientSecure here).
  // setInsecure() skips certificate verification, matches the relaxed setup
  // the old library used by default. Swap in setCACert(...) later if want
  // to pin the Firebase root certificate.
  fbSSL.setInsecure();
  fbStreamSSL.setInsecure();
  fbSSL.setConnectionTimeout(15000);
  fbStreamSSL.setConnectionTimeout(15000);

  Database.url(FIREBASE_DB_URL);

  // Queue the auth task (async) and bind Database to this FirebaseApp.
  initializeApp(fbClient, fbApp, getAuth(fbUserAuth), fbAuthResult);
  fbApp.getApp<RealtimeDatabase>(Database);

  Serial.print(F("[Firebase] Authenticating"));
  int attempts = 0;
  while (!fbApp.ready() && attempts < 25) {
    fbApp.loop();
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (fbApp.ready()) {
    fbConnected = true;
    Serial.println(F("\n[Firebase] Connected!"));
    fetchSlotsFromFirebase();
  } else {
    Serial.println(F("\n[Firebase] Authentication still pending — will keep retrying in the background"));
    // loop() finishes the handshake later via fbApp.loop() and flips
    // fbConnected once fbApp.ready() becomes true.
  }
}

//  STREAM + GENERAL ASYNC RESULT CALLBACKS
void streamResultCallback(AsyncResult& aResult) {
  if (!aResult.isResult()) return;

  if (aResult.isError()) {
    Firebase.printf("[Firebase] Stream error: %s (code %d)\n", aResult.error().message().c_str(), aResult.error().code());
    return;
  }

  if (!aResult.available()) return;

  RealtimeDatabaseResult& stream = aResult.to<RealtimeDatabaseResult>();
  if (!stream.isStream()) return;

  String path = stream.dataPath();
  Serial.printf("[Stream] Change at: %s\n", path.c_str());
  Serial.printf("[Stream] Event=%s Path=%s Data=%s\n",
    stream.event().c_str(),
    stream.dataPath().c_str(),
    stream.data().c_str());

  if (path.endsWith("/command")) {
    String cmd = stream.data();
    cmd.replace("\"", "");  // string values arrive JSON-quoted
    Serial.printf("[Stream] Command received: %s\n", cmd.c_str());

    if (cmd == "start_refill" && state == STATE_IDLE) {
      refillCmdFromApp = true;
    } else if (cmd == "exit_refill" && state == STATE_REFILL_OPEN) {
      exitRefillMode();
    }

    // Clear the command after processing.
    String cmdPath = "/dispensers/";
    cmdPath += DEVICE_ID;
    cmdPath += "/command";
    Database.set<String>(fbClient, cmdPath, "");
  } else if (path.indexOf("/slots") >= 0) {
    scheduleChanged = true;
  }
}

void processFirebaseResult(AsyncResult& aResult) {
  if (!aResult.isResult()) return;

  if (aResult.isEvent())
    Firebase.printf("[Firebase] Event: %s, msg: %s, code: %d\n",
                    aResult.uid().c_str(), aResult.eventLog().message().c_str(), aResult.eventLog().code());

  if (aResult.isError())
    Firebase.printf("[Firebase] Error: %s, msg: %s, code: %d\n",
                    aResult.uid().c_str(), aResult.error().message().c_str(), aResult.error().code());
}

//  FETCH SLOTS: await mode get() + ArduinoJson parse
void fetchSlotsFromFirebase() {
  if (!fbConnected || !fbApp.ready()) {
    Serial.println(F("[Firebase] Not ready for fetch"));
    return;
  }

  Serial.println(F("[Firebase] Fetching slots..."));

  for (int i = 0; i < NUM_SLOTS; i++) {
    String path = "/dispensers/";
    path += DEVICE_ID;
    path += "/slots/";
    path += i;

    // Await mode: no callback/AsyncResult passed, so this blocks until
    // the response (or timeout/error) — same blocking behavior the
    // original for-loop had with the old library's getJSON().
    String payload = Database.get<String>(fbClient, path);

    if (fbClient.lastError().code() != 0) {
      Serial.printf("[Firebase] Failed to fetch slot %d: %s\n",
                    i, fbClient.lastError().message().c_str());
      delay(100);
      continue;
    }

    JsonDocument doc;  // ArduinoJson v7 
    DeserializationError err = deserializeJson(doc, payload);
    if (err) {
      Serial.printf("[Firebase] JSON parse error slot %d: %s\n", i, err.c_str());
      delay(100);
      continue;
    }

    if (!doc["medicineName"].isNull())
      strlcpy(slots[i].medicineName, doc["medicineName"].as<const char*>(), 40);
    if (!doc["dose"].isNull())
      strlcpy(slots[i].dose, doc["dose"].as<const char*>(), 16);
    if (!doc["quantity"].isNull())
      slots[i].quantity = doc["quantity"].as<uint8_t>();
    if (!doc["enabled"].isNull())
      slots[i].enabled = doc["enabled"].as<bool>();
    if (!doc["numSchedules"].isNull())
      slots[i].numSchedules = constrain(doc["numSchedules"].as<int>(), 0, MAX_SCHEDULES_PER_SLOT);

    JsonArray scheds = doc["schedules"];
    for (int j = 0; j < MAX_SCHEDULES_PER_SLOT; j++) {
      if (j < (int)scheds.size()) {
        JsonObject sc = scheds[j];
        if (!sc["period"].isNull()) slots[i].schedules[j].period = sc["period"].as<uint8_t>();
        if (!sc["hour"].isNull()) slots[i].schedules[j].hour = sc["hour"].as<uint8_t>();
        if (!sc["minute"].isNull()) slots[i].schedules[j].minute = sc["minute"].as<uint8_t>();
        if (!sc["takenToday"].isNull()) slots[i].schedules[j].takenToday = sc["takenToday"].as<bool>();
      }
      slots[i].schedules[j].active = (j < slots[i].numSchedules);
    }

    Serial.printf("[Firebase] Slot %d: %s | schedules=%d | qty=%d\n",
                  i, slots[i].medicineName, slots[i].numSchedules, slots[i].quantity);
    delay(100);
  }

  checkStockLevels();
  saveSlotsToNVS();
  lastFullFetch = millis();
}

//  PUSH SLOT: build JSON with ArduinoJson
void pushSlotToFirebase(int i) {
  if (!fbConnected || !fbApp.ready()) return;

  String path = "/dispensers/";
  path += DEVICE_ID;
  path += "/slots/";
  path += i;

  JsonDocument doc;
  doc["medicineName"] = slots[i].medicineName;
  doc["dose"] = slots[i].dose;
  doc["quantity"] = (int)slots[i].quantity;
  doc["enabled"] = slots[i].enabled;
  doc["numSchedules"] = (int)slots[i].numSchedules;

  JsonArray scheds = doc["schedules"].to<JsonArray>();
  for (int j = 0; j < slots[i].numSchedules; j++) {
    JsonObject sc = scheds.add<JsonObject>();
    sc["period"] = (int)slots[i].schedules[j].period;
    sc["hour"] = (int)slots[i].schedules[j].hour;
    sc["minute"] = (int)slots[i].schedules[j].minute;
    sc["takenToday"] = slots[i].schedules[j].takenToday;
  }

  String json;
  serializeJson(doc, json);

  if (!Database.set<object_t>(fbClient, path, object_t(json))) {
    Serial.printf("[Firebase] Push slot %d failed: %s\n",
                  i, fbClient.lastError().message().c_str());
  }
}

//  PUSH EVENT
void pushEvent(const char* type, int slot, const char* status) {
  if (!fbConnected || !fbApp.ready()) return;

  DateTime now = rtc.now();
  char ts[20];
  snprintf(ts, sizeof(ts), "%04d-%02d-%02d %02d:%02d",
           now.year(), now.month(), now.day(), now.hour(), now.minute());

  String path = "/dispensers/";
  path += DEVICE_ID;
  path += "/events";

  JsonDocument doc;
  doc["type"] = type;
  doc["slot"] = slot >= 0 ? slot : -1;
  doc["name"] = slot >= 0 ? slots[slot].medicineName : "--";
  doc["status"] = status;
  doc["timestamp"] = ts;

  String json;
  serializeJson(doc, json);

  Database.push<object_t>(fbClient, path, object_t(json));
  if (fbClient.lastError().code() != 0) {
    Serial.printf("[Firebase] Event push failed: %s\n", fbClient.lastError().message().c_str());
  } else {
    Serial.printf("[Firebase] Event: %s -> %s\n", type, status);
  }
}

//  PUSH HEARTBEAT
void pushHeartbeat() {
  if (!fbConnected || !fbApp.ready()) return;

  DateTime now = rtc.now();
  char ts[20];
  snprintf(ts, sizeof(ts), "%04d-%02d-%02d %02d:%02d",
           now.year(), now.month(), now.day(), now.hour(), now.minute());

  String path = "/dispensers/";
  path += DEVICE_ID;
  path += "/status";

  JsonDocument doc;
  doc["online"] = true;
  doc["lastSeen"] = ts;
  doc["wifi_rssi"] = (int)WiFi.RSSI();
  doc["currentSlot"] = (int)currentSlot;
  doc["mode"] =
    state == STATE_IDLE ? "idle" : state == STATE_REFILL_OPEN ? "refill"
                                                              : "active";

  String json;
  serializeJson(doc, json);

  if (!Database.set<object_t>(fbClient, path, object_t(json))) {
    Serial.printf("[Firebase] Heartbeat failed: %s\n", fbClient.lastError().message().c_str());
  }
}
