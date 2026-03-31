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
 *  PUB  esp32/status              {"motor1":bool,"motor2":bool,"wifi":"SSID"}
 *  PUB  esp32/online              true | false  (LWT)
 *
 * Required Libraries:
 *   • PubSubClient  (Nick O'Leary)
 *   • ArduinoJson   (Benoit Blanchon v6+)
 *   • Preferences   (built-in ESP32 core — no install needed)
 */

#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

// ============================================================
//  MQTT Config
// ============================================================
const char* MQTT_BROKER    = "broker.hivemq.com";
const int   MQTT_PORT      = 1883;
const char* MQTT_CLIENT_ID = "esp32-motor-001";

const char* TOPIC_MOTOR1   = "esp32/motor1/control";
const char* TOPIC_MOTOR2   = "esp32/motor2/control";
const char* TOPIC_WIFI_CMD = "esp32/system/wifi";
const char* TOPIC_STATUS   = "esp32/status";
const char* TOPIC_ONLINE   = "esp32/online";

// ============================================================
//  AP Config (provisioning mode)
// ============================================================
const char* AP_SSID = "ESP32-Setup";   // hotspot name Flutter connects to
const char* AP_PASS = "";              // no password — easy to connect

// ============================================================
//  Pin Definitions
// ============================================================
const int MOTOR1_PIN_ON  = 26;   // Motor 1: dual-pin latching relay
const int MOTOR1_PIN_OFF = 27;
const int MOTOR2_PIN     = 25;   // Motor 2: single-pin relay
const int RESET_BUTTON   = 0;    // GPIO 0 (BOOT button on most ESP32 dev boards)

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
//  NVS Helpers
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
//  GPIO Reset Button
//  Hold BOOT button for 3 s → clear WiFi → restart into AP mode
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

  // Test the credentials before saving
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

  // Valid credentials — save and restart
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
  Serial.printf("[AP] Hotspot started: %s\n", AP_SSID);
  Serial.printf("[AP] IP: %s\n", WiFi.softAPIP().toString().c_str());

  httpServer.on("/status",    HTTP_GET,     handleProvisionStatus);
  httpServer.on("/configure", HTTP_POST,    handleProvisionConfigure);
  httpServer.on("/configure", HTTP_OPTIONS, handleCors);
  httpServer.begin();

  Serial.println("[AP] HTTP server ready. Waiting for Flutter to send credentials...");

  // Stay in AP mode loop until credentials are received (handled by restart inside handler)
  while (true) {
    httpServer.handleClient();
    checkResetButton();
    delay(10);
  }
}

// ============================================================
//  MQTT
// ============================================================
void publishStatus() {
  StaticJsonDocument<128> doc;
  doc["motor1"] = motor1_state;
  doc["motor2"] = motor2_state;
  doc["wifi"]   = WiFi.SSID();

  char buf[128];
  serializeJson(doc, buf);
  mqttClient.publish(TOPIC_STATUS, buf, true);
  Serial.printf("[MQTT] Status: %s\n", buf);
}

void onMqttMessage(char* topic, byte* payload, unsigned int length) {
  char msg[length + 1];
  memcpy(msg, payload, length);
  msg[length] = '\0';
  Serial.printf("[MQTT] [%s] %s\n", topic, msg);

  if (strcmp(topic, TOPIC_MOTOR1) == 0) {
    if      (strcmp(msg, "ON")  == 0) motor1Enable();
    else if (strcmp(msg, "OFF") == 0) motor1Disable();

  } else if (strcmp(topic, TOPIC_MOTOR2) == 0) {
    if      (strcmp(msg, "ON")  == 0) motor2Enable();
    else if (strcmp(msg, "OFF") == 0) motor2Disable();

  } else if (strcmp(topic, TOPIC_WIFI_CMD) == 0) {
    if (strcmp(msg, "RESET") == 0) {
      Serial.println("[WiFi] Reset command received via MQTT — clearing credentials...");
      mqttClient.publish(TOPIC_ONLINE, "false", true);
      delay(300);
      clearCredentials();
      ESP.restart();
    }
  }

  publishStatus();
}

void connectMQTT() {
  while (!mqttClient.connected()) {
    Serial.printf("[MQTT] Connecting to %s...", MQTT_BROKER);
    // Last Will: marks device offline if it drops unexpectedly
    if (mqttClient.connect(MQTT_CLIENT_ID, nullptr, nullptr,
                           TOPIC_ONLINE, 0, true, "false")) {
      Serial.println(" Connected!");
      mqttClient.publish(TOPIC_ONLINE, "true", true);
      mqttClient.subscribe(TOPIC_MOTOR1);
      mqttClient.subscribe(TOPIC_MOTOR2);
      mqttClient.subscribe(TOPIC_WIFI_CMD);
      publishStatus();
    } else {
      Serial.printf(" Failed (rc=%d). Retry in 5 s...\n", mqttClient.state());
      delay(5000);
    }
  }
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
    // ── No credentials saved → provisioning mode ──
    startProvisioningMode(); // never returns — restarts when creds received
  }

  // ── Normal mode: connect to saved WiFi ──
  Serial.printf("[WiFi] Connecting to: %s\n", savedSSID.c_str());
  WiFi.begin(savedSSID.c_str(), getSavedPassword().c_str());

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
    attempts++;
    if (attempts > 40) { // 20 s timeout — WiFi may be down, still boot into MQTT
      Serial.println("\n[WiFi] Could not connect. Will retry via loop.");
      break;
    }
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\n[WiFi] Connected. IP: %s\n", WiFi.localIP().toString().c_str());
  }

  mqttClient.setServer(MQTT_BROKER, MQTT_PORT);
  mqttClient.setCallback(onMqttMessage);
  connectMQTT();
}

void loop() {
  checkResetButton();

  // Reconnect WiFi if dropped
  if (WiFi.status() != WL_CONNECTED) {
    WiFi.reconnect();
    delay(1000);
    return;
  }

  // Reconnect MQTT if dropped
  if (!mqttClient.connected()) {
    connectMQTT();
  }

  mqttClient.loop();
}
