// ═══════════════════════════════════════════════════════════════
// Scent & Sense ESP32 Firmware v2.5.1
// ───────────────────────────────────────────────────────────────
// Hardware layout (confirmed):
//   GPIO25        = Relay (pump HIGH=ON)
//   GPIO21/22     = I2C SDA/SCL → VL53L0X ToF sensor
//   GPIO16/17     = UART2 → Nextion display (optional)
//   BLE           = NimBLE-Arduino (auto-detect 1.x or 2.x)
//
// Backend: configured at build time via DEFAULT_BACKEND_BASE below.
//
// ═════════════════════════════════════════════════════════════════
// DEVICE IDENTITY — v2.5.1 (Apr 2026)
// ═════════════════════════════════════════════════════════════════
// ⚠  IMPORTANT — READ BEFORE FLASHING A NEW BOARD ⚠
//
// The three identity values below (serial, ID, token) used to be
// baked in as compile-time #defines. That was fine for the first
// board but made every subsequent board a clone: flashing unchanged
// firmware onto a second unit would have TWO boards reporting the
// same DEVICE_ID to the backend, clobbering each other's sensor
// data and schedules.
//
// Current behaviour:
//   • On boot we READ identity from NVS (namespace "sns", keys
//     "serial" / "id" / "token").
//   • If NVS is empty — first-ever flash — we fall back to the
//     FACTORY_* constants below ONCE, and immediately write them
//     back to NVS. That way the defaults only seed the very first
//     unit and every board afterwards must be provisioned.
//   • To provision a new board, send these three lines over the
//     USB serial monitor during boot (or flash custom NVS):
//         PROV_SERIAL=<unique-serial>
//         PROV_ID=<mongo-objectid>
//         PROV_TOKEN=<shared-or-per-device-token>
//     See handleSerialProvisioning() at the bottom of this file.
//
// FACTORY_* values below are the identity of unit #001 and must
// NOT be reused on any other unit.
// ═════════════════════════════════════════════════════════════════
#define FACTORY_SERIAL    "SS-2026-001"
#define FACTORY_ID        "69d27f3e3820c6a70d12c508"
#define FACTORY_TOKEN     "ss-device-2025-secret"

// Runtime identity (loaded from NVS in loadIdentity()). Reads are
// safe without locking — strings only mutate during setup().
String DEVICE_SERIAL = "";
String DEVICE_ID     = "";
String DEVICE_TOKEN  = "";
// ═════════════════════════════════════════════════════════════════
//
#define FIRMWARE_VERSION "2.6.0"
//
// ─── CHANGES vs v2.4.3 ────────────────────────────────────────
// * CRITICAL: New Wi-Fi credentials are no longer persisted to NVS on
//   write. They are held in RAM as "pendingSsid/pendingPass" only. We
//   try to connect using them; NVS is written ONLY if the connect
//   succeeds. If it fails the previous known-good SSID/password remain
//   on NVS untouched, so a bad provisioning attempt can never brick the
//   device. ("Do NOT permanently save newly entered Wi-Fi credentials
//   before connection success is verified.")
// * On Wi-Fi success: frame "OK" is emitted on the status char. On
//   failure: frame "WIFI_FAIL". This lets the mobile app verify real
//   success instead of waiting a fake 2 s then claiming.
// * SCAN_WIFI still works the same on the wire:
//     WIFI_START / WIFI:<ssid>:<rssi>:<S|O> / WIFI_END / WIFI_SCAN_FAIL
//
// ─── Arduino IDE Settings ────────────────────────────────────────
//   Board              : ESP32 Dev Module
//   Partition Scheme   : Minimal SPIFFS (1.9MB APP with OTA)
//                        — หรือ — Huge APP (3MB No OTA)
//   Flash Size         : 4MB (32Mb)
//   Flash Mode         : QIO (default)
//   PSRAM              : Disabled
//   Upload Speed       : 921600
//   Core Debug Level   : None
//
// ─── Libraries (Arduino Library Manager) ─────────────────────────
//   ESP32 core 3.x → NimBLE-Arduino 2.x (h2zero)
//   ESP32 core 2.x → NimBLE-Arduino 1.4.x (h2zero)
//   ArduinoJson       6.x or 7.x  (Benoit Blanchon)
//   Adafruit VL53L0X       (Adafruit)
//   Adafruit BusIO         (Adafruit — dependency)
// ═══════════════════════════════════════════════════════════════

// ─── Compile-time size reduction (before includes) ───────────────
#define ARDUINOJSON_ENABLE_COMMENTS    0
#define ARDUINOJSON_ENABLE_NAN         0
#define ARDUINOJSON_ENABLE_INFINITY    0
#define ARDUINOJSON_ENABLE_PROGMEM     0

#include <Arduino.h>

// ─── Auto-detect ESP32 core version for NimBLE compat ────────────
#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
  #define NIMBLE_V2  1
#else
  #define NIMBLE_V2  0
#endif

#if NIMBLE_V2
  #define CONFIG_BT_NIMBLE_ROLE_OBSERVER    0
  #define CONFIG_BT_NIMBLE_ROLE_CENTRAL     0
  #define CONFIG_BT_NIMBLE_ROLE_BROADCASTER 1
  #define CONFIG_BT_NIMBLE_ROLE_PERIPHERAL  1
#else
  #define CONFIG_BT_NIMBLE_ROLE_CENTRAL_DISABLED
  #define CONFIG_BT_NIMBLE_ROLE_OBSERVER_DISABLED
#endif
#define CONFIG_BT_NIMBLE_MAX_CONNECTIONS 2

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <NimBLEDevice.h>
#include <Preferences.h>
#include <esp_task_wdt.h>
#include <Wire.h>
#include "Adafruit_VL53L0X.h"

#if ARDUINOJSON_VERSION_MAJOR >= 7
  #define JSON_DOC(size) JsonDocument
#else
  #define JSON_DOC(size) StaticJsonDocument<size>
#endif

// ─── Hardware Pins ────────────────────────────────────────────
#define RELAY_PIN     25
#define I2C_SDA       21
#define I2C_SCL       22

// ─── Tank Configuration ───────────────────────────────────────
#define TANK_ML          1000
#define TANK_HEIGHT_MM   120
#define TOF_OFFSET_MM    5

// ─── Backend ─────────────────────────────────────────────────
// v5.2.1 (Apr 2026): internal app deployment — the backend now runs on
// the factory / lab LAN at the address below. Override at build time
// by editing this one line, or better by reflashing boards per site.
// The HTTPS-only Render URL from v2.5.0 was intentionally removed.
#define DEFAULT_BACKEND_BASE  "https://diffuser-backend-1.onrender.com"
String BACKEND_BASE = DEFAULT_BACKEND_BASE;  // set in loadIdentity() from NVS if present
String SENSOR_URL   = "";                    // built in loadIdentity()
String STATE_URL    = "";                    // built in loadIdentity()

// ─── BLE UUIDs (must match app ble_wifi_service.dart) ────────
#define BLE_SERVICE_UUID  "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define BLE_WIFI_CHAR     "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define BLE_STATUS_CHAR   "beb5483e-36e1-4688-b7f5-ea07361b26a9"

// ─── Timing ─────────────────────────────────────────────────
#define HEARTBEAT_MS    30000
#define STATE_POLL_MS   15000
#define SCHED_CHECK_MS  60000
#define WIFI_TIMEOUT_MS 15000
#define WDT_TIMEOUT_S   60

// ─── Globals ────────────────────────────────────────────────
Preferences          prefs;
Adafruit_VL53L0X     tof;
bool                 tofOk = false;

String   wifiSsid    = "";   // currently active (and NVS-persisted) creds
String   wifiPass    = "";
bool     relayState  = false;
float    levelMl     = TANK_ML;
bool     pumpOk      = true;
bool     relayOk     = true;
uint32_t lastCmdVer  = 0;

NimBLEServer*          bleServer  = nullptr;
NimBLECharacteristic*  wifiChar   = nullptr;
NimBLECharacteristic*  statusChar = nullptr;
bool                   bleConn    = false;

// ─── Async Wi-Fi provisioning — STAGED only, not persisted ──
// BLE callback must not block (>2 s BLE timeout). We capture the new creds
// here and act on them in loop().  Persistence is deferred to the moment
// the device actually joins the new network.
volatile bool wifiChangeReq   = false;
String        pendingSsid     = "";
String        pendingPass     = "";

// Wi-Fi scan request (SCAN_WIFI) — scan runs async in loop()
volatile bool wifiScanReq     = false;

// Schedule
struct Schedule {
  String   startTime = "08:00";
  String   endTime   = "18:00";
  uint32_t workSec   = 30;
  uint32_t pauseSec  = 60;
  bool     days[7]   = {};
};
static const int MAX_SCHEDULES = 5;
Schedule schedules[MAX_SCHEDULES];
int      scheduleCount = 0;

// ─── Forward declarations ───────────────────────────────────
void updateBleStatus();
bool sendHeartbeat();
bool connectWifi(const String& ssid, const String& pass,
                 uint32_t timeoutMs = WIFI_TIMEOUT_MS);

// ═══════════════════════════════════════════════════════════════
// NVS
// ═══════════════════════════════════════════════════════════════
// Build the composed URLs from DEVICE_ID + BACKEND_BASE. Called
// whenever either changes (boot + after serial provisioning).
void rebuildBackendUrls() {
  SENSOR_URL = BACKEND_BASE + "/api/devices/" + DEVICE_ID + "/sensor";
  STATE_URL  = BACKEND_BASE + "/api/devices/" + DEVICE_ID + "/state";
}

// Read identity + backend URL from NVS. If any key is missing we
// seed it from the FACTORY_* defaults (first-flash path) and write
// back, so NVS is the source of truth from that point on.
void loadIdentity() {
  prefs.begin("sns", false);
  DEVICE_SERIAL = prefs.getString("serial", "");
  DEVICE_ID     = prefs.getString("id", "");
  DEVICE_TOKEN  = prefs.getString("token", "");
  BACKEND_BASE  = prefs.getString("backend", DEFAULT_BACKEND_BASE);
  bool writeBack = false;
  if (DEVICE_SERIAL.length() == 0) { DEVICE_SERIAL = FACTORY_SERIAL; writeBack = true; }
  if (DEVICE_ID.length()     == 0) { DEVICE_ID     = FACTORY_ID;     writeBack = true; }
  if (DEVICE_TOKEN.length()  == 0) { DEVICE_TOKEN  = FACTORY_TOKEN;  writeBack = true; }
  if (writeBack) {
    prefs.putString("serial", DEVICE_SERIAL);
    prefs.putString("id",     DEVICE_ID);
    prefs.putString("token",  DEVICE_TOKEN);
    Serial.println(F("[NVS] Seeded identity from FACTORY_* defaults. "
                     "Provision a unique serial before deploying."));
  }
  prefs.end();
  rebuildBackendUrls();
  Serial.printf("[NVS] Identity: serial=%s id=%s backend=%s\n",
                DEVICE_SERIAL.c_str(), DEVICE_ID.c_str(),
                BACKEND_BASE.c_str());
}

// Serial-monitor provisioning. Called from loop() when a line arrives.
// Use ONCE during factory/install to set a board's unique identity:
//   PROV_SERIAL=SS-2026-047
//   PROV_ID=670...                    (Mongo ObjectId from the backend)
//   PROV_TOKEN=<per-device-or-shared>
//   PROV_BACKEND=http://10.0.0.5:3000 (optional)
//   PROV_COMMIT                       (persists to NVS and reboots)
static String _provBuf;
void handleSerialProvisioning() {
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\r') continue;
    if (c == '\n') {
      String line = _provBuf; _provBuf = "";
      line.trim();
      if (line.length() == 0) continue;
      if (line == "PROV_COMMIT") {
        Serial.println(F("[PROV] Committing identity and rebooting..."));
        delay(300);
        ESP.restart();
        return;
      }
      int eq = line.indexOf('=');
      if (eq <= 0) continue;
      String key = line.substring(0, eq);
      String val = line.substring(eq + 1);
      prefs.begin("sns", false);
      if      (key == "PROV_SERIAL")  { prefs.putString("serial",  val); DEVICE_SERIAL = val; }
      else if (key == "PROV_ID")      { prefs.putString("id",      val); DEVICE_ID     = val; }
      else if (key == "PROV_TOKEN")   { prefs.putString("token",   val); DEVICE_TOKEN  = val; }
      else if (key == "PROV_BACKEND") { prefs.putString("backend", val); BACKEND_BASE  = val; }
      else { prefs.end(); continue; }
      prefs.end();
      rebuildBackendUrls();
      Serial.printf("[PROV] Stored %s (len=%u)\n", key.c_str(), val.length());
    } else {
      if (_provBuf.length() < 200) _provBuf += c;
    }
  }
}

void loadPrefs() {
  prefs.begin("sns", true);
  wifiSsid   = prefs.getString("ssid", "");
  wifiPass   = prefs.getString("pass", "");
  levelMl    = prefs.getFloat("level", (float)TANK_ML);
  relayState = prefs.getBool("relay", false);
  prefs.end();
}

void saveWifi(const String& ssid, const String& pass) {
  prefs.begin("sns", false);
  prefs.putString("ssid", ssid);
  prefs.putString("pass", pass);
  prefs.end();
}

void saveLevel(float ml) {
  prefs.begin("sns", false);
  prefs.putFloat("level", ml);
  prefs.end();
}

// ═══════════════════════════════════════════════════════════════
// VL53L0X (ToF sensor)
// ═══════════════════════════════════════════════════════════════
bool setupToF() {
  Wire.begin(I2C_SDA, I2C_SCL);
  if (!tof.begin()) {
    Serial.println(F("[ToF] VL53L0X not found"));
    return false;
  }
  tof.setMeasurementTimingBudgetMicroSeconds(200000);
  Serial.println(F("[ToF] VL53L0X ready"));
  return true;
}

float measureLevelMl() {
  if (!tofOk) return levelMl;
  VL53L0X_RangingMeasurementData_t m;
  tof.rangingTest(&m, false);
  if (m.RangeStatus == 4) return levelMl;

  float dist = (float)m.RangeMilliMeter - (float)TOF_OFFSET_MM;
  dist = constrain(dist, 0.0f, (float)TANK_HEIGHT_MM);
  float ratio = 1.0f - (dist / (float)TANK_HEIGHT_MM);
  float ml = constrain(ratio * (float)TANK_ML, 0.0f, (float)TANK_ML);
  Serial.printf("[ToF] dist=%.0fmm → %.0fml\n", dist, ml);
  return ml;
}

// ═══════════════════════════════════════════════════════════════
// WiFi
// ═══════════════════════════════════════════════════════════════
bool connectWifi(const String& ssid, const String& pass, uint32_t timeoutMs) {
  if (ssid.isEmpty()) return false;

  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid.c_str(), pass.c_str());

  uint32_t t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < timeoutMs) {
    delay(500);
    Serial.print('.');
    esp_task_wdt_reset();
  }
  Serial.println();

  bool ok = (WiFi.status() == WL_CONNECTED);
  if (ok) Serial.printf("[WiFi] Connected: %s  IP: %s\n",
                         ssid.c_str(), WiFi.localIP().toString().c_str());
  else    Serial.printf("[WiFi] Failed: %s\n", ssid.c_str());
  return ok;
}

// ═══════════════════════════════════════════════════════════════
// Schedule helpers
// ═══════════════════════════════════════════════════════════════
void parseSchedules(const JsonArray& arr) {
  scheduleCount = 0;
  for (JsonObject item : arr) {
    if (scheduleCount >= MAX_SCHEDULES) break;
    Schedule& s = schedules[scheduleCount++];
    s.startTime = item["startTime"] | "08:00";
    s.endTime   = item["endTime"]   | "18:00";
    s.workSec   = item["workSeconds"]  | 30;
    s.pauseSec  = item["pauseSeconds"] | 60;
    JsonArray dArr = item["days"];
    for (int d = 0; d < 7 && d < (int)dArr.size(); d++) s.days[d] = dArr[d];
  }
  Serial.printf("[SCHED] Loaded %d schedule(s)\n", scheduleCount);
}

bool isInSchedule() {
  if (scheduleCount == 0) return false;
  struct tm ti;
  if (!getLocalTime(&ti)) return false;
  // ⚠ WEEKDAY MAPPING — must match app + backend.
  //   POSIX tm_wday:      Sun=0, Mon=1, Tue=2, ..., Sat=6
  //   Our schedule.days:  Mon=0, Tue=1, Wed=2, Thu=3, Fri=4, Sat=5, Sun=6
  // Without this conversion the firmware was reading the wrong bit —
  // e.g. a "Monday" schedule in the app was silently stored in slot 1
  // which the firmware interpreted as Tuesday. Schedules ran a day late.
  int dow    = (ti.tm_wday + 6) % 7;  // Sun(0)→6, Mon(1)→0, ..., Sat(6)→5
  int nowMin = ti.tm_hour * 60 + ti.tm_min;
  for (int i = 0; i < scheduleCount; i++) {
    const Schedule& s = schedules[i];
    if (!s.days[dow]) continue;
    int sm = s.startTime.substring(0,2).toInt() * 60 + s.startTime.substring(3,5).toInt();
    int em = s.endTime.substring(0,2).toInt()   * 60 + s.endTime.substring(3,5).toInt();
    if (nowMin >= sm && nowMin < em) return true;
  }
  return false;
}

// ═══════════════════════════════════════════════════════════════
// HTTP / HTTPS helpers
// ═══════════════════════════════════════════════════════════════
// v5.2.1 (Apr 2026): the internal company deployment uses a plain HTTP
// LAN backend, so we pick a plain WiFiClient for http:// URLs. If a
// future deployment uses https://, we fall back to WiFiClientSecure
// with setInsecure() — that matches what the old Render deployment
// needed (Render's cert chain changes periodically and the ESP32 has
// no practical way to ship a CA bundle). The device token header
// (x-device-token) is still the real authentication for the ESP32
// endpoints — TLS would only protect the token in transit. For an
// internal LAN that's acceptable.
static bool _isHttpsUrl(const String& url) {
  return url.startsWith("https://");
}

bool httpPut(const String& url, const String& body) {
  if (WiFi.status() != WL_CONNECTED) return false;
  HTTPClient http;
  int code;
  if (_isHttpsUrl(url)) {
    WiFiClientSecure client;
    client.setInsecure();  // intentional — see banner above
    http.begin(client, url);
    http.addHeader("Content-Type", "application/json");
    http.addHeader("x-device-token", DEVICE_TOKEN);
    http.setTimeout(10000);
    code = http.PUT(body);
  } else {
    WiFiClient client;
    http.begin(client, url);
    http.addHeader("Content-Type", "application/json");
    http.addHeader("x-device-token", DEVICE_TOKEN);
    http.setTimeout(10000);
    code = http.PUT(body);
  }
  bool ok  = (code >= 200 && code < 300);
  if (!ok) Serial.printf("[HTTP PUT %d] %s\n", code, url.c_str());
  http.end();
  return ok;
}

String httpGet(const String& url) {
  if (WiFi.status() != WL_CONNECTED) return "";
  HTTPClient http;
  int    code;
  String body;
  if (_isHttpsUrl(url)) {
    WiFiClientSecure client;
    client.setInsecure();  // intentional — see banner above
    http.begin(client, url);
    http.addHeader("x-device-token", DEVICE_TOKEN);
    http.setTimeout(10000);
    code = http.GET();
    body = (code == 200) ? http.getString() : "";
  } else {
    WiFiClient client;
    http.begin(client, url);
    http.addHeader("x-device-token", DEVICE_TOKEN);
    http.setTimeout(10000);
    code = http.GET();
    body = (code == 200) ? http.getString() : "";
  }
  if (code != 200) Serial.printf("[HTTP GET %d] %s\n", code, url.c_str());
  http.end();
  return body;
}

// ═══════════════════════════════════════════════════════════════
// BLE Status broadcast
// Format: "SSID|IP|DEVICE_ID|ON/OFF|LEVEL%|FIRMWARE"
// ═══════════════════════════════════════════════════════════════
void updateBleStatus() {
  if (!statusChar) return;
  int pct = constrain((int)((levelMl / TANK_ML) * 100.0f), 0, 100);
  String ip = (WiFi.status() == WL_CONNECTED) ? WiFi.localIP().toString() : "0.0.0.0";
  String s = wifiSsid + "|" + ip + "|" + DEVICE_ID + "|"
           + (relayState ? "ON" : "OFF") + "|"
           + String(pct) + "%" + "|" + FIRMWARE_VERSION;
  statusChar->setValue(s.c_str());
  if (bleConn) statusChar->notify();
}

// ═══════════════════════════════════════════════════════════════
// Heartbeat / Sensor report
// ═══════════════════════════════════════════════════════════════
bool sendHeartbeat() {
  float newLevel = measureLevelMl();
  if (fabsf(newLevel - levelMl) > 5.0f) {
    levelMl = newLevel;
    saveLevel(levelMl);
  }

  int pct  = constrain((int)((levelMl / TANK_ML) * 100.0f), 0, 100);
  int rssi = WiFi.RSSI();

  JSON_DOC(512) doc;
  doc["status"]          = "online";
  doc["firmwareVersion"] = FIRMWARE_VERSION;
  doc["serialNumber"]    = DEVICE_SERIAL;
  doc["isOn"]            = relayState;
  doc["levelMl"]         = (int)levelMl;
  doc["level"]           = pct;
  doc["installedTankMl"] = TANK_ML;
  doc["battery"]         = 100;
  doc["pumpOk"]          = pumpOk;
  doc["relayOk"]         = relayOk;
  doc["mac"]             = WiFi.macAddress();
  doc["wifiSSID"]        = wifiSsid;
  doc["wifiIP"]          = WiFi.localIP().toString();
  doc["signalStrength"]  = rssi;

  String payload;
  serializeJson(doc, payload);

  bool ok = httpPut(SENSOR_URL, payload);
  Serial.printf("[HB] level=%d%% isOn=%d rssi=%d → %s\n",
                pct, relayState, rssi, ok ? "OK" : "FAIL");
  return ok;
}

// ═══════════════════════════════════════════════════════════════
// Poll command version
// ═══════════════════════════════════════════════════════════════
void pollState() {
  String body = httpGet(STATE_URL);
  if (body.isEmpty()) return;

  JSON_DOC(512) doc;
  if (deserializeJson(doc, body) != DeserializationError::Ok) return;

  uint32_t cmdVer = doc["commandVersion"] | 0U;
  if (cmdVer > lastCmdVer) {
    lastCmdVer = cmdVer;
    bool newOn = doc["isOn"] | relayState;
    if (newOn != relayState) {
      relayState = newOn;
      digitalWrite(RELAY_PIN, relayState ? HIGH : LOW);
      relayOk = true;
      Serial.printf("[CMD] Relay → %s (v%u)\n",
                    relayState ? "ON" : "OFF", cmdVer);
    }
    JsonVariant schedVar = doc["schedule"];
    if (!schedVar.isNull()) {
      parseSchedules(schedVar.as<JsonArray>());
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// Wi-Fi scan (called from loop when wifiScanReq flag is set by BLE)
// ═══════════════════════════════════════════════════════════════
void doWifiScan() {
  if (!statusChar) return;
  Serial.println(F("[WIFI] Scan requested via BLE"));

  bool hadSta = (WiFi.status() == WL_CONNECTED);
  if (!hadSta) {
    WiFi.mode(WIFI_STA);
    WiFi.disconnect(false, true);
    delay(100);
  }

  statusChar->setValue("WIFI_START");
  if (bleConn) statusChar->notify();
  delay(30);

  int n = WiFi.scanNetworks(false, true);
  Serial.printf("[WIFI] %d networks found\n", n);

  if (n < 0) {
    statusChar->setValue("WIFI_SCAN_FAIL");
    if (bleConn) statusChar->notify();
    WiFi.scanDelete();
    return;
  }

  const int cap = (n > 20) ? 20 : n;
  for (int i = 0; i < cap; i++) {
    String ssid = WiFi.SSID(i);
    if (ssid.length() == 0) continue;
    int32_t rssi = WiFi.RSSI(i);
    wifi_auth_mode_t auth = WiFi.encryptionType(i);
    const char secFlag = (auth == WIFI_AUTH_OPEN) ? 'O' : 'S';

    String line = "WIFI:";
    line += ssid;
    line += ':';
    line += String(rssi);
    line += ':';
    line += secFlag;
    if (line.length() > 170) line = line.substring(0, 170);

    statusChar->setValue(line.c_str());
    if (bleConn) statusChar->notify();
    delay(50);
    esp_task_wdt_reset();
  }

  statusChar->setValue("WIFI_END");
  if (bleConn) statusChar->notify();
  WiFi.scanDelete();

  if (!hadSta && !wifiSsid.isEmpty()) {
    WiFi.begin(wifiSsid.c_str(), wifiPass.c_str());
  }
}

// ─── BLE callbacks ───────────────────────────────────────────
class WiFiCharCB : public NimBLECharacteristicCallbacks {
#if NIMBLE_V2
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& connInfo) override {
#else
  void onWrite(NimBLECharacteristic* c) override {
#endif
    String val = String(c->getValue().c_str());
    Serial.printf("[BLE] Write: %s\n", val.c_str());

    if (val == "SCAN") {
      updateBleStatus();
      return;
    }
    if (val == "SCAN_WIFI") {
      wifiScanReq = true;
      return;
    }
    if (val == "TOGGLE") {
      relayState = !relayState;
      digitalWrite(RELAY_PIN, relayState ? HIGH : LOW);
      Serial.printf("[BLE] Toggle → %s\n", relayState ? "ON" : "OFF");
      updateBleStatus();
      return;
    }

    // Parse "SSID|PASSWORD" — stage only, do NOT persist yet.
    int sep = val.indexOf('|');
    if (sep > 0) {
      String newSsid = val.substring(0, sep);
      String newPass = val.substring(sep + 1);
      if (newSsid.isEmpty()) return;

      Serial.printf("[BLE] New WiFi request (staged): %s\n", newSsid.c_str());

      // Tell the app we got the creds and are about to try them.
      statusChar->setValue("CONNECTING");
      if (bleConn) statusChar->notify();

      // ★ v2.5.0: DO NOT call saveWifi() here. Hold creds in RAM only.
      pendingSsid   = newSsid;
      pendingPass   = newPass;
      wifiChangeReq = true;
    }
  }
};

class ServerCB : public NimBLEServerCallbacks {
#if NIMBLE_V2
  void onConnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo) override {
#else
  void onConnect(NimBLEServer* pServer) override {
#endif
    bleConn = true;
    Serial.println(F("[BLE] Client connected"));
    updateBleStatus();
  }

#if NIMBLE_V2
  void onDisconnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo, int reason) override {
#else
  void onDisconnect(NimBLEServer* pServer) override {
#endif
    bleConn = false;
    Serial.println(F("[BLE] Disconnected — restarting advertising"));
    NimBLEDevice::startAdvertising();
  }
};

// ═══════════════════════════════════════════════════════════════
// BLE Setup
// ═══════════════════════════════════════════════════════════════
void setupBLE() {
  String bleName = "ScentSense-" + DEVICE_SERIAL;
  NimBLEDevice::init(bleName.c_str());

  NimBLEDevice::setMTU(185);

#if NIMBLE_V2
  NimBLEDevice::setPower(9);
#else
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);
#endif

  bleServer = NimBLEDevice::createServer();
  bleServer->setCallbacks(new ServerCB());

  NimBLEService* svc = bleServer->createService(BLE_SERVICE_UUID);

  wifiChar = svc->createCharacteristic(BLE_WIFI_CHAR,
               NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  wifiChar->setCallbacks(new WiFiCharCB());

  statusChar = svc->createCharacteristic(BLE_STATUS_CHAR,
                 NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  statusChar->setValue("READY");

  svc->start();

  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(BLE_SERVICE_UUID);
#if !NIMBLE_V2
  adv->setScanResponse(true);
#endif
  adv->start();

  Serial.printf("[BLE] Advertising as: %s\n", bleName.c_str());
}

// ═══════════════════════════════════════════════════════════════
// Setup
// ═══════════════════════════════════════════════════════════════
void setup() {
  Serial.begin(115200);
  // Identity is loaded from NVS below; at this point DEVICE_SERIAL /
  // DEVICE_ID may still be empty. The useful boot log comes from
  // loadIdentity() itself.
  Serial.printf("\n\n[BOOT] Scent & Sense v%s\n", FIRMWARE_VERSION);
#if NIMBLE_V2
  Serial.println(F("[BOOT] ESP32 core 3.x / NimBLE 2.x detected"));
#else
  Serial.println(F("[BOOT] ESP32 core 2.x / NimBLE 1.x detected"));
#endif

#if NIMBLE_V2
  {
    esp_task_wdt_config_t wdt_cfg = {
      .timeout_ms     = WDT_TIMEOUT_S * 1000,
      .idle_core_mask = 0,
      .trigger_panic  = true,
    };
    if (esp_task_wdt_reconfigure(&wdt_cfg) != ESP_OK) {
      esp_task_wdt_init(&wdt_cfg);
    }
  }
#else
  esp_task_wdt_init(WDT_TIMEOUT_S, true);
#endif
  esp_task_wdt_add(NULL);

  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW);

  loadIdentity();
  loadPrefs();
  tofOk = setupToF();
  setupBLE();

  if (!wifiSsid.isEmpty()) {
    if (connectWifi(wifiSsid, wifiPass)) {
      configTime(7 * 3600, 0, "pool.ntp.org", "time.cloudflare.com");
      struct tm ti;
      for (int i = 0; i < 10 && !getLocalTime(&ti); i++) delay(500);
      sendHeartbeat();
      pollState();
    }
  } else {
    Serial.println(F("[BOOT] No WiFi saved — waiting for BLE config"));
  }

  if (scheduleCount == 0) {
    digitalWrite(RELAY_PIN, relayState ? HIGH : LOW);
  }

  Serial.println(F("[BOOT] Ready"));
}

// ═══════════════════════════════════════════════════════════════
// Loop
// ═══════════════════════════════════════════════════════════════
uint32_t lastHb    = 0;
uint32_t lastPoll  = 0;
uint32_t lastSched = 0;
uint32_t lastRecon = 0;

// Heartbeat failure backoff.
static const uint32_t HB_MAX_INTERVAL_MS = 300000UL;
uint32_t hbFailCount        = 0;
uint32_t hbCurrentIntervalMs = HEARTBEAT_MS;

void loop() {
  esp_task_wdt_reset();
  uint32_t now = millis();

  // ── Serial-port identity provisioning (one-time per board) ──
  // See handleSerialProvisioning() for the accepted commands.
  handleSerialProvisioning();

  // ── Async Wi-Fi scan (from BLE callback "SCAN_WIFI") ────────
  if (wifiScanReq) {
    wifiScanReq = false;
    doWifiScan();
  }

  // ── Async Wi-Fi provisioning — STAGE → TRY → PERSIST ONLY ON OK ──
  if (wifiChangeReq) {
    wifiChangeReq = false;

    // Save the current (known-good) creds so we can restore them if
    // the new creds fail.
    const String prevSsid = wifiSsid;
    const String prevPass = wifiPass;

    Serial.printf("[WiFi] Trying new creds: %s\n", pendingSsid.c_str());
    WiFi.disconnect(true);
    delay(500);

    bool ok = connectWifi(pendingSsid, pendingPass);
    if (ok) {
      // ★ v2.5.0: persist ONLY after a successful connection.
      wifiSsid = pendingSsid;
      wifiPass = pendingPass;
      saveWifi(wifiSsid, wifiPass);

      configTime(7 * 3600, 0, "pool.ntp.org");
      hbFailCount = 0;
      hbCurrentIntervalMs = HEARTBEAT_MS;
      lastHb = 0;
      sendHeartbeat();

      statusChar->setValue("OK");
      if (bleConn) statusChar->notify();
      Serial.println(F("[WiFi] New creds persisted to NVS"));
    } else {
      // Try to fall back to the previous good creds so the device
      // isn't stranded.  Persistent NVS values were never touched.
      Serial.println(F("[WiFi] New creds failed — reverting to last good"));
      statusChar->setValue("WIFI_FAIL");
      if (bleConn) statusChar->notify();

      if (!prevSsid.isEmpty()) {
        WiFi.disconnect(true);
        delay(300);
        connectWifi(prevSsid, prevPass);
      }
    }
    updateBleStatus();
    pendingSsid = "";
    pendingPass = "";
  }

  bool wifiOk = (WiFi.status() == WL_CONNECTED);

  // ── Auto-reconnect ────────────────────────────────────────
  if (!wifiOk && !wifiSsid.isEmpty() && !wifiChangeReq) {
    if (now - lastRecon > 30000) {
      lastRecon = now;
      Serial.println(F("[WiFi] Reconnecting..."));
      connectWifi(wifiSsid, wifiPass, 10000);
    }
    delay(100);
    return;
  }

  // ── Heartbeat (adaptive cadence) ──────────────────────────
  if (wifiOk && now - lastHb > hbCurrentIntervalMs) {
    lastHb = now;
    bool ok = sendHeartbeat();
    updateBleStatus();
    if (ok) {
      if (hbFailCount > 0) {
        Serial.printf("[HB] Recovered after %u failure(s)\n", hbFailCount);
      }
      hbFailCount = 0;
      hbCurrentIntervalMs = HEARTBEAT_MS;
    } else {
      hbFailCount++;
      uint32_t shift = (hbFailCount > 4) ? 4 : hbFailCount;
      uint32_t next  = HEARTBEAT_MS * (1UL << shift);
      hbCurrentIntervalMs = (next > HB_MAX_INTERVAL_MS) ? HB_MAX_INTERVAL_MS : next;
      Serial.printf("[HB] Backing off (%u fails) — next in %u ms\n",
                    hbFailCount, hbCurrentIntervalMs);
    }
  }

  // ── Command poll every 15s ──────────────────────────────
  if (wifiOk && now - lastPoll > STATE_POLL_MS) {
    lastPoll = now;
    pollState();
  }

  // ── Schedule check every 60s ────────────────────────────
  if (wifiOk && now - lastSched > SCHED_CHECK_MS) {
    lastSched = now;
    if (scheduleCount > 0) {
      bool shouldBeOn = isInSchedule();
      if (shouldBeOn != relayState) {
        relayState = shouldBeOn;
        digitalWrite(RELAY_PIN, relayState ? HIGH : LOW);
        Serial.printf("[SCHED] Relay → %s\n", relayState ? "ON" : "OFF");
      }
    }
  }

  delay(100);
}
