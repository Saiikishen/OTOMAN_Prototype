/*
 * ESP32 — WiFi Provisioning + MQTT Motor Controller
 *
 * ── First boot ────────────────────────────────────────────────────────────────
 *  1. No WiFi credentials saved → starts as AP: "ESP32-Setup" (no password)
 *  2. Flutter app connects to that hotspot and POSTs credentials to 192.168.4.1
 *  3. Credentials saved to NVS (survives power loss) → ESP32 restarts
 *  4. Connects to your WiFi → MQTT broker
 *
 * ── Re-configure WiFi ─────────────────────────────────────────────────────────
 *  Option A: Hold GPIO 0 (BOOT button) for 3 seconds → clears NVS → restarts into AP mode
 *  Option B: Publish "RESET" to esp32/system/wifi via MQTT from Flutter
 *
 * ── HTTP Provisioning Endpoints (AP mode only, 192.168.4.1) ──────────────────
 *  POST /configure    body: {"ssid":"...","password":"..."}
 *  GET  /status       returns {"configured":false}
 *
 * ── MQTT Topics (normal mode) ─────────────────────────────────────────────────
 *  SUB  esp32/motor1/control      ON | OFF
 *  SUB  esp32/motor2/control      ON | OFF
 *  SUB  esp32/system/wifi         RESET  (triggers AP mode)
 *  SUB  esp32/schedules           JSON array of schedule slots
 *  PUB  esp32/status              {"motor1":bool,"motor2":bool,"wifi":"SSID"}
 *  PUB  esp32/online              true | false  (LWT)
 *
 * Required Libraries:
 *   • PubSubClient  (Nick O'Leary)
 *   • ArduinoJson   (Benoit Blanchon v6+)
 *   • Preferences   (built-in ESP32 core — no install needed)
 *
 * ── NTP timezone ──────────────────────────────────────────────────────────────
 *  Change UTC_OFFSET_SECONDS to match your timezone.
 *  IST (UTC+5:30) = 19800   |   UTC = 0   |   EST (UTC-5) = -18000
 */

#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <time.h>

// ============================================================
//  MQTT Config
// ============================================================
const char* MQTT_BROKER    = "broker.hivemq.com";
const int   MQTT_PORT      = 1883;
const char* MQTT_CLIENT_ID = "esp32-motor-001";

const char* TOPIC_MOTOR1    = "esp32/motor1/control";
const char* TOPIC_MOTOR2    = "esp32/motor2/control";
const char* TOPIC_WIFI_CMD  = "esp32/system/wifi";
const char* TOPIC_STATUS    = "esp32/status";
const char* TOPIC_ONLINE    = "esp32/online";
const char* TOPIC_SCHEDULES = "esp32/schedules";

// ── Timezone — change to match your location ──────────────────
#define UTC_OFFSET_SECONDS 19800  // IST = UTC+5:30

// ============================================================
//  AP Config (provisioning mode)
// ============================================================
const char* AP_SSID = "ESP32-Setup";
const char* AP_PASS = "";

// ============================================================
//  Pin Definitions
// ============================================================
const int MOTOR1_PIN_ON  = 19;
const int MOTOR1_PIN_OFF = 22;
const int MOTOR2_PIN     = 21;
const int RESET_BUTTON   = 0;

// ============================================================
//  State
// ============================================================
bool motor1_state = false;
bool motor2_state = false;

Preferences  prefs;
WebServer    httpServer(80);
WiFiClient   wifiClient;
PubSubClient mqttClient(wifiClient);

// ============================================================
//  Schedule State
// ============================================================
struct ScheduleSlot {
  int  motor;
  int  hour;
  int  minute;
  bool turnOn;
  bool enabled;
  int  lastFiredHHMM;  // FIX: double-fire guard — stores hour*60+min of last fire
};

#define MAX_SLOTS 40
ScheduleSlot  scheduleSlots[MAX_SLOTS];
int           slotCount         = 0;
unsigned long lastScheduleCheck = 0;

// ============================================================
//  Motor Helpers
// ============================================================
void pulsePin(int pin) {
  digitalWrite(pin, HIGH);
  delay(500);
  digitalWrite(pin, LOW);
}

void motor1Enable()  { if (!motor1_state) { pulsePin(MOTOR1_PIN_ON);  motor1_state = true;  Serial.println("[Motor1] ON");  } }
void motor1Disable() { if (motor1_state)  { pulsePin(MOTOR1_PIN_OFF); motor1_state = false; Serial.println("[Motor1] OFF"); } }
void motor2Enable()  { digitalWrite(MOTOR2_PIN, HIGH); motor2_state = true;  Serial.println("[Motor2] ON");  }
void motor2Disable() { digitalWrite(MOTOR2_PIN, LOW);  motor2_state = false; Serial.println("[Motor2] OFF"); }

// ============================================================
//  MQTT — publishStatus
//  FIX: guard against calling when disconnected
// ============================================================
void publishStatus() {
  if (!mqttClient.connected()) return;  // FIX: silent no-op guard

  StaticJsonDocument<128> doc;
  doc["motor1"] = motor1_state;
  doc["motor2"] = motor2_state;
  doc["wifi"]   = WiFi.SSID();

  char buf[128];
  serializeJson(doc, buf);
  mqttClient.publish(TOPIC_STATUS, buf, true);
  Serial.printf("[MQTT] Status: %s\n", buf);
}

// ============================================================
//  NVS Helpers — WiFi credentials
// ============================================================
String getSavedSSID() {
  prefs.begin("wifi", true);
  String s = prefs.getString("ssid", "");
  prefs.end();
  return s;
}

String getSavedPassword() {
  prefs.begin("wifi", true);
  String p = prefs.getString("pass", "");
  prefs.end();
  return p;
}

void saveCredentials(const String& ssid, const String& pass) {
  prefs.begin("wifi", false);
  prefs.putString("ssid", ssid);
  prefs.putString("pass", pass);
  prefs.end();
  Serial.println("[NVS] Credentials saved.");
}

void clearCredentials() {
  prefs.begin("wifi", false);
  prefs.clear();
  prefs.end();
  Serial.println("[NVS] Credentials cleared.");
}

// ============================================================
//  Schedule NVS + Parser
//  FIX: heap-allocated JsonDocument to avoid stack overflow
//  FIX: NVS size guard (3900 byte limit)
//  FIX: lastFiredHHMM initialised to -1
// ============================================================
void saveSchedulesToNVS(const char* json) {
  // FIX: guard against NVS string limit (~4000 bytes)
  if (strlen(json) > 3900) {
    Serial.println("[NVS] Schedule JSON too large — not saved.");
    return;
  }
  prefs.begin("schedules", false);
  prefs.putString("slots", json);
  prefs.end();
  Serial.println("[NVS] Schedules saved.");
}

void parseAndApplySchedules(const char* json) {
  // FIX: DynamicJsonDocument on heap instead of StaticJsonDocument on stack
  DynamicJsonDocument doc(4096);
  DeserializationError err = deserializeJson(doc, json);
  if (err) {
    Serial.printf("[Schedule] Parse error: %s\n", err.c_str());
    return;
  }
  slotCount = 0;
  for (JsonObject slot : doc.as<JsonArray>()) {
    if (slotCount >= MAX_SLOTS) break;
    scheduleSlots[slotCount].motor        = slot["motor"]   | 0;
    scheduleSlots[slotCount].hour         = slot["hour"]    | 0;
    scheduleSlots[slotCount].minute       = slot["minute"]  | 0;
    scheduleSlots[slotCount].turnOn       = strcmp(slot["action"] | "", "ON") == 0;
    scheduleSlots[slotCount].enabled      = slot["enabled"] | false;
    scheduleSlots[slotCount].lastFiredHHMM = -1;  // FIX: reset double-fire guard
    slotCount++;
  }
  Serial.printf("[Schedule] Loaded %d slot(s).\n", slotCount);
}

void loadSchedulesFromNVS() {
  prefs.begin("schedules", true);
  String json = prefs.getString("slots", "[]");
  prefs.end();
  parseAndApplySchedules(json.c_str());
}

// ============================================================
//  Schedule Checker — called every 30 s from loop()
//  FIX: double-fire guard via lastFiredHHMM
//  FIX: publishStatus() only if connected
// ============================================================
void checkSchedules() {
  if (millis() - lastScheduleCheck < 30000) return;
  lastScheduleCheck = millis();

  struct tm timeinfo;
  if (!getLocalTime(&timeinfo)) return;  // NTP not synced yet

  const int currentHHMM = timeinfo.tm_hour * 60 + timeinfo.tm_min;

  for (int i = 0; i < slotCount; i++) {
    ScheduleSlot& s = scheduleSlots[i];
    if (!s.enabled) continue;
    if (s.hour != timeinfo.tm_hour || s.minute != timeinfo.tm_min) continue;
    if (s.lastFiredHHMM == currentHHMM) continue;  // FIX: already fired this minute

    Serial.printf("[Schedule] Firing motor%d %s at %02d:%02d\n",
                  s.motor, s.turnOn ? "ON" : "OFF",
                  s.hour, s.minute);

    s.lastFiredHHMM = currentHHMM;  // FIX: mark as fired

    if (s.motor == 1) s.turnOn ? motor1Enable() : motor1Disable();
    if (s.motor == 2) s.turnOn ? motor2Enable() : motor2Disable();

    if (mqttClient.connected()) publishStatus();  // FIX: connection guard
  }
}

// ============================================================
//  GPIO Reset Button
// ============================================================
void checkResetButton() {
  if (digitalRead(RESET_BUTTON) == LOW) {
    unsigned long held = millis();
    Serial.println("[Reset] Button held — release within 3 s to cancel...");
    while (digitalRead(RESET_BUTTON) == LOW) {
      if (millis() - held >= 3000) {
        Serial.println("[Reset] Clearing WiFi credentials...");
        clearCredentials();
        delay(500);
        ESP.restart();
      }
    }
  }
}

// ============================================================
//  PROVISIONING MODE (AP + HTTP server)
// ============================================================
void handleProvisionStatus() {
  httpServer.sendHeader("Access-Control-Allow-Origin", "*");
  httpServer.send(200, "application/json", "{\"configured\":false,\"mode\":\"provisioning\"}");
}

void handleProvisionConfigure() {
  httpServer.sendHeader("Access-Control-Allow-Origin", "*");

  if (!httpServer.hasArg("plain")) {
    httpServer.send(400, "application/json", "{\"error\":\"No body\"}");
    return;
  }

  StaticJsonDocument<256> doc;
  DeserializationError err = deserializeJson(doc, httpServer.arg("plain"));

  if (err || !doc["ssid"].is<const char*>() || !doc["password"].is<const char*>()) {
    httpServer.send(400, "application/json", "{\"error\":\"Invalid JSON — need ssid and password\"}");
    return;
  }

  String ssid = doc["ssid"].as<String>();
  String pass = doc["password"].as<String>();

  Serial.printf("[Provision] Received — SSID: %s\n", ssid.c_str());

  WiFi.begin(ssid.c_str(), pass.c_str());
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    attempts++;
    Serial.print(".");
  }

  if (WiFi.status() != WL_CONNECTED) {
    WiFi.disconnect();
    httpServer.send(401, "application/json", "{\"error\":\"Could not connect — check SSID and password\"}");
    Serial.println("\n[Provision] Connection test failed.");
    return;
  }

  httpServer.send(200, "application/json", "{\"success\":true,\"message\":\"Saved! Restarting...\"}");
  delay(300);
  saveCredentials(ssid, pass);
  ESP.restart();
}

void handleCors() {
  httpServer.sendHeader("Access-Control-Allow-Origin", "*");
  httpServer.sendHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
  httpServer.sendHeader("Access-Control-Allow-Headers", "Content-Type");
  httpServer.send(204);
}

void startProvisioningMode() {
  Serial.println("[AP] Starting provisioning mode...");
  WiFi.softAP(AP_SSID, AP_PASS);
  Serial.printf("[AP] Hotspot: %s  IP: %s\n", AP_SSID, WiFi.softAPIP().toString().c_str());

  httpServer.on("/status",    HTTP_GET,     handleProvisionStatus);
  httpServer.on("/configure", HTTP_POST,    handleProvisionConfigure);
  httpServer.on("/configure", HTTP_OPTIONS, handleCors);
  httpServer.begin();

  Serial.println("[AP] HTTP server ready.");
  while (true) {
    httpServer.handleClient();
    checkResetButton();
    delay(10);
  }
}

// ============================================================
//  MQTT — message handler
//  FIX: heap-allocated msg buffer instead of VLA
// ============================================================
void onMqttMessage(char* topic, byte* payload, unsigned int length) {
  // FIX: malloc instead of VLA — avoids stack overflow on large payloads
  char* msg = (char*)malloc(length + 1);
  if (!msg) { Serial.println("[MQTT] malloc failed"); return; }
  memcpy(msg, payload, length);
  msg[length] = '\0';

  Serial.printf("[MQTT] [%s] %.80s%s\n", topic, msg, length > 80 ? "..." : "");

  if (strcmp(topic, TOPIC_MOTOR1) == 0) {
    if      (strcmp(msg, "ON")  == 0) motor1Enable();
    else if (strcmp(msg, "OFF") == 0) motor1Disable();
    publishStatus();

  } else if (strcmp(topic, TOPIC_MOTOR2) == 0) {
    if      (strcmp(msg, "ON")  == 0) motor2Enable();
    else if (strcmp(msg, "OFF") == 0) motor2Disable();
    publishStatus();

  } else if (strcmp(topic, TOPIC_WIFI_CMD) == 0) {
    if (strcmp(msg, "RESET") == 0) {
      Serial.println("[WiFi] Reset via MQTT — clearing credentials...");
      mqttClient.publish(TOPIC_ONLINE, "false", true);
      delay(300);
      clearCredentials();
      ESP.restart();
    }

  } else if (strcmp(topic, TOPIC_SCHEDULES) == 0) {
    Serial.println("[Schedule] Received updated schedule from app.");
    saveSchedulesToNVS(msg);
    parseAndApplySchedules(msg);
  }

  free(msg);  // FIX: release heap buffer
}

// ============================================================
//  MQTT — connect
// ============================================================
void connectMQTT() {
  int attempts = 0;
  while (!mqttClient.connected() && attempts < 5) {
    Serial.printf("[MQTT] Connecting... (attempt %d/5)\n", ++attempts);
    if (mqttClient.connect(MQTT_CLIENT_ID, nullptr, nullptr,
                           TOPIC_ONLINE, 0, true, "false")) {
      Serial.println("[MQTT] Connected!");
      mqttClient.publish(TOPIC_ONLINE, "true", true);
      mqttClient.subscribe(TOPIC_MOTOR1);
      mqttClient.subscribe(TOPIC_MOTOR2);
      mqttClient.subscribe(TOPIC_WIFI_CMD);
      mqttClient.subscribe(TOPIC_SCHEDULES);
      publishStatus();
      return;
    }
    Serial.printf("[MQTT] Failed (rc=%d). Retry in 5 s...\n", mqttClient.state());
    delay(5000);
  }
  if (!mqttClient.connected())
    Serial.println("[MQTT] Could not connect after 5 attempts. Will retry in loop.");
}

// ============================================================
//  Setup & Loop
// ============================================================
void setup() {
  Serial.begin(115200);

  pinMode(MOTOR1_PIN_ON,  OUTPUT);
  pinMode(MOTOR1_PIN_OFF, OUTPUT);
  pinMode(MOTOR2_PIN,     OUTPUT);
  pinMode(RESET_BUTTON,   INPUT_PULLUP);

  digitalWrite(MOTOR1_PIN_ON,  LOW);
  digitalWrite(MOTOR1_PIN_OFF, LOW);
  digitalWrite(MOTOR2_PIN,     LOW);

  String savedSSID = getSavedSSID();
  if (savedSSID.length() == 0) {
    startProvisioningMode(); // never returns
  }

  Serial.printf("[WiFi] Connecting to: %s\n", savedSSID.c_str());
  WiFi.begin(savedSSID.c_str(), getSavedPassword().c_str());

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
    if (++attempts > 40) {
      Serial.println("\n[WiFi] Timeout — will retry in loop.");
      break;
    }
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\n[WiFi] Connected. IP: %s\n", WiFi.localIP().toString().c_str());

    // NTP sync
    configTime(UTC_OFFSET_SECONDS, 0, "pool.ntp.org", "time.nist.gov");
    Serial.print("[NTP] Syncing time");
    struct tm timeinfo;
    int ntpAttempts = 0;
    while (!getLocalTime(&timeinfo) && ntpAttempts < 10) {
      delay(500);
      Serial.print(".");
      ntpAttempts++;
    }
    if (getLocalTime(&timeinfo))
      Serial.printf("\n[NTP] Synced: %02d:%02d\n", timeinfo.tm_hour, timeinfo.tm_min);
    else
      Serial.println("\n[NTP] Sync failed — schedules will fire once time is available.");
  }

  mqttClient.setServer(MQTT_BROKER, MQTT_PORT);
  mqttClient.setCallback(onMqttMessage);
  mqttClient.setBufferSize(4096);
  mqttClient.setSocketTimeout(10);

  loadSchedulesFromNVS();
  connectMQTT();
}

void loop() {
  checkResetButton();

  if (WiFi.status() != WL_CONNECTED) {
    WiFi.reconnect();
    delay(1000);
    return;
  }

  if (!mqttClient.connected()) {
    connectMQTT();
  }

  mqttClient.loop();
  checkSchedules();
}
