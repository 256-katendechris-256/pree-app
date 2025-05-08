#include <WiFi.h>
#include <DNSServer.h>
#include <WebServer.h>
#include <Preferences.h>
#include <SPI.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <HTTPClient.h>
#include <time.h>
#include <ArduinoJson.h>
#include <MPU6050_tockn.h>
#include "MAX30105.h"
#include "heartRate.h"  // For BPM detection

// Display settings
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET    -1
#define SCREEN_ADDRESS 0x3C
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

// Step detection constants
#define STEP_THRESHOLD 1.2
#define STEP_COOLDOWN 400
#define CALORIES_PER_STEP 0.04
#define STEP_LENGTH_METERS 0.75

// Button pins
#define CONFIG_BUTTON_PIN 4  // Button for entering setup mode
#define POWER_BUTTON_PIN 4 //Button for power
#define LONG_PRESS_DURATION 4500 // 4 seconds for power on and off
#define SCREEN_TOGGLE_PIN 6  // Button for toggling display on/off (GPIO0)
#define WIFI_STATUS_LED_PIN 7     // Button for cycling through data screens (GPIO1)
#define BUZZER_PIN 20
#define BUZZER_DURATION 1000
#define MIDNIGHT_RESET_HOUR 0
#define MIDNIGHT_RESET_MINUTE 0

// RTC memory will keep values during sleep
RTC_DATA_ATTR bool deviceWasOn = false;
RTC_DATA_ATTR unsigned long lastStepCountBeforeSleep = 0;
RTC_DATA_ATTR float lastCaloriesBurnedBeforeSleep = 0.0;
RTC_DATA_ATTR float lastDistanceInKmBeforeSleep = 0.0;
RTC_DATA_ATTR time_t lastSleepTime = 0;


bool devicePoweredOn = true;  // Start powered on by default
bool powerButtonPressed = false;
unsigned long powerButtonPressStartTime = 0;
unsigned long lastMidnightCheck = 0;
bool midnightResetDone = false;



// Access Point settings
const char* apSSID = "PMD-HealthDevice";
const IPAddress apIP(192, 168, 4, 1);
const byte DNS_PORT = 53;

// WiFi settings for normal operation mode
String wifiSSID = "";
String wifiPassword ="";

// Firestore settings
const char* firestoreProjectId = "finale-813d8"; 
const char* firestoreAPIKey = "AIzaSyBiBVye_Jru8BLq96LeLhkNpbOhyHkLM6A"; 

// Initialize sensors
MPU6050 mpu(Wire);
MAX30105 particleSensor;

DNSServer dnsServer;
WebServer webServer(80);

// Variables for configuration
Preferences preferences;
String userId = "";
String deviceId = "";
bool setupMode = false;
unsigned long setupModeTimeout = 0;
const unsigned long SETUP_MODE_DURATION = 120000; // 2 minutes

// Variables for sensor data
unsigned long stepCount = 0;
unsigned long lastStepTime = 0;
bool stepDetected = false;
float caloriesBurned = 0.0;
float distanceInKm = 0.0;

int temperature = 0;
float beatsPerMinute = 0;
int beatAvg = 0;
int activeMinutes = 0;
String bpMeasurementDate = "--/--/----";
String bpMeasurementTime = "--:--";


// Data from Firebase (retrieved)
int systolicValue = 0;  // Systolic blood pressure value from Firebase
int diastolicValue = 0; // Diastolic blood pressure value from Firebase
int remoteBPM = 0;      // BPM value from Firebase

// Heart Rate variables
const byte RATE_SIZE = 4;
byte rates[RATE_SIZE];
byte rateSpot = 0;
long lastBeat = 0;

// Time tracking
unsigned long lastReadingTime = 0;
unsigned long lastUploadTime = 0;
unsigned long lastFetchTime = 0;
const unsigned long READING_INTERVAL = 2000;   // Read sensors every 2 seconds
const unsigned long UPLOAD_INTERVAL = 300000;  // Upload data every 5 minutes (reduced frequency)
const unsigned long FETCH_INTERVAL = 600000;   // Fetch data from Firebase every 10 minutes

// Display state
bool displayOn = true;
unsigned long displaySleepTime = 0;
const unsigned long DISPLAY_TIMEOUT = 30000;  // Turn off display after 30 seconds of inactivity
int currentScreen = 0;  // 0 = time, 1 = steps/calories, 2 = heart/temp, 3 = BP from Firebase
const int NUM_SCREENS = 3;

//buzzer alert config
unsigned long lastVitalSignsUpdate = 0;
//const unsigned long VITALS_SIGNS_ALERT_INTERVAL = 2*60*1000;
const unsigned long VITALS_SIGNS_ALERT_INTERVAL = 4*60*60*1000;
bool alertActive = false; // flag to track if alert is active
bool alertSilenced = false; // flag to allow user silence the alert


// Button state
bool screenTogglePressed = false;
bool dataCyclePressed = false;
unsigned long lastButtonPress = 0;
const unsigned long BUTTON_LONG_PRESS = 1000; // 1 second for long press

String lastKnownTimestamp = "";
bool forceTimerReset = false;
unsigned long lastQuickCheckTime = 0;
const unsigned long QUICK_CHECK_INTERVAL =60000;
unsigned long lastTimerUpdate = 0;
String lastKnownTimeStamp = "";

unsigned long savedStepCount = 0;
float savedCaloriesBurned = 0.0;
float savedDistanceInKm = 0.0;
bool wasPoweredOff = false;
int bootCount = 0;  


String maskString(String input, int visibleChars = 3) {
  if (input.length() <= visibleChars * 2) {
    return input; // If string is short, don't mask
  }
  
  String first = input.substring(0, visibleChars);
  String last = input.substring(input.length() - visibleChars);
  
  // Return masked string with asterisks in the middle
  return first + "****" + last;
}


bool verifyUserID(String userIdToVerify) {
  if (userIdToVerify.isEmpty()) {
    return false;
  }
  
  // If not connected to WiFi, accept the user ID without verification
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("No WiFi connection. Accepting user ID without verification.");
    return true;
  }
  
  // Now we can verify against Firebase
  Serial.println("Verifying user ID: " + maskString(userIdToVerify));
  
  HTTPClient http;
  
  // URL to check if the user exists in Firebase
  String url = "https://firestore.googleapis.com/v1/projects/";
  url += firestoreProjectId;
  url += "/databases/(default)/documents/users/";
  url += userIdToVerify;
  url += "?key=";
  url += firestoreAPIKey;
  
  http.begin(url);
  int httpCode = http.GET();
  
  bool userExists = false;
  
  if (httpCode == HTTP_CODE_OK) {
    // User document exists
    Serial.println("User verification successful");
    userExists = true;
  } else if (httpCode == 404) {
    // User not found
    Serial.println("User verification failed: User not found");
    // Accept new users without verification during setup
    if (setupMode) {
      Serial.println("In setup mode - accepting new user ID without verification");
      userExists = true;
    } else {
      userExists = false;
    }
  } else {
    // Other error
    Serial.print("User verification failed: HTTP error ");
    Serial.println(httpCode);
    
    // Allow user ID to be set if we can't verify due to technical reasons
    userExists = true;
  }
  
  http.end();
  return userExists;
}


bool fetchBPDataByUserId() {
  if (WiFi.status() != WL_CONNECTED || userId.isEmpty()) {
    Serial.println("Cannot fetch vital signs: WiFi not connected or no user ID");
    return false;
  }
  
  Serial.println("Fetching vital signs specifically for user: " + maskString(userId));
  
  HTTPClient http;
  String url = "https://firestore.googleapis.com/v1/projects/";
  url += firestoreProjectId;
  url += "/databases/(default)/documents/vital_signs";
  // Use a structured query to filter by user_id
  url += ":runQuery";
  url += "?key=";
  url += firestoreAPIKey;
  
  // Create a structured query payload to filter by user_id and order by timestamp
  String queryPayload = "{";
  queryPayload += "\"structuredQuery\": {";
  queryPayload += "\"from\": [{\"collectionId\": \"vital_signs\"}],";
  queryPayload += "\"where\": {";
  queryPayload += "\"fieldFilter\": {";
  queryPayload += "\"field\": {\"fieldPath\": \"user_id\"},";
  queryPayload += "\"op\": \"EQUAL\",";
  queryPayload += "\"value\": {\"stringValue\": \"" + userId + "\"}";
  queryPayload += "}},";
  queryPayload += "\"orderBy\": [{";
  queryPayload += "\"field\": {\"fieldPath\": \"timestamp\"},";
  queryPayload += "\"direction\": \"DESCENDING\"";
  queryPayload += "}],";
  queryPayload += "\"limit\": 1";
  queryPayload += "}}";
  
  Serial.println("Sending query: " + queryPayload);
  
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  int httpCode = http.POST(queryPayload);
  bool dataUpdated = false;
  
  if (httpCode == HTTP_CODE_OK) {
    String payload = http.getString();
    Serial.println("Response received. Size: " + String(payload.length()));
    
    DynamicJsonDocument doc(16384);
    DeserializationError error = deserializeJson(doc, payload);
    
    if (!error && doc.is<JsonArray>() && doc.size() > 0) {
      // First element contains the result
      JsonObject result = doc[0];
      
      if (result.containsKey("document")) {
        JsonObject document = result["document"];
        
        if (document.containsKey("fields")) {
          JsonObject fields = document["fields"];
          
          // Now store the timestamp (after fields is defined)
          if (fields.containsKey("timestamp")) {
            JsonObject tsField = fields["timestamp"].as<JsonObject>();
            if (tsField.containsKey("timestampValue")) {
              String timestamp = tsField["timestampValue"].as<String>();
              Serial.println("Data timestamp from structured query: " + timestamp);
              lastKnownTimestamp = timestamp;
            }
          }
          
          // Extract vital signs data using our helper function
          if (fields.containsKey("systolic_BP")) {
            extractNumericValue(fields["systolic_BP"], systolicValue, "systolic_BP");
          }
          
          if (fields.containsKey("diastolic")) {
            extractNumericValue(fields["diastolic"], diastolicValue, "diastolic");
          }
          
          if (fields.containsKey("pulse")) {
            extractNumericValue(fields["pulse"], remoteBPM, "pulse");
          }
          
          // Extract date and time
          if (fields.containsKey("date") && 
              fields["date"].containsKey("stringValue")) {
            bpMeasurementDate = fields["date"]["stringValue"].as<String>();
          }
          
          if (fields.containsKey("time") && 
              fields["time"].containsKey("stringValue")) {
            bpMeasurementTime = fields["time"]["stringValue"].as<String>();
          }
          
          Serial.println("--- Structured Query Result ---");
          Serial.println("Systolic: " + String(systolicValue));
          Serial.println("Diastolic: " + String(diastolicValue));
          Serial.println("Pulse: " + String(remoteBPM));
          Serial.println("Date: " + bpMeasurementDate);
          Serial.println("Time: " + bpMeasurementTime);
          Serial.println("-----------------------------");
          
          // Update display and flag success
          if (displayOn) {
            updateDisplay();
          }
          dataUpdated = true;
        }
      } else if (result.containsKey("readTime")) {
        // We got a response, but no documents matched our query
        Serial.println("No matching documents found for this user ID");
      }
    } else {
      Serial.print("Failed to parse response: ");
      if (error) {
        Serial.println(error.c_str());
      } else {
        Serial.println("No results in array");
      }
    }
  } else {
    Serial.print("HTTP error: ");
    Serial.println(httpCode);
  }
  
  http.end();
  lastFetchTime = millis();
  
  // Reset vital signs timer if we successfully got data
  if (dataUpdated) {
    lastVitalSignsUpdate = millis();
    time_t now = time(nullptr);
    preferences.putLong("lastVitalEpoch", now);
    preferences.putLong("lastVitalUpdate", lastVitalSignsUpdate);
    alertSilenced = false;
    Serial.println("Vital signs timer reset after successful structured query");
  }
  
  return dataUpdated;
}

// Modified WiFi test function to be more reliable
bool testWiFiConnection(String ssid, String password) {
  if (ssid.isEmpty()) {
    return false;
  }
  
  Serial.println("Testing WiFi credentials for SSID: " + ssid);
  
  // Remember current connection state
  WiFiMode_t currentMode = WiFi.getMode();
  
  // Disconnect from current network
  WiFi.disconnect(true);
  delay(500);
  
  // Try the new connection
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid.c_str(), password.c_str());
  
  // Wait for connection with timeout
  int attempts = 0;
  bool connectionSuccess = false;
  
  while (WiFi.status() != WL_CONNECTED && attempts < 20) { // 10 second timeout
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi test successful!");
    Serial.println("IP: " + WiFi.localIP().toString());
    connectionSuccess = true;
    
    // Disconnect immediately after successful test
    WiFi.disconnect(true);
    delay(500);
  } else {
    Serial.println("\nWiFi test failed, but accepting credentials anyway!");
    // We'll accept the credentials even if the test fails
    // The user might be setting up WiFi that's not currently available
    connectionSuccess = true;
  }
  
  // Restore original mode
  WiFi.mode(currentMode);
  
  return connectionSuccess;
}



void setup() {
  // Start Serial for debugging
  Serial.begin(115200);
  delay(100); // Short delay to stabilize
  Serial.println("\n\nStarting PMD Health Device...");
  
  // Initialize button pins
  pinMode(POWER_BUTTON_PIN, INPUT_PULLUP);
  pinMode(CONFIG_BUTTON_PIN, INPUT_PULLUP);
  pinMode(SCREEN_TOGGLE_PIN, INPUT_PULLUP);
  pinMode(WIFI_STATUS_LED_PIN, OUTPUT);
  digitalWrite(WIFI_STATUS_LED_PIN, LOW);
  
  // Initialize I2C
  Wire.begin();
  
  // Initialize the OLED display
  if (!display.begin(SSD1306_SWITCHCAPVCC, SCREEN_ADDRESS)) {
    Serial.println(F("SSD1306 display allocation failed"));
  } else {
    // Clear display and show startup message
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(0, 0);
    display.println("Starting PMD Device...");
    display.display();
  }
  
  // Initialize preferences storage
  preferences.begin("pmdevice", false);

  loadPowerState();

  //Initialize the timer value
  lastVitalSignsUpdate = millis();

    
    unsigned long savedUpdate = preferences.getLong("lastVitalUpdate", 0);
    if (savedUpdate > 0) {
      // Consider if device was rebooted
      if (savedUpdate > millis()) {
        // Device was rebooted, calculate elapsed time from epoch time
        time_t now = time(nullptr);
        time_t savedEpoch = preferences.getLong("lastVitalEpoch", 0);
        unsigned long elapsedSeconds = (now > savedEpoch) ? (now - savedEpoch) : 0;
        
        if (elapsedSeconds < (4 * 60 * 60)) {
          // Not yet 4 hours, calculate remaining time
          unsigned long remainingSeconds = (4 * 60 * 60) - elapsedSeconds;
          lastVitalSignsUpdate = millis() - (VITALS_SIGNS_ALERT_INTERVAL - (remainingSeconds * 1000));
        } else {
          // More than 4 hours, trigger alert soon
          lastVitalSignsUpdate = millis() - VITALS_SIGNS_ALERT_INTERVAL + (60 * 1000); // Alert in 1 minute
        }
      } else {
        // Normal case - load saved value
        lastVitalSignsUpdate = savedUpdate;
      }
    }
  

  // wifiSSID = preferences.getString("wifiSSID","");
  // wifiPassword = preferences.getString("wifiPassword","");
  // lastVitalSignsUpdate = millis();

  // // devicePoweredOn = preferences.getBool("poweredOn", true);

  // checkWakeupState();
  
  // initializePowerManagement();
  if (devicePoweredOn){

    wifiSSID = preferences.getString("wifiSSID","");
    wifiPassword = preferences.getString("wifiPassword","");
    lastVitalSignsUpdate = millis();
    userId = preferences.getString("userId", "");
    deviceId = preferences.getString("deviceId", "");
    
    // Initialize step counter to 0 explicitly
    stepCount = 0;
    lastStepTime = 0;
    stepDetected = false;
    caloriesBurned = 0.0;
    distanceInKm = 0.0;

    if (lastVitalSignsUpdate == 0) {
    // If no saved value, initialize to current time
    lastVitalSignsUpdate = millis();
    preferences.putLong("lastVitalUpdate", lastVitalSignsUpdate);
  }
  
  // Check if we need to adjust for device reboot
  // Account for millis() resetting to 0 after reboot
  if (lastVitalSignsUpdate > millis()) {
    // This means device has been rebooted since last update
    // Calculate if 4 hours have passed since last update
    unsigned long currentTime = time(nullptr);
    unsigned long savedTime = preferences.getLong("lastVitalEpoch", 0);
    
    if (currentTime > savedTime && (currentTime - savedTime) >= (4 * 60 * 60)) {
      // It's been more than 4 hours, set timer to trigger alert soon
      lastVitalSignsUpdate = millis() - VITALS_SIGNS_ALERT_INTERVAL + (1 * 60 * 1000); // Alert in 1 minute
    } else {
      // Not yet 4 hours, calculate remaining time
      unsigned long elapsedSeconds = (currentTime > savedTime) ? (currentTime - savedTime) : 0;
      unsigned long remainingSeconds = (4 * 60 * 60) - elapsedSeconds;
      lastVitalSignsUpdate = millis() - (remainingSeconds * 1000);
    }
  }

  // Load saved configuration
  userId = preferences.getString("userId", "");
  deviceId = preferences.getString("deviceId", "");
  
  // Initialize step counter to 0 explicitly
  stepCount = 0;
  lastStepTime = 0;
  stepDetected = false;
  caloriesBurned = 0.0;
  distanceInKm = 0.0;
  
  // Generate device ID if not set
  if (deviceId == "") {
    deviceId = "PMD_" + String((uint32_t)(ESP.getEfuseMac()), HEX);
    preferences.putString("deviceId", deviceId);
    Serial.println("Generated new device ID: " + deviceId);
  }
  
  // Initialize MPU6050 accelerometer
  mpu.begin();
  Serial.println("Calibrating MPU6050...");
  display.clearDisplay();
  display.setCursor(0, 0);
  display.println("Calibrating...");
  display.display();
  mpu.calcGyroOffsets(true);
  Serial.println("MPU6050 Initialized");
  
  // Initialize MAX30102 heart rate sensor
  if (!particleSensor.begin(Wire, I2C_SPEED_FAST)) {
    Serial.println("MAX30102 not found");
    display.clearDisplay();
    display.setCursor(0, 0);
    display.println("Heart rate sensor");
    display.setCursor(0, 10);
    display.println("not found!");
    display.display();
    delay(2000);
  } else {
    particleSensor.setup(); // Use default values
    particleSensor.enableDIETEMPRDY();
    Serial.println("MAX30102 Initialized");
  }
  
  // Check if we should enter setup mode (using CONFIG_BUTTON_PIN now)
  if (userId == "" || digitalRead(CONFIG_BUTTON_PIN) == LOW) {
    Serial.println("Entering setup mode...");
    setupMode = true;
    setupModeTimeout = millis() + SETUP_MODE_DURATION;
    startCaptivePortal();
  } else {
    Serial.println("Device configured with User ID: " + userId);
    Serial.println("Running in normal mode");
    
    // Connect to WiFi for normal operation
    connectToWiFi();
    
    // Initialize time with UTC+3 for Uganda
    configTime(3 * 3600, 0, "pool.ntp.org", "time.nist.gov");

    // In the setup() function where you're initializing time
    Serial.println("Waiting for time sync");
    time_t now = time(nullptr);
    int timeoutCounter = 0;
    while (now < 8 * 3600 * 2 && timeoutCounter < 10) { // Add timeout counter
      delay(500);
      Serial.print(".");
      now = time(nullptr);
      timeoutCounter++;
    }
    if (now > 8 * 3600 * 2) {
      Serial.println("Time synchronized");
    } else {
      Serial.println("Time sync failed, continuing anyway");
    }
    
    // Fetch initial BP data from Firebase
    fetchBPDataFromFirebase();
    
    // Display status
    displayStatus();
  }
  
  // Print serial configuration instructions
  Serial.println("\n=== PMD Health Device Configuration ===");
  Serial.println("Device ID: " + deviceId);

  if (userId.isEmpty()) {
    Serial.println("Current User ID: Not set");
  } else {
    Serial.println("Current User ID: " + maskString(userId));
  }
  
  Serial.println("To set user ID via serial, send: USERID:[your-user-id]");
  Serial.println("Example: USERID:abc123def456");
  Serial.println("Type HELP for more commands");
  Serial.println("=======================================\n");
  
  // Set initial display timeout
  displaySleepTime = millis() + DISPLAY_TIMEOUT;

  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);

  lastVitalSignsUpdate = millis();
}

}

void loop() {

  checkPowerButton();

  if (!devicePoweredOn){
    delay(100); // this should never happen

    return;
  }

  checkForMidnightReset();

  if (setupMode) {
    // Handle DNS and HTTP requests in setup mode
    dnsServer.processNextRequest();
    webServer.handleClient();
    
    // Make sure LED is off in setup mode or when display is off
    digitalWrite(WIFI_STATUS_LED_PIN, LOW);
    
    // Check if CONFIG_BUTTON_PIN is pressed again to exit setup mode
    if (digitalRead(CONFIG_BUTTON_PIN) == LOW) {
      delay(50); // Debounce
      if (digitalRead(CONFIG_BUTTON_PIN) == LOW) {
        // Wait for button release
        while (digitalRead(CONFIG_BUTTON_PIN) == LOW) {
          delay(10);
        }
        
        Serial.println("Setup mode exited by user");
        display.clearDisplay();
        display.setCursor(0, 0);
        display.println("Exiting setup mode...");
        display.display();
        delay(1000);
        
        setupMode = false;
        stopCaptivePortal();
        
        // Connect to WiFi for normal operation if user ID is set
        if (!userId.isEmpty()) {
          connectToWiFi();
          // Initialize time with UTC+3 for Uganda
          configTime(3 * 3600, 0, "pool.ntp.org", "time.nist.gov");
        }
        
        // Show normal display
        displayStatus();
        delay(2000);
        currentScreen = 0; // Start with main screen
        updateDisplay();
      }
    }
    
    // Exit setup mode after timeout
    if (millis() > setupModeTimeout) {
      Serial.println("Setup mode timed out, returning to normal operation");
      setupMode = false;
      stopCaptivePortal();
      
      // Connect to WiFi for normal operation if a user ID is set
      if (!userId.isEmpty()) {
        connectToWiFi();
        // Initialize time with UTC+3 for Uganda
        configTime(3 * 3600, 0, "pool.ntp.org", "time.nist.gov");
      }
      
      displayStatus();
    }
  } else {
    // Normal operation code here
    if (!userId.isEmpty()) {
      // Check buttons first
      checkButtons();
      
      // Only perform normal operations if the device is configured
      
      // Update WiFi status LED based on both connection state AND display state
      // LED should be on only when both WiFi is connected AND display is on
      digitalWrite(WIFI_STATUS_LED_PIN, (WiFi.status() == WL_CONNECTED && displayOn) ? HIGH : LOW);
      
      // Read sensor data at regular intervals
      if (millis() - lastReadingTime >= READING_INTERVAL) {
        readSensorData();
        lastReadingTime = millis();
        
        // Update display if it's on
        if (displayOn) {
          updateDisplay();
        }
      }
      


      // Upload data to Firestore at regular intervals
      if (WiFi.status() == WL_CONNECTED && (millis() - lastUploadTime >= UPLOAD_INTERVAL)) {
        uploadToFirestore();
        lastUploadTime = millis();
      }
      
      // Fetch BP data from Firebase at regular intervals
      if (WiFi.status() == WL_CONNECTED && (millis() - lastFetchTime >= FETCH_INTERVAL)) {
        fetchLatestVitalSignsData();
        lastFetchTime = millis();
      }

      // Check for new vital signs data more frequently 
      if (WiFi.status() == WL_CONNECTED && !setupMode && !userId.isEmpty() && 
          (millis() - lastQuickCheckTime >= QUICK_CHECK_INTERVAL)) {
        
        // Perform a quick check for new data
        fetchLatestVitalSignsData();
        lastQuickCheckTime = millis();
      }
      
      // Check if WiFi connection is lost and try to reconnect
      if (WiFi.status() != WL_CONNECTED && millis() - lastUploadTime >= 600000) { // Try reconnecting every 10 minutes
        Serial.println("WiFi connection lost. Attempting to reconnect...");
        connectToWiFi();
      }

      // Update timer display more frequently when on timer screen
      // if (displayOn && currentScreen == 2 && millis() % 1000 < 20) {  // Update every ~1 second
      // displayTimerScreen();  // Refresh the timer screen to show accurate countdown
      // }
      if (displayOn && currentScreen == 2){
        static unsigned long lastTimerUpdate = 0;
        if (millis() - lastTimerUpdate >= 1000){
          displayTimerScreen();
          lastTimerUpdate =millis();
        }
      }
      
      // Check for display timeout
      if (displayOn && millis() > displaySleepTime) {
        displayOn = false;
        display.clearDisplay();
        display.display();
        // Also turn off the LED when display turns off
        digitalWrite(WIFI_STATUS_LED_PIN, LOW);
        Serial.println("Display turned off due to inactivity");
      }
    }
  }
  

  mpu.update();
  float accelX = mpu.getAccX();
  float accelY = mpu.getAccY();
  float accelZ = mpu.getAccZ();
  float accelMagnitude = sqrt(accelX * accelX + accelY * accelY + accelZ * accelZ);
  detectStep(accelMagnitude);

  caloriesBurned = stepCount * CALORIES_PER_STEP;
  distanceInKm = (stepCount * STEP_LENGTH_METERS) / 1000.0;

  // Check if vital signs alert needs to be trigered
  if (!setupMode && !userId.isEmpty()){
    checkVitalSignsAlert();
  }



// Print timer debug info every 5 seconds
if (millis() % 5000 < 10) {
  unsigned long elapsedTime = millis() - lastVitalSignsUpdate;
  unsigned long remainingTime = (elapsedTime < VITALS_SIGNS_ALERT_INTERVAL) ? 
    (VITALS_SIGNS_ALERT_INTERVAL - elapsedTime) : 0;
  
  Serial.println("===== Timer Debug =====");
  Serial.print("Current millis: "); Serial.println(millis());
  Serial.print("Last update: "); Serial.println(lastVitalSignsUpdate);
  Serial.print("Elapsed since update: "); Serial.print(elapsedTime / 1000); Serial.println(" seconds");
  Serial.print("Time remaining: "); 
  Serial.print(remainingTime / 1000); Serial.println(" seconds");
  Serial.print("Alert active: "); Serial.println(alertActive ? "Yes" : "No");
  Serial.print("Alert silenced: "); Serial.println(alertSilenced ? "Yes" : "No");
  Serial.print("Force reset flag: "); Serial.println(forceTimerReset ? "Yes" : "No");
  Serial.println("=======================");
}

  // Always check for serial commands
  checkSerialCommand();
  
  // Small delay to prevent watchdog issues
  delay(10);
}


void saveDeviceState() {
  // Save current step count and other metrics before sleep
  lastStepCountBeforeSleep = stepCount;
  lastCaloriesBurnedBeforeSleep = caloriesBurned;
  lastDistanceInKmBeforeSleep = distanceInKm;
  
  Serial.println("Device state saved before sleep");
}


void restoreDeviceState() {
  // Current implementation will use RTC memory values already loaded
  // No need to do anything here as values are already restored during init
  Serial.println("Checking if state needs to be restored");
  
  // Check if we need to perform a midnight reset
  // If we're waking up from a long sleep, check if we missed midnight
  struct tm timeinfo;
  if (getLocalTime(&timeinfo)) {
    time_t now = time(nullptr);
    
    if (lastSleepTime > 0) {
      // Convert both times to struct tm to check day
      struct tm then_tm;
      localtime_r(&lastSleepTime, &then_tm);
      
      // If current day is different from lastSleepTime day,
      // we crossed midnight and should reset
      if (timeinfo.tm_mday != then_tm.tm_mday || 
          timeinfo.tm_mon != then_tm.tm_mon || 
          timeinfo.tm_year != then_tm.tm_year) {
        
        Serial.println("Day changed while sleeping, resetting daily metrics");
        stepCount = 0;
        caloriesBurned = 0;
        distanceInKm = 0;
      }
    }
  }
}

void checkForMidnightReset() {
  // Only check every minute to save resources
  if (millis() - lastMidnightCheck < 60000) {
    return;
  }
  lastMidnightCheck = millis();
  
  // Get current time
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo)) {
    return;  // Can't get time, try again later
  }
  
  // Check if it's midnight (00:00)
  if (timeinfo.tm_hour == MIDNIGHT_RESET_HOUR && timeinfo.tm_min == MIDNIGHT_RESET_MINUTE) {
    // Only reset once per day
    if (!midnightResetDone) {
      Serial.println("Midnight reached - resetting daily metrics");
      
      // Reset step count and related metrics
      stepCount = 0;
      caloriesBurned = 0;
      distanceInKm = 0;
      
      // Show reset message if display is on
      if (displayOn) {
        display.clearDisplay();
        display.setTextSize(1);
        display.setCursor(0, 0);
        display.println("Daily Reset");
        display.setCursor(0, 20);
        display.println("Step count and");
        display.setCursor(0, 30);
        display.println("metrics reset");
        display.display();
        delay(2000);
        updateDisplay();
      }
      
      // Set flag to prevent multiple resets
      midnightResetDone = true;
    }
  } else {
    // Reset the flag when it's no longer midnight
    if (timeinfo.tm_hour != MIDNIGHT_RESET_HOUR || timeinfo.tm_min > MIDNIGHT_RESET_MINUTE + 2) {
      midnightResetDone = false;
    }
  }
}

void checkWakeupState() {
  bootCount++;
  Serial.println("Boot count: " + String(bootCount));
  
  // Check if we were previously powered off by the user
  if (wasPoweredOff) {
    // We were powered off, but now we're rebooting - probably due to power cycle
    // Check if it's a new day
    struct tm timeinfo;
    bool isSameDay = false;
    
    if (getLocalTime(&timeinfo)) {
      // Get the current time
      time_t now = time(nullptr);
      
      // Get the last saved time from preferences
      preferences.begin("pmdevice", false);
      time_t lastRecordedTime = preferences.getLong("lastKnownTime", 0);
      preferences.end();
      
      if (lastRecordedTime > 0) {
        // Convert to local time structures
        struct tm *lastTm = localtime(&lastRecordedTime);
        struct tm *nowTm = localtime(&now);
        
        // Check if we're on the same day
        isSameDay = (lastTm->tm_year == nowTm->tm_year && 
                      lastTm->tm_mon == nowTm->tm_mon && 
                      lastTm->tm_mday == nowTm->tm_mday);
      }
    }
    
    if (isSameDay) {
      // Same day, restore previous values
      stepCount = savedStepCount;
      caloriesBurned = savedCaloriesBurned;
      distanceInKm = savedDistanceInKm;
      Serial.println("Restored previous activity state");
    } else {
      // New day, start fresh
      stepCount = 0;
      caloriesBurned = 0;
      distanceInKm = 0;
      Serial.println("New day detected, starting with fresh metrics");
    }
    
    // We're back on now
    devicePoweredOn = true;
    wasPoweredOff = false;
  }
  
  // Save current time for future reference
  time_t now = time(nullptr);
  preferences.begin("pmdevice", false);
  preferences.putLong("lastKnownTime", now);
  preferences.end();
}

void checkPowerButton() {
  // Check if button is pressed
  if (digitalRead(POWER_BUTTON_PIN) == LOW && !powerButtonPressed) {
    powerButtonPressed = true;
    powerButtonPressStartTime = millis();
  } 
  // Check if button is released
  else if (digitalRead(POWER_BUTTON_PIN) == HIGH && powerButtonPressed) {
    powerButtonPressed = false;
    // Short press is handled elsewhere for setup mode
  }
  
  // Check for long press while button is still pressed
  if (powerButtonPressed && (millis() - powerButtonPressStartTime >= LONG_PRESS_DURATION)) {
    powerButtonPressed = false;  // Reset state to prevent multiple triggers
    
    // Toggle power state
    if (devicePoweredOn) {
      // Power off sequence
      devicePoweredOn = false;
      
      Serial.println("Long press detected: Powering off...");
      display.clearDisplay();
      display.setTextSize(1);
      display.setCursor(0, 0);
      display.println("Powering off...");
      display.setCursor(0, 20);
      display.println("Goodbye!");
      display.display();
      delay(1000);
      
      // Turn off display
      display.clearDisplay();
      display.display();
      
      // Save state before going to "sleep"
      wasPoweredOff = true;
      savedStepCount = stepCount;
      savedCaloriesBurned = caloriesBurned;
      savedDistanceInKm = distanceInKm;
      
      // Store power state in preferences
      preferences.begin("pmdevice", false);
      preferences.putBool("poweredOn", false);
      preferences.end();
      
      // Turn off WiFi
      WiFi.disconnect();
      WiFi.mode(WIFI_OFF);
      
      // Turn off the LED and display
      digitalWrite(WIFI_STATUS_LED_PIN, LOW);
      display.clearDisplay();
      display.display();
    } else {
      // Power on sequence
      devicePoweredOn = true;
      wasPoweredOff = false;
      
      // Store power state in preferences
      preferences.begin("pmdevice", false);
      preferences.putBool("poweredOn", true);
      preferences.end();
      
      Serial.println("Long press detected: Powering on...");
      
      // Show boot animation
      display.clearDisplay();
      display.setTextSize(1);
      display.setCursor(0, 0);
      display.println("PMD Health Device");
      display.setCursor(0, 20);
      display.println("Starting up...");
      display.display();
      delay(1000);
      
      // Restore previous values if they exist
      if (savedStepCount > 0) {
        // Check if we're still in the same day before restoring
        bool sameDay = true;
        struct tm timeinfo;
        if (getLocalTime(&timeinfo)) {
          // Get the current time
          time_t now = time(nullptr);
          
          // Get the last saved time from preferences
          preferences.begin("pmdevice", false);
          time_t lastKnownTime = preferences.getLong("lastKnownTime", 0);
          preferences.end();
          
          if (lastKnownTime > 0) {
            // Convert to local time structures
            struct tm lastTm;
            localtime_r(&lastKnownTime, &lastTm);
            
            // Different day if any date components differ
            sameDay = (timeinfo.tm_mday == lastTm.tm_mday && 
                      timeinfo.tm_mon == lastTm.tm_mon && 
                      timeinfo.tm_year == lastTm.tm_year);
          }
        }
        
        if (sameDay) {
          // Restore values from before power off
          stepCount = savedStepCount;
          caloriesBurned = savedCaloriesBurned;
          distanceInKm = savedDistanceInKm;
          Serial.println("Restored previous activity metrics");
        } else {
          // Different day, start fresh
          stepCount = 0;
          caloriesBurned = 0;
          distanceInKm = 0;
          Serial.println("New day detected, starting with fresh metrics");
        }
      }
      
      // Connect to WiFi for normal operation if user ID is set
      if (!userId.isEmpty()) {
        connectToWiFi();
        // Initialize time with UTC+3 for Uganda
        configTime(3 * 3600, 0, "pool.ntp.org", "time.nist.gov");
      }
      
      // Show ready screen
      display.clearDisplay();
      display.setCursor(0, 0);
      display.println("Device ready!");
      display.setCursor(0, 20);
      display.println("User: " + (userId.isEmpty() ? "Not set" : maskString(userId)));
      display.display();
      delay(1000);
      
      // Reset display timeout
      displayOn = true;
      displaySleepTime = millis() + DISPLAY_TIMEOUT;
      
      // Update display with current screen
      updateDisplay();
    }
  }
}

void loadPowerState() {
  // Load power state from preferences
  preferences.begin("pmdevice", false);
  devicePoweredOn = preferences.getBool("poweredOn", true);
  
  // Save current time for day change detection
  time_t now = time(nullptr);
  preferences.putLong("lastKnownTime", now);
  
  // If device is supposed to be off, show a message
  if (!devicePoweredOn) {
    Serial.println("Device was powered off before reboot");
    display.clearDisplay();
    display.setCursor(0, 0);
    display.println("Device is off");
    display.setCursor(0, 20);
    display.println("Press power button");
    display.setCursor(0, 30);
    display.println("to turn on");
    display.display();
    delay(2000);
    display.clearDisplay();
    display.display();
  } else {
    Serial.println("Device is powered on");
  }
}



void playAlertPattern() {
  // Visual indicator that alert is playing
  bool ledState = digitalRead(WIFI_STATUS_LED_PIN);
  
  // Play an attention-getting pattern with varying tones
  for (int i = 0; i < 3; i++) {
    // Flash LED during alert
    digitalWrite(WIFI_STATUS_LED_PIN, !ledState);
    
    // First beep
    digitalWrite(BUZZER_PIN, HIGH);
    delay(150);
    digitalWrite(BUZZER_PIN, LOW);
    delay(100);
    
    digitalWrite(WIFI_STATUS_LED_PIN, ledState);
    
    // Second beep (shorter)
    digitalWrite(BUZZER_PIN, HIGH);
    delay(80);
    digitalWrite(BUZZER_PIN, LOW);
    delay(100);
  }
  
  // One longer beep
  digitalWrite(WIFI_STATUS_LED_PIN, !ledState);
  digitalWrite(BUZZER_PIN, HIGH);
  delay(400);
  digitalWrite(BUZZER_PIN, LOW);
  
  // Restore original LED state
  digitalWrite(WIFI_STATUS_LED_PIN, ledState);
}

void checkButtons() {
  // Track press duration for long press detection
  static unsigned long buttonPressStartTime = 0;
  static bool longPressInProgress = false;
  
  // Check screen toggle button (pin 6)
  if (digitalRead(SCREEN_TOGGLE_PIN) == LOW) {
    // Button is pressed
    if (!screenTogglePressed) {
      // First detection of button press
      screenTogglePressed = true;
      buttonPressStartTime = millis();
      longPressInProgress = false;
    } else {
      // Continuing button press - check for long press threshold
      if (!longPressInProgress && (millis() - buttonPressStartTime >= 2000)) {
        longPressInProgress = true;
        
        // Long press detected - initiate manual data refresh
        Serial.println("Long press detected - manual data refresh");
        
        // Show refresh indicator
        if (displayOn) {
          display.clearDisplay();
          display.setTextSize(1);
          display.setCursor(0, 0);
          display.println("Refreshing Data...");
          display.setCursor(0, 20);
          display.println("Connecting to cloud");
          display.display();
        }
        
        // Try to fetch fresh data
        fetchLatestVitalSignsData();
        
        // Reset display timeout and update display
        displaySleepTime = millis() + DISPLAY_TIMEOUT;
        updateDisplay();
      }
    }
  } else if (screenTogglePressed) {
    // Button is released
    unsigned long pressDuration = millis() - buttonPressStartTime;
    
    // Only handle short press if we didn't already handle as long press
    if (!longPressInProgress && pressDuration < 2000) {
      // Short press functionality
      
      // If display is off, turn it on
      if (!displayOn) {
        displayOn = true;
        displaySleepTime = millis() + DISPLAY_TIMEOUT;
        currentScreen = 0;  // Start with the main screen
      } else {
        // If display is on, toggle between screens
        currentScreen = (currentScreen + 1) % NUM_SCREENS;
      }
      
      // Update the display
      updateDisplay();
      
      // Reset display timeout
      displaySleepTime = millis() + DISPLAY_TIMEOUT;
      
      Serial.print("Changed to screen ");
      Serial.println(currentScreen);
    }
    
    // Reset button state
    screenTogglePressed = false;
    delay(50); // Debounce
  }
  
  // Check setup mode button with short press detection
  if (!setupMode && digitalRead(CONFIG_BUTTON_PIN) == LOW) {
    delay(50); // Debounce
    
    if (digitalRead(CONFIG_BUTTON_PIN) == LOW) {
      unsigned long pressStart = millis();
      
      // Wait for button release or timeout
      while (digitalRead(CONFIG_BUTTON_PIN) == LOW && 
             (millis() - pressStart < LONG_PRESS_DURATION)) {
        delay(10);
      }
      
      // If button was released before long press threshold, it's a short press for setup mode
      if (millis() - pressStart < LONG_PRESS_DURATION) {
        Serial.println("Config button short press, entering setup mode...");
        setupMode = true;
        setupModeTimeout = millis() + SETUP_MODE_DURATION;
        
        // Disconnect from WiFi
        WiFi.disconnect();
        
        // Start captive portal
        startCaptivePortal();
      }
    }
  }

  // If any button is pressed during an alert, silence it
  if (alertActive) {
    alertSilenced = true;
    alertActive = false;
    Serial.println("Alert silenced by user");
    
    // Display confirmation
    if (displayOn) {
      display.clearDisplay();
      display.setTextSize(1);
      display.setCursor(0, 0);
      display.println("Alert silenced");
      display.setCursor(0, 20);
      display.println("Remember to take");
      display.setCursor(0, 30);
      display.println("your readings soon");
      display.display();
      delay(2000);
      updateDisplay(); // Return to normal display
    }
  }
}

void updateDisplay() {
  if (!displayOn) return;
  
  switch (currentScreen) {
    case 0:
      displayMainScreen();  // Time, date, steps and calories
      break;
    case 1:
      displayHealthScreen(); // BP, temp, heart rate
      break;

    case 2:
      displayTimerScreen();
      break;
  }
}

void checkVitalSignsAlert() {
  // Reset the timer if new data was detected - this should have been handled
  // in fetchBPDataFromFirebase() already, but check the flag here as a backup
  if (forceTimerReset) {
    time_t now = time(nullptr);
    preferences.putLong("lastVitalEpoch", now);
    preferences.putLong("lastVitalUpdate", millis());
    alertSilenced = false;
    Serial.println("Vital signs timer reset due to new data detection (flag detected in checkVitalSignsAlert)");
    forceTimerReset = false;
    return;
  }
  
  // First check if we have nextDueEpoch available (new method)
  time_t nextDueEpoch = preferences.getLong("nextDueEpoch", 0);
  time_t currentTime = time(nullptr);
  
  if (nextDueEpoch > 0) {
    // New method using actual timestamp
    if (!alertSilenced && currentTime >= nextDueEpoch) {
      // It's time for an alert
      if (!alertActive) {
        alertActive = true;
        
        // Display alert message
        if (displayOn) {
          display.clearDisplay();
          display.setTextSize(1);
          display.setCursor(0, 0);
          display.println("ALERT!");
          display.setCursor(0, 16);
          display.println("Time to take your");
          display.setCursor(0, 26);
          display.println("vital signs reading");
          display.setCursor(0, 46);
          display.println("Press any button");
          display.setCursor(0, 56);
          display.println("to silence");
          display.display();
        }
        
        playAlertPattern();
        
        // If alert is not silenced, schedule next alert in 30 seconds
        if (!alertSilenced) {
          // Save next alert time (30 seconds from now)
          preferences.putLong("nextDueEpoch", currentTime + 30);
        }
        
        Serial.println("Vital signs alert activated - 4 hours since last reading");
        Serial.println("Next alert in 30 seconds if not silenced");
      }
    } else {
      // Reset alert state when not in alert condition
      if (alertActive && (currentTime < nextDueEpoch)) {
        alertActive = false;
        Serial.println("Alert condition no longer active");
      }
    }
  } else {
    // Fall back to old method using millis() if nextDueEpoch is not available
    unsigned long elapsedTime = millis() - lastVitalSignsUpdate;
    
    if (!alertSilenced && elapsedTime >= VITALS_SIGNS_ALERT_INTERVAL) {
      // Using old method for backward compatibility
      if (!alertActive) {
        alertActive = true;
        
        // Display alert message
        if (displayOn) {
          display.clearDisplay();
          display.setTextSize(1);
          display.setCursor(0, 0);
          display.println("ALERT!");
          display.setCursor(0, 16);
          display.println("Time to take your");
          display.setCursor(0, 26);
          display.println("vital signs reading");
          display.setCursor(0, 46);
          display.println("Press any button");
          display.setCursor(0, 56);
          display.println("to silence");
          display.display();
        }
        
        playAlertPattern();
        
        // Schedule next alert in 30 seconds if not silenced
        lastVitalSignsUpdate = millis() - VITALS_SIGNS_ALERT_INTERVAL + (30 * 1000);
        
        Serial.println("Vital signs alert activated using fallback method");
      }
    } else {
      // Reset alert state when not in alert condition
      if (alertActive && (elapsedTime < VITALS_SIGNS_ALERT_INTERVAL)) {
        alertActive = false;
        Serial.println("Alert condition no longer active (fallback method)");
      }
    }
  }
  
  // Print timer debug info every 5 seconds
  if (millis() % 5000 < 10) {
    Serial.println("===== Timer Debug =====");
    
    if (nextDueEpoch > 0) {
      // New method
      char nextDueTimeStr[30];
      char currentTimeStr[30];
      strftime(nextDueTimeStr, sizeof(nextDueTimeStr), "%Y-%m-%d %H:%M:%S", localtime(&nextDueEpoch));
      strftime(currentTimeStr, sizeof(currentTimeStr), "%Y-%m-%d %H:%M:%S", localtime(&currentTime));
      
      long timeRemaining = nextDueEpoch - currentTime;
      
      Serial.println("Using timestamp-based timer:");
      Serial.print("Next due time: "); Serial.println(nextDueTimeStr);
      Serial.print("Current time: "); Serial.println(currentTimeStr);
      Serial.print("Time remaining: "); 
      Serial.print(timeRemaining); Serial.println(" seconds");
    } else {
      // Old method
      unsigned long elapsedTime = millis() - lastVitalSignsUpdate;
      unsigned long remainingTime = (elapsedTime < VITALS_SIGNS_ALERT_INTERVAL) ? 
        (VITALS_SIGNS_ALERT_INTERVAL - elapsedTime) : 0;
      
      Serial.println("Using millis()-based timer (fallback):");
      Serial.print("Current millis: "); Serial.println(millis());
      Serial.print("Last update: "); Serial.println(lastVitalSignsUpdate);
      Serial.print("Elapsed since update: "); Serial.print(elapsedTime / 1000); Serial.println(" seconds");
      Serial.print("Time remaining: "); 
      Serial.print(remainingTime / 1000); Serial.println(" seconds");
    }
    
    Serial.print("Alert active: "); Serial.println(alertActive ? "Yes" : "No");
    Serial.print("Alert silenced: "); Serial.println(alertSilenced ? "Yes" : "No");
    Serial.print("Force reset flag: "); Serial.println(forceTimerReset ? "Yes" : "No");
    Serial.println("=======================");
  }
}



void displayMainScreen() {
  struct tm timeinfo;
  bool hasTime = getLocalTime(&timeinfo);
  
  display.clearDisplay();
  display.setTextSize(1);
  display.setCursor(0, 0);
  
  // Show online/offline status
  if (WiFi.status() == WL_CONNECTED) {
    display.println("PMD (Online)");
  } else {
    display.println("PMD (Offline)");
  }
  
  // Display time and date if available
  if (hasTime) {
    char timeStr[9];
    strftime(timeStr, sizeof(timeStr), "%H:%M:%S", &timeinfo);
    
    char dateStr[11];
    strftime(dateStr, sizeof(dateStr), "%Y-%m-%d", &timeinfo);
    
    display.setTextSize(2);
    display.setCursor(20, 12);
    display.println(timeStr);
    
    display.setTextSize(1);
    display.setCursor(32, 30);
    display.println(dateStr);
  } else {
    display.setTextSize(1);
    display.setCursor(0, 15);
    display.println("Time not available");
    display.setCursor(0, 25);
    display.println("Connect to update time");
  }
  
  // Always display steps and calories (these don't require connectivity)
  display.setCursor(0, 42);
  display.print("Steps: ");
  display.println(stepCount);
  
  display.setCursor(0, 54);
  display.print("Cal: ");
  display.print(caloriesBurned, 1);
  display.print(" | HR: ");
  display.print(beatAvg);
  
  display.display();
}


void connectToWiFi() {
  Serial.println("Connecting to WiFi...");
  
  // Turn off WiFi status LED
  digitalWrite(WIFI_STATUS_LED_PIN, LOW);
  
  // Check if WiFi credentials are available
  if (wifiSSID.isEmpty()) {
    Serial.println("No WiFi credentials set. Cannot connect.");
    
    if (displayOn) {
      display.clearDisplay();
      display.setCursor(0, 0);
      display.println("No WiFi configured");
      display.setCursor(0, 20);
      display.println("Enter setup mode");
      display.setCursor(0, 30);
      display.println("to configure WiFi");
      // Display local sensor data even in offline mode
      display.setCursor(0, 45);
      display.print("Steps: "); display.println(stepCount);
      display.setCursor(0, 55);
      display.print("HR: "); display.println(beatAvg);
      display.display();
      delay(500);
    }
    return;
  }
  
  if (displayOn) {
    display.clearDisplay();
    display.setCursor(0, 0);
    display.println("Connecting to WiFi");
    display.setCursor(0, 10);
    display.println(wifiSSID);
    // Display local sensor data during connection attempt
    display.setCursor(0, 30);
    display.print("Steps: "); display.println(stepCount);
    display.setCursor(0, 40);
    display.print("HR: "); display.println(beatAvg);
    display.setCursor(0, 50);
    display.print("Temp: "); display.println(temperature);
    display.display();
  }
  
  // Connect to WiFi
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.persistent(true);
  WiFi.begin(wifiSSID.c_str(), wifiPassword.c_str());
  
  // Wait for connection with timeout
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print(".");
    if (displayOn) {
      display.print(".");
      display.display();
    }
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi connected");
    Serial.println("IP address: " + WiFi.localIP().toString());
    
    // Turn on WiFi status LED when connected
    digitalWrite(WIFI_STATUS_LED_PIN, HIGH);
    
    if (displayOn) {
      display.clearDisplay();
      display.setCursor(0, 0);
      display.println("WiFi connected!");
      display.setCursor(0, 20);
      display.println("IP: " + WiFi.localIP().toString());
      display.display();
      delay(500);
    }
  } else {
    Serial.println("\nWiFi connection failed");
    
    // Ensure LED is off if connection failed
    digitalWrite(WIFI_STATUS_LED_PIN, LOW);
    
    if (displayOn) {
      display.clearDisplay();
      display.setCursor(0, 0);
      display.println("Offline Mode");
      display.setCursor(0, 10);
      display.println("WiFi unavailable");
      
      // Show local sensor data that doesn't require connectivity
      display.setCursor(0, 25);
      display.println("Local Data:");
      display.setCursor(0, 35);
      display.print("Steps: "); display.println(stepCount);
      display.setCursor(0, 45);
      display.print("HR: "); display.println(beatAvg);
      display.setCursor(0, 55);
      display.print("Temp: "); display.println(temperature);
      display.display();
      delay(2000);
    }
  }
}

void readSensorData() {
  // Update MPU6050 readings
  mpu.update();
  
  // Get raw acceleration values
  float accelX = mpu.getAccX();
  float accelY = mpu.getAccY();
  float accelZ = mpu.getAccZ();
  
  // Calculate total acceleration magnitude
  float accelMagnitude = sqrt(accelX*accelX + accelY*accelY + accelZ*accelZ);
  
  // Print raw values occasionally for debugging
  if (millis() % 5000 < 10) {
    Serial.print("Raw Accel: X=");
    Serial.print(accelX);
    Serial.print(" Y=");
    Serial.print(accelY);
    Serial.print(" Z=");
    Serial.print(accelZ);
    Serial.print(" Mag=");
    Serial.println(accelMagnitude);
  }
  
  // Step detection - using simple method first to confirm it works
  detectStep(accelMagnitude);
  
  // Calculate calories and distance
  caloriesBurned = stepCount * CALORIES_PER_STEP;
  distanceInKm = (stepCount * STEP_LENGTH_METERS) / 1000.0;
  
  // Read temperature from MAX30102
  temperature = particleSensor.readTemperature();
  
  // Read heart rate from MAX30102
  long irValue = particleSensor.getIR();
  if (checkForBeat(irValue) == true) {
    long delta = millis() - lastBeat;
    lastBeat = millis();
    
    beatsPerMinute = 60 / (delta / 1000.0);
    
    if (beatsPerMinute < 255 && beatsPerMinute > 20) {
      rates[rateSpot++] = (byte)beatsPerMinute;
      rateSpot %= RATE_SIZE;
      
      beatAvg = 0;
      for (byte x = 0; x < RATE_SIZE; x++) beatAvg += rates[x];
      beatAvg /= RATE_SIZE;
    }
  }
  
  // Calculate active minutes
  activeMinutes = (millis() / 60000) % 1000; // Minutes since power-on
  
  // Print sensor data periodically
  if (millis() % 10000 < 100) { // Approximately every 10 seconds
    Serial.println("\n----- Sensor Readings -----");
    Serial.print("Steps: "); Serial.println(stepCount);
    Serial.print("Calories: "); Serial.println(caloriesBurned, 1);
    Serial.print("Distance: "); Serial.print(distanceInKm, 2); Serial.println(" km");
    Serial.print("Temperature: "); Serial.print(temperature); Serial.println(" C");
    Serial.print("Heart Rate: "); Serial.print(beatAvg); Serial.println(" BPM");
    Serial.println("---------------------------\n");
  }
}


void detectStep(float accelMagnitude) {
  unsigned long currentTime = millis();
  if (accelMagnitude > STEP_THRESHOLD && !stepDetected &&
      (currentTime - lastStepTime > STEP_COOLDOWN)) {
    stepCount++;
    lastStepTime = currentTime;
    stepDetected = true;
  } else if (accelMagnitude < STEP_THRESHOLD - 0.3 && stepDetected) {
    stepDetected = false;
  }
}

void displayTime() {
  struct tm timeinfo;
  if(!getLocalTime(&timeinfo)){
    Serial.println("Failed to obtain time");
    return;
  }
  
  char timeStr[9];
  strftime(timeStr, sizeof(timeStr), "%H:%M:%S", &timeinfo);
  
  char dateStr[11];
  strftime(dateStr, sizeof(dateStr), "%Y-%m-%d", &timeinfo);
  
  display.clearDisplay();
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.println("PMD Health Device");
  
  display.setTextSize(2);
  display.setCursor(20, 20);
  display.println(timeStr);
  
  display.setTextSize(1);
  display.setCursor(32, 45);
  display.println(dateStr);
  
  display.display();
}

void displayStepsScreen() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  
  // Get current time
  struct tm timeinfo;
  char timeStr[6] = "--:--";
  if(getLocalTime(&timeinfo)){
    sprintf(timeStr, "%02d:%02d", timeinfo.tm_hour, timeinfo.tm_min);
  }
  
  display.setCursor(0, 0);
  display.print("Time: ");
  display.println(timeStr);
  
  display.setCursor(0, 12);
  display.print("Steps: ");
  display.println(stepCount);
  
  display.setCursor(0, 24);
  display.print("Calories: ");
  display.print(caloriesBurned, 1);
  
  display.setCursor(0, 36);
  display.print("Distance: ");
  display.print(distanceInKm, 2);
  display.println(" km");
  
  display.setCursor(0, 48);
  display.print("Active: ");
  display.print(activeMinutes);
  display.println(" min");
  
  display.display();
}




void displayHealthScreen() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  
  // Check WiFi status
  bool isOnline = (WiFi.status() == WL_CONNECTED);
  
  display.setCursor(0, 0);
  if (isOnline) {
    display.println("Health Metrics (Online)");
  } else {
    display.println("Health Metrics (Offline)");
  }
  
  // Always show local sensor data first (these don't require connectivity)
  display.setCursor(0, 10);
  display.print("Steps: ");
  display.println(stepCount);
  
  display.setCursor(0, 20);
  display.print("Temp: ");
  display.print(temperature);
  display.println(" C");
  
  display.setCursor(0, 30);
  display.print("Heart: ");
  display.print(beatAvg);
  display.println(" BPM");
  
  // Show remote BP data only if online or if we have previously cached values
  if (isOnline || (systolicValue > 0 && diastolicValue > 0)) {
    display.setCursor(0, 42);
    display.print("BP: ");
    display.print(systolicValue);
    display.print("/");
    display.print(diastolicValue);
    display.println(" mmHg");
    
    display.setCursor(0, 52);
    display.print("Remote HR: ");
    display.print(remoteBPM);
    display.println(" BPM");
    
    // Add sync status indicator
    if (isOnline && millis() - lastFetchTime < 300000) { // 5 minutes
      display.print(" ↺"); // Sync indicator
    } else if (!isOnline && systolicValue > 0) {
      display.print(" (cached)");
    }
  } else {
    // If no remote data and offline
    display.setCursor(0, 42);
    display.println("No BP data available");
    display.setCursor(0, 52); 
    display.println("Connect to update");
  }
  
  display.display();
}


void displayBPScreen() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  
  display.setCursor(0, 0);
  display.println("Blood Pressure Data");
  
  display.setCursor(0, 12);
  display.print("Systolic: ");
  display.print(systolicValue);
  display.println(" mmHg");
  
  display.setCursor(0, 22);
  display.print("Diastolic: ");
  display.print(diastolicValue);
  display.println(" mmHg");
  
  display.setCursor(0, 32);
  display.print("Pulse: ");
  display.print(remoteBPM);
  display.println(" BPM");
  
  // Display measurement date and time
  display.setCursor(0, 42);
  if (bpMeasurementDate != "--/--/----") {
    display.print(bpMeasurementDate);
    display.print(" ");
    display.print(bpMeasurementTime);
  } else {
    display.println("No measurement data");
  }
  
  // Display status of the data
  display.setCursor(0, 52);
  if (millis() - lastFetchTime < 600000) {
    display.println("Data recently fetched");
  } else {
    display.println("Data may be outdated");
  }
  
  display.display();
}

void displayTimerScreen() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  
  // Check WiFi status
  bool isOnline = (WiFi.status() == WL_CONNECTED);
  
  display.setCursor(0, 0);
  if (isOnline) {
    display.println("Next Reading Due:");
  } else {
    display.println("Offline Mode Active");
  }
  
  // Only show timer countdown if we're online or have a valid timer
  time_t nextDueEpoch = preferences.getLong("nextDueEpoch", 0);
  time_t currentTime = time(nullptr);
 // long timeRemaining = 0;
  
  if (nextDueEpoch > 0 && currentTime > 0) {
   long timeRemaining = nextDueEpoch - currentTime;
    if (timeRemaining < 0) timeRemaining = 0;
    
    // Convert to hours, minutes, seconds
    unsigned long hours = timeRemaining / 3600;
    unsigned long minutes = (timeRemaining % 3600) / 60;
    unsigned long seconds = timeRemaining % 60;
    
    // Display time in large format
    display.setTextSize(2);
    display.setCursor(16, 16);
    
    // Format hours:minutes:seconds with leading zeros
    char timeStr[12];
    sprintf(timeStr, "%02lu:%02lu:%02lu", hours, minutes, seconds);
    display.println(timeStr);
  } else if (!isOnline) {
    // If offline and no valid timer, show local data instead
    display.setTextSize(1);
    
    // Show current time if available
    struct tm timeinfo;
    if (getLocalTime(&timeinfo)) {
      char timeStr[9];
      strftime(timeStr, sizeof(timeStr), "%H:%M:%S", &timeinfo);
      display.setCursor(30, 16);
      display.setTextSize(2);
      display.println(timeStr);
    } else {
      display.setCursor(16, 16);
      display.setTextSize(2);
      display.println("No Time");
    }
  }
  
  // Display information text in smaller format
  display.setTextSize(1);
  display.setCursor(0, 40);
  
  if (!isOnline) {
    display.println("Connect to WiFi to");
    display.setCursor(0, 50);
    display.println("sync with cloud data");
  } else if (alertActive) {
    display.println("ALERT ACTIVE!");
  } else if (alertSilenced) {
    display.println("Alert silenced manually");
  } else {
    display.println("Last reading at:");
    display.setCursor(0, 50);
    
    if (bpMeasurementDate != "--/--/----") {
      display.print(bpMeasurementDate);
      display.print(" ");
      display.print(bpMeasurementTime);
    } else {
      display.println("No data available");
    }
  }
  
  display.display();
}


bool fetchBPDataFromFirebase() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("Cannot fetch vital signs: WiFi not connected");
    return false;
  }
  
  Serial.println("Current device user ID: " + maskString(userId));
  Serial.println("Fetching vital signs data...");
  
  HTTPClient http;
  String url = "https://firestore.googleapis.com/v1/projects/";
  url += firestoreProjectId;
  url += "/databases/(default)/documents/vital_signs";
  // Request only 1 document - the most recent one
  url += "?pageSize=1";
  // Order by timestamp in descending order to get the most recent record
  url += "&orderBy=timestamp%20desc";
  url += "&key=";
  url += firestoreAPIKey;
  
  Serial.println("Fetching data from URL: " + url);
  
  http.begin(url);
  int httpCode = http.GET();
  bool dataUpdated = false;
  String previousTimestamp = lastKnownTimestamp;
  
  if (httpCode == HTTP_CODE_OK) {
    String payload = http.getString();
    Serial.println("Data fetched. Response size: " + String(payload.length()));
    
    // Parse the JSON response
    DynamicJsonDocument doc(16384);
    DeserializationError error = deserializeJson(doc, payload);
    
    if (!error) {
      if (doc["documents"].size() > 0) {
        Serial.println("Found " + String(doc["documents"].size()) + " documents");
        
        // We only need to check the first document since we ordered by timestamp desc
        JsonObject document = doc["documents"][0].as<JsonObject>();
        
        if (document.containsKey("fields")) {
          JsonObject fields = document["fields"];
          
          // Check for user_id field
          String docUserId = "";
          if (fields.containsKey("user_id")) {
            JsonObject userIdField = fields["user_id"].as<JsonObject>();
            
            if (userIdField.containsKey("stringValue")) {
              docUserId = userIdField["stringValue"].as<String>();
            }
          }
          
          // Only process if this document belongs to our user
          if (docUserId == userId) {
            Serial.println("Found document for our user ID!");
            
            // Store timestamp information here - after fields is defined
            String timestamp = "";
            if (fields.containsKey("timestamp")) {
              JsonObject tsField = fields["timestamp"].as<JsonObject>();
              if (tsField.containsKey("timestampValue")) {
                timestamp = tsField["timestampValue"].as<String>();
                Serial.println("Data timestamp: " + timestamp);
                
                // Store the timestamp to detect changes
                lastKnownTimestamp = timestamp;
                
                // Parse the timestamp (format: "2023-05-03T10:57:00Z")
                // Extract date and time components
                int year, month, day, hour, minute, second;
                char timestampStr[30];
                strncpy(timestampStr, timestamp.c_str(), sizeof(timestampStr) - 1);
                timestampStr[sizeof(timestampStr) - 1] = '\0';
                
                // Example format: 2023-05-03T10:57:00Z
                if (sscanf(timestampStr, "%d-%d-%dT%d:%d:%dZ", 
                           &year, &month, &day, &hour, &minute, &second) == 6) {
                  
                  // Create a tm structure for the reading time
                  struct tm readingTime;
                  readingTime.tm_year = year - 1900;  // Years since 1900
                  readingTime.tm_mon = month - 1;     // Months start from 0
                  readingTime.tm_mday = day;
                  readingTime.tm_hour = hour;
                  readingTime.tm_min = minute;
                  readingTime.tm_sec = second;
                  readingTime.tm_isdst = -1;          // Let system decide DST
                  
                  // Convert to time_t (Unix timestamp)
                  time_t readingEpoch = mktime(&readingTime);
                  
                  // Calculate next due time (4 hours = 14400 seconds later)
                  time_t nextDueEpoch = readingEpoch + (4 * 60 * 60);
                  
                  // Store these timestamps for future use
                  preferences.putLong("lastReadingEpoch", readingEpoch);
                  preferences.putLong("nextDueEpoch", nextDueEpoch);
                  
                  // Get current time
                  time_t now = time(nullptr);
                  
                  // Format and display debug info
                  char readingTimeStr[30];
                  char nextDueTimeStr[30];
                  char currentTimeStr[30];
                  
                  strftime(readingTimeStr, sizeof(readingTimeStr), "%Y-%m-%d %H:%M:%S", localtime(&readingEpoch));
                  strftime(nextDueTimeStr, sizeof(nextDueTimeStr), "%Y-%m-%d %H:%M:%S", localtime(&nextDueEpoch));
                  strftime(currentTimeStr, sizeof(currentTimeStr), "%Y-%m-%d %H:%M:%S", localtime(&now));
                  
                  Serial.println("Reading time: " + String(readingTimeStr));
                  Serial.println("Next due time: " + String(nextDueTimeStr));
                  Serial.println("Current time: " + String(currentTimeStr));
                  
                  // Calculate time remaining until next alert
                  long timeRemaining = nextDueEpoch - now;
                  
                  if (timeRemaining <= 0) {
                    // Reading is already overdue
                    Serial.println("Reading is already overdue!");
                    // Set the timer to trigger alert immediately
                    lastVitalSignsUpdate = millis() - VITALS_SIGNS_ALERT_INTERVAL - 1;
                  } else {
                    // Calculate when to trigger alert based on actual due time
                    // VITALS_SIGNS_ALERT_INTERVAL is 4 hours in milliseconds
                    // We need to set lastVitalSignsUpdate so that:
                    // millis() - lastVitalSignsUpdate >= VITALS_SIGNS_ALERT_INTERVAL
                    // when current time reaches nextDueEpoch
                    
                    // Convert timeRemaining to milliseconds
                    unsigned long timeRemainingMs = timeRemaining * 1000;
                    
                    if (timeRemainingMs < VITALS_SIGNS_ALERT_INTERVAL) {
                      // Less than 4 hours remaining
                      lastVitalSignsUpdate = millis() - (VITALS_SIGNS_ALERT_INTERVAL - timeRemainingMs);
                    } else {
                      // More than 4 hours remaining (unusual case)
                      lastVitalSignsUpdate = millis();
                    }
                    
                    Serial.print("Time remaining until alert: ");
                    Serial.print(timeRemaining);
                    Serial.println(" seconds");
                  }
                  
                  // Save lastVitalSignsUpdate to preferences
                  preferences.putLong("lastVitalUpdate", lastVitalSignsUpdate);
                  preferences.putLong("lastVitalEpoch", now);
                }
              }
            }
            
            // Extract systolic_BP value with improved type handling
            if (fields.containsKey("systolic_BP")) {
              extractNumericValue(fields["systolic_BP"], systolicValue, "systolic_BP");
            }
            
            // Extract diastolic value with improved type handling
            if (fields.containsKey("diastolic")) {
              extractNumericValue(fields["diastolic"], diastolicValue, "diastolic");
            }
            
            // Extract pulse value with improved type handling
            if (fields.containsKey("pulse")) {
              extractNumericValue(fields["pulse"], remoteBPM, "pulse");
            }
            
            // Extract date and time
            if (fields.containsKey("date") && 
                fields["date"].containsKey("stringValue")) {
              bpMeasurementDate = fields["date"]["stringValue"].as<String>();
              Serial.println("Updated date to: " + bpMeasurementDate);
            }
            
            if (fields.containsKey("time") && 
                fields["time"].containsKey("stringValue")) {
              bpMeasurementTime = fields["time"]["stringValue"].as<String>();
              Serial.println("Updated time to: " + bpMeasurementTime);
            }
            
            // Print data summary
            Serial.println("--- Extracted Data Summary ---");
            Serial.println("Systolic: " + String(systolicValue));
            Serial.println("Diastolic: " + String(diastolicValue));
            Serial.println("Pulse: " + String(remoteBPM));
            Serial.println("Date: " + bpMeasurementDate);
            Serial.println("Time: " + bpMeasurementTime);
            Serial.println("Timestamp: " + lastKnownTimestamp);
            Serial.println("-----------------------------");
            
            // Update display if it's on
            if (displayOn) {
              updateDisplay();
            }
            
            // Check if this is new data by comparing timestamps
            if (previousTimestamp != lastKnownTimestamp && !lastKnownTimestamp.isEmpty()) {
              Serial.println("New data detected with different timestamp!");
              // Set flag to reset the timer
              forceTimerReset = true;
            }
            
            // Signal success
            dataUpdated = true;
          } else {
            Serial.println("Document does not match our user ID. Found: " + docUserId);
          }
        }
      } else {
        Serial.println("No vital_signs documents found in collection");
      }
    } else {
      Serial.print("JSON parsing error: ");
      Serial.println(error.c_str());
    }
  } else {
    Serial.print("Failed to fetch vital signs data. HTTP code: ");
    Serial.println(httpCode);
  }
  
  http.end();
  lastFetchTime = millis();

  // If data was successfully updated with new readings, reset the vital signs timer
  if (dataUpdated && forceTimerReset) {
    // The timer has already been reset when processing the timestamp above,
    // but we'll show a confirmation message anyway
    alertSilenced = false;
    Serial.println("Vital signs timer reset due to new data detection");
    
    // Display a confirmation message if the display is on
    if (displayOn) {
      display.clearDisplay();
      display.setTextSize(1);
      display.setCursor(0, 0);
      display.println("New Reading Detected!");
      display.setCursor(0, 16);
      display.print("BP: ");
      display.print(systolicValue);
      display.print("/");
      display.print(diastolicValue);
      display.println(" mmHg");
      display.setCursor(0, 28);
      display.print("Pulse: ");
      display.print(remoteBPM);
      display.println(" BPM");
      display.setCursor(0, 42);
      display.println("Timer reset to 4h");
      display.display();
      delay(2000);
      updateDisplay();
    }
    
    // Play a confirmation sound
    digitalWrite(BUZZER_PIN, HIGH);
    delay(100);
    digitalWrite(BUZZER_PIN, LOW);
    
    // Reset the flag
    forceTimerReset = false;
  }
  
  return dataUpdated;
}

void fetchLatestVitalSignsData() {
  Serial.println("Attempting to fetch latest vital signs data...");
  
  // Store the previous values to check if data changed
  String previousTimestamp = lastKnownTimestamp;
  int previousSystolic = systolicValue;
  int previousDiastolic = diastolicValue;
  int previousPulse = remoteBPM;
  
  // Method 1: Try the updated primary method
  bool dataFetched = fetchBPDataFromFirebase();
  
  // Method 2: If primary method failed, try with specific user ID filtering
  if (!dataFetched) {
    dataFetched = fetchBPDataByUserId();
  }
  
  // Method 3: If both methods failed, try fallback
  if (!dataFetched) {
    Serial.println("Primary methods failed, trying fallback method...");
    fetchBPDataWithoutOrdering();
  }
  
  // Check if we got new data (by comparing timestamp or values)
  if (lastKnownTimestamp != previousTimestamp || 
      (systolicValue != previousSystolic && systolicValue > 0) || 
      (diastolicValue != previousDiastolic && diastolicValue > 0) || 
      (previousPulse != remoteBPM && remoteBPM > 0)) {
    
    // New data detected - reset the countdown timer
    if (lastKnownTimestamp != previousTimestamp) {
      Serial.println("New data detected by timestamp change!");
    } else {
      Serial.println("New data detected by value change!");
    }
    
    // Flag to reset the timer
    forceTimerReset = true;
    
    // Visual confirmation if display is on
    if (displayOn) {
      display.clearDisplay();
      display.setTextSize(1);
      display.setCursor(0, 0);
      display.println("New Data Detected!");
      display.setCursor(0, 16);
      display.print("BP: ");
      display.print(systolicValue);
      display.print("/");
      display.print(diastolicValue);
      display.println(" mmHg");
      display.setCursor(0, 28);
      display.print("Pulse: ");
      display.print(remoteBPM);
      display.println(" BPM");
      display.setCursor(0, 42);
      display.println("Countdown timer");
      display.setCursor(0, 52);
      display.println("has been reset");
      display.display();
      delay(2000);
      updateDisplay();
    }
  } else if (dataFetched) {
    Serial.println("Data fetched, but no changes detected");
  }
}


// Helper function to extract numeric values from different JSON field types
void extractNumericValue(JsonObject field, int &targetVariable, const String &fieldName) {
  int extractedValue = 0;
  bool valueFound = false;
  
  Serial.println("Found " + fieldName + " field, checking value types...");
  
  // Try string value
  if (field.containsKey("stringValue")) {
    String strValue = field["stringValue"].as<String>();
    extractedValue = strValue.toInt();
    Serial.println("Found " + fieldName + " as stringValue: " + strValue + " -> " + String(extractedValue));
    valueFound = true;
  } 
  // Try integer value (could be returned as a string by Firebase)
  else if (field.containsKey("integerValue")) {
    if (field["integerValue"].is<String>()) {
      String intStr = field["integerValue"].as<String>();
      extractedValue = intStr.toInt();
      Serial.println("Found " + fieldName + " as integerValue string: " + intStr + " -> " + String(extractedValue));
      valueFound = true;
    }
    else if (field["integerValue"].is<int>()) {
      extractedValue = field["integerValue"].as<int>();
      Serial.println("Found " + fieldName + " as integerValue number: " + String(extractedValue));
      valueFound = true;
    }
  }
  // Try double value
  else if (field.containsKey("doubleValue")) {
    float doubleVal = field["doubleValue"].as<float>();
    extractedValue = (int)doubleVal;
    Serial.println("Found " + fieldName + " as doubleValue: " + String(doubleVal) + " -> " + String(extractedValue));
    valueFound = true;
  }
  
  if (valueFound) {
    targetVariable = extractedValue;
    Serial.println("Updated " + fieldName + " value to: " + String(targetVariable));
  } else {
    Serial.println("No usable value type found for " + fieldName);
    // Print the field content for debugging
    String output;
    serializeJson(field, output);
    Serial.println("Field content: " + output);
  }
}

// Fallback function if orderBy doesn't work
void fetchBPDataWithoutOrdering() {
  if (WiFi.status() != WL_CONNECTED || userId.isEmpty()) {
    return;
  }
  
  Serial.println("Trying fallback method to fetch vital signs...");
  
  HTTPClient http;
  
  // Fetch all vital_signs documents without ordering
  String url = "https://firestore.googleapis.com/v1/projects/";
  url += firestoreProjectId;
  url += "/databases/(default)/documents/vital_signs";
  url += "?key=";
  url += firestoreAPIKey;
  
  http.begin(url);
  int httpCode = http.GET();
  
  if (httpCode == HTTP_CODE_OK) {
    String payload = http.getString();
    
    DynamicJsonDocument doc(8192);
    DeserializationError error = deserializeJson(doc, payload);
    
    if (!error) {
      if (doc.containsKey("documents") && doc["documents"].size() > 0) {
        // Find the most recent timestamp manually for our user
        String latestTimestamp = "";
        JsonObject latestDoc;
        bool foundUser = false;
        
        for (JsonVariant documentVar : doc["documents"].as<JsonArray>()) {
          JsonObject document = documentVar.as<JsonObject>();
          
          if (document.containsKey("fields") && 
              document["fields"].containsKey("user_id") && 
              document["fields"]["user_id"].containsKey("stringValue") &&
              document["fields"]["user_id"]["stringValue"].as<String>() == userId) {
            
            foundUser = true;
            
            if (document["fields"].containsKey("timestamp") && 
                document["fields"]["timestamp"].containsKey("stringValue")) {
              String tsStr = document["fields"]["timestamp"]["stringValue"].as<String>();
              
              if (latestTimestamp.isEmpty() || tsStr > latestTimestamp) {
                latestTimestamp = tsStr;
                latestDoc = document;
              }
            }
          }
        }
        
        // Extract data from the latest document
        if (foundUser && !latestDoc.isNull()) {
          // Extract values similar to the main function
          if (latestDoc["fields"].containsKey("systolic_BP") && 
              latestDoc["fields"]["systolic_BP"].containsKey("stringValue")) {
            systolicValue = latestDoc["fields"]["systolic_BP"]["stringValue"].as<String>().toInt();
          }
          
          if (latestDoc["fields"].containsKey("diastolic") && 
              latestDoc["fields"]["diastolic"].containsKey("stringValue")) {
            diastolicValue = latestDoc["fields"]["diastolic"]["stringValue"].as<String>().toInt();
          }
          
          if (latestDoc["fields"].containsKey("pulse") && 
              latestDoc["fields"]["pulse"].containsKey("stringValue")) {
            remoteBPM = latestDoc["fields"]["pulse"]["stringValue"].as<String>().toInt();
          }
          
          if (latestDoc["fields"].containsKey("date") && 
              latestDoc["fields"]["date"].containsKey("stringValue")) {
            bpMeasurementDate = latestDoc["fields"]["date"]["stringValue"].as<String>();
          }
          
          if (latestDoc["fields"].containsKey("time") && 
              latestDoc["fields"]["time"].containsKey("stringValue")) {
            bpMeasurementTime = latestDoc["fields"]["time"]["stringValue"].as<String>();
          }
          
          Serial.println("Fallback method: Found latest vital signs data");
        }
      }
    }
  }
  
  http.end();
}

void uploadToFirestore() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("Not connected to WiFi. Cannot upload data.");
    return;
  }
  
  // Get current time
  struct tm timeinfo;
  if(!getLocalTime(&timeinfo)){
    Serial.println("Failed to obtain time for timestamp");
    return;
  }
  
  char timestamp[24];
  strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%SZ", &timeinfo);
  
  // Create the Firestore document in a format Firestore REST API expects
  String jsonData = "{\"fields\":{";
  jsonData += "\"active_minutes\":{\"stringValue\":\"" + String(activeMinutes) + "\"},";
  jsonData += "\"calories\":{\"stringValue\":\"" + String(int(caloriesBurned)) + "\"},";
  jsonData += "\"distance\":{\"stringValue\":\"" + String(int(distanceInKm)) + "\"},";
  jsonData += "\"steps\":{\"stringValue\":\"" + String(stepCount) + "\"},";
  jsonData += "\"timestamp\":{\"timestampValue\":\"" + String(timestamp) + "\"},";
  jsonData += "\"user_id\":{\"stringValue\":\"" + userId + "\"}";
  jsonData += "}}";
  
  // For temperature - we'll only upload the most recent reading
  String temperatureJson = "{\"fields\":{";
  temperatureJson += "\"heart_rate\":{\"stringValue\":\"" + String(beatAvg) + "\"},";
  temperatureJson += "\"temperature\":{\"stringValue\":\"" + String(temperature) + "\"},";
  temperatureJson += "\"timestamp\":{\"timestampValue\":\"" + String(timestamp) + "\"},";
  temperatureJson += "\"user_id\":{\"stringValue\":\"" + userId + "\"}";
  temperatureJson += "}}";
  
  Serial.println("Uploading activity data to Firestore...");
  sendToFirestore("activity", jsonData);
  
  Serial.println("Uploading temperature data to Firestore...");
  sendToFirestore("temperature", temperatureJson);
}

void sendToFirestore(const char* collection, String jsonData) {
  HTTPClient http;
  
  // Prepare the URL for Firestore REST API
  String url = "https://firestore.googleapis.com/v1/projects/";
  url += firestoreProjectId;
  url += "/databases/(default)/documents/";
  url += collection;
  url += "?key=";
  url += firestoreAPIKey;
  
  Serial.println("Sending to URL: " + url);
  
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  
  int httpResponseCode = http.POST(jsonData);
  
  if (httpResponseCode > 0) {
    Serial.print("HTTP Response code: ");
    Serial.println(httpResponseCode);
  } else {
    Serial.print("Error on sending POST request: ");
    Serial.println(httpResponseCode);
  }
  
  http.end();
}

void startCaptivePortal() {
  // Disconnect from any previous WiFi
  WiFi.disconnect();
  delay(100);
  
  // Start the access point
  WiFi.mode(WIFI_AP);
  WiFi.softAPConfig(apIP, apIP, IPAddress(255, 255, 255, 0));
  WiFi.softAP(apSSID);
  delay(500); // Give time for AP to start
  
  Serial.print("AP IP address: ");
  Serial.println(WiFi.softAPIP());
  
  // Start DNS server
  dnsServer.setErrorReplyCode(DNSReplyCode::NoError);
  dnsServer.start(DNS_PORT, "*", apIP);
  
  // Setup web server
  webServer.on("/", HTTP_GET, handleRoot);
  webServer.on("/save", HTTP_POST, handleSave);
  webServer.onNotFound([]() {
    webServer.sendHeader("Location", "http://192.168.4.1/", true);
    webServer.send(302, "text/plain", "");
  });
  
  webServer.begin();
  
  Serial.println("Captive portal started");
  Serial.println("Connect to WiFi SSID: " + String(apSSID));
  Serial.println("Then navigate to http://192.168.4.1");
  
  // Show setup instructions on display
  display.clearDisplay();
  display.setCursor(0, 0);
  display.println("SETUP MODE");
  display.setCursor(0, 16);
  display.println("Connect to WiFi:");
  display.setCursor(0, 26);
  display.println(apSSID);
  display.setCursor(0, 36);
  display.println("Then browse to:");
  display.setCursor(0, 46);
 display.println("192.168.4.1");
    display.display();
}

void stopCaptivePortal() {
  // Stop the services
  webServer.stop();
  dnsServer.stop();
  WiFi.softAPdisconnect(true);
  WiFi.mode(WIFI_OFF);
  Serial.println("Captive portal stopped");
}

void handleRoot() {
  String html = "<!DOCTYPE html><html><head><title>PMD Health Device Setup</title>";
  html += "<meta name='viewport' content='width=device-width, initial-scale=1'>";
  html += "<style>";
  html += "body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; color: #333; }";
  html += ".container { max-width: 500px; margin: 0 auto; background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1); }";
  html += "h1 { color: #2c3e50; text-align: center; margin-bottom: 20px; }";
  html += "h2 { color: #3498db; margin-top: 30px; font-size: 1.3em; }";
  html += "p { line-height: 1.5; }";
  html += ".info { background-color: #e8f4fd; border-left: 4px solid #2196F3; padding: 12px; margin-bottom: 20px; }";
  html += "label { display: block; margin-bottom: 8px; font-weight: bold; }";
  html += "input[type='text'], input[type='password'] { width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 4px; box-sizing: border-box; margin-bottom: 20px; }";
  html += "button { background-color: #4CAF50; color: white; border: none; padding: 12px 20px; border-radius: 4px; cursor: pointer; width: 100%; font-size: 16px; }";
  html += "button:hover { background-color: #45a049; }";
  html += "</style></head>";
  html += "<body><div class='container'>";
  html += "<h1>PMD Health Device Setup</h1>";
  html += "<div class='info'>";
  html += "<p>Device ID: <strong>" + deviceId + "</strong></p>";
  
  // Only show if user ID is configured, and show it masked
  if (!userId.isEmpty()) {
    html += "<p>User ID: <strong>Configured (" + maskString(userId) + ")</strong></p>";
  } else {
    html += "<p>User ID: <strong>Not configured</strong></p>";
  }
  
  html += "<p>WiFi Network: <strong>" + (wifiSSID.isEmpty() ? "Not configured" : wifiSSID) + "</strong></p>";
  html += "</div>";
  html += "<form action='/save' method='post'>";
  
  html += "<h2>User Settings</h2>";
  html += "<label for='userId'>User ID:</label>";
  html += "<input type='password' id='userId' name='userId' value='" + userId + "' placeholder='Enter your user ID'>";
  
  html += "<h2>WiFi Settings</h2>";
  html += "<label for='wifiSSID'>WiFi Network Name:</label>";
  html += "<input type='text' id='wifiSSID' name='wifiSSID' value='" + wifiSSID + "' placeholder='Enter WiFi SSID'>";
  html += "<label for='wifiPassword'>WiFi Password:</label>";
  html += "<input type='password' id='wifiPassword' name='wifiPassword' placeholder='Enter WiFi password'>";
  
  html += "<button type='submit'>Save Configuration</button>";
  html += "</form></div></body></html>";
  
  webServer.send(200, "text/html", html);
}


void handleSave() {
  bool configUpdated = false;
  String message = "<ul>";
  String errorMessage = "";
  
  // Collect new values
  String newUserId = "";
  String newWifiSSID = "";
  String newWifiPassword = "";
  
  if (webServer.hasArg("userId")) {
    newUserId = webServer.arg("userId");
    newUserId.trim();
  }
  
  if (webServer.hasArg("wifiSSID")) {
    newWifiSSID = webServer.arg("wifiSSID");
    newWifiSSID.trim();
  }
  
  if (webServer.hasArg("wifiPassword")) {
    newWifiPassword = webServer.arg("wifiPassword");
    // Don't trim password as spaces might be valid
  }
  
  // Validate WiFi credentials if provided
  bool wifiValid = true;
  if (!newWifiSSID.isEmpty()) {
    display.clearDisplay();
    display.setCursor(0, 0);
    display.println("Testing WiFi...");
    display.setCursor(0, 20);
    display.println(newWifiSSID);
    display.display();
    
    // Accept WiFi credentials even if test fails (network might not be in range)
    // Just display a message telling user the test failed but credentials are saved
    if (!testWiFiConnection(newWifiSSID, newWifiPassword)) {
      errorMessage += "<p>WiFi connection test failed. Credentials saved, but network might not be available.</p>";
    }
  }
  
  // Validate user ID if provided
  bool userValid = true;
  if (!newUserId.isEmpty()) {
    display.clearDisplay();
    display.setCursor(0, 0);
    display.println("Verifying user...");
    display.setCursor(0, 20);
    display.println(maskString(newUserId));
    display.display();
    
    // In setup mode, accept any user ID
    if (setupMode) {
      userValid = true;
    } else {
      userValid = verifyUserID(newUserId);
    }
    
    if (!userValid) {
      errorMessage += "<p>User ID verification failed. ID not recognized by the system.</p>";
    }
  }
  
  // Update configurations if validations passed
  bool updateUserID = !newUserId.isEmpty() && userValid;
  bool updateWiFi = !newWifiSSID.isEmpty();
  
  if (updateUserID) {
    userId = newUserId;
    if (!preferences.putString("userId", userId)) {
      errorMessage += "<p>Failed to save User ID to device memory.</p>";
      configUpdated = false;
    } else {
      configUpdated = true;
      message += "<li>User ID updated to: <strong>" + maskString(userId) + "</strong></li>";
      Serial.println("User ID updated to: " + maskString(userId));
    }
  }
  
  if (updateWiFi) {
    wifiSSID = newWifiSSID;
    if (!preferences.putString("wifiSSID", wifiSSID)) {
      errorMessage += "<p>Failed to save WiFi SSID to device memory.</p>";
      configUpdated = false;
    } else {
      configUpdated = true;
      message += "<li>WiFi network updated to: <strong>" + wifiSSID + "</strong></li>";
      Serial.println("WiFi SSID updated to: " + wifiSSID);
    
      if (!newWifiPassword.isEmpty()) {
        wifiPassword = newWifiPassword;
        if (!preferences.putString("wifiPassword", wifiPassword)) {
          errorMessage += "<p>Failed to save WiFi password to device memory.</p>";
        } else {
          message += "<li>WiFi password updated</li>";
          Serial.println("WiFi password was updated");
        }
      }
    }
  }
  
  message += "</ul>";
  
  if (configUpdated) {
    // Display the success page
    String html = "<!DOCTYPE html><html lang='en'>";
    html += "<head><meta charset='UTF-8'><meta name='viewport' content='width=device-width, initial-scale=1.0'>";
    html += "<title>Configuration Saved</title>";
    html += "<style>";
    html += "* { box-sizing: border-box; font-family: Arial, sans-serif; }";
    html += "body { background-color: #f5f5f5; color: #333; margin: 0; padding: 20px; }";
    html += ".container { max-width: 500px; margin: 0 auto; background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1); text-align: center; }";
    html += "h1 { color: #4CAF50; }";
    html += "p { line-height: 1.5; margin-bottom: 15px; }";
    html += ".success { background-color: #e8f5e9; border-left: 4px solid #4CAF50; padding: 12px; margin: 20px 0; text-align: left; }";
    html += ".warning { background-color: #fffde7; border-left: 4px solid #fdd835; padding: 12px; margin: 20px 0; text-align: left; }";
    html += "ul { text-align: left; padding-left: 20px; }";
    html += "li { margin-bottom: 8px; }";
    html += ".btn { background-color: #2196F3; color: white; border: none; padding: 12px 20px; border-radius: 4px; cursor: pointer; font-size: 16px; text-decoration: none; display: inline-block; margin-top: 10px; }";
    html += ".btn:hover { background-color: #0b7dda; }";
    html += ".icon { font-size: 48px; margin-bottom: 10px; }";
    html += "</style>";
    html += "</head>";
    html += "<body><div class='container'>";
    html += "<div class='icon'>✅</div>";
    html += "<h1>Configuration Saved!</h1>";
    
    html += "<div class='success'>";
    html += message;
    html += "</div>";
    
    if (errorMessage != "") {
      html += "<div class='warning'>";
      html += errorMessage;
      html += "</div>";
    }
    
    html += "<p>The device will automatically exit setup mode in 2 minutes.</p>";
    html += "<p>You can also press the CONFIG button to exit setup mode now.</p>";
    
    // Add a link to go back to the setup page
    html += "<a href='/' class='btn'>Return to Setup</a>";
    
    html += "</div></body></html>";
    
    webServer.send(200, "text/html", html);
    
    // Show success on display
    display.clearDisplay();
    display.setTextSize(1);
    display.setCursor(0, 0);
    display.println("Settings saved!");
    if (!userId.isEmpty()) {
      display.setCursor(0, 16);
      display.println("ID: " + maskString(userId));
    }
    if (!wifiSSID.isEmpty()) {
      display.setCursor(0, 32);
      display.println("WiFi: " + wifiSSID.substring(0, 16) + (wifiSSID.length() > 16 ? "..." : ""));
    }
    display.setCursor(0, 48);
    display.println("Setup successful!");
    display.display();
    
    // Debug info to serial
    Serial.println("Configuration updated successfully");
    Serial.println("User ID in preferences: " + preferences.getString("userId", "NOT FOUND"));
    Serial.println("WiFi SSID in preferences: " + preferences.getString("wifiSSID", "NOT FOUND"));
  } else {
    // Display the failure page
    String html = "<!DOCTYPE html><html lang='en'>";
    html += "<head><meta charset='UTF-8'><meta name='viewport' content='width=device-width, initial-scale=1.0'>";
    html += "<title>Configuration Failed</title>";
    html += "<style>";
    html += "* { box-sizing: border-box; font-family: Arial, sans-serif; }";
    html += "body { background-color: #f5f5f5; color: #333; margin: 0; padding: 20px; }";
    html += ".container { max-width: 500px; margin: 0 auto; background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1); text-align: center; }";
    html += "h1 { color: #e74c3c; }";
    html += "p { line-height: 1.5; margin-bottom: 15px; }";
    html += ".error { background-color: #fdecea; border-left: 4px solid #e74c3c; padding: 12px; margin: 20px 0; text-align: left; }";
    html += ".btn { background-color: #3498db; color: white; border: none; padding: 12px 20px; border-radius: 4px; cursor: pointer; font-size: 16px; text-decoration: none; display: inline-block; margin-top: 10px; }";
    html += ".btn:hover { background-color: #2980b9; }";
    html += ".icon { font-size: 48px; margin-bottom: 10px; }";
    html += "</style>";
    html += "</head>";
    html += "<body><div class='container'>";
    html += "<div class='icon'>❌</div>";
    html += "<h1>Configuration Failed</h1>";
    
    html += "<div class='error'>";
    if (errorMessage != "") {
      html += errorMessage;
    } else {
      html += "<p>No configuration changes were made. Please check your inputs and try again.</p>";
    }
    html += "</div>";
    
    html += "<a href='/' class='btn'>Go Back</a>";
    html += "</div></body></html>";
    
    webServer.send(400, "text/html", html);
    
    // Show failure on display
    display.clearDisplay();
    display.setCursor(0, 0);
    display.println("Save failed!");
    display.setCursor(0, 20);
    display.println("Check settings");
    display.setCursor(0, 40);
    display.println("Try again");
    display.display();
    
    Serial.println("Configuration update failed");
    Serial.println(errorMessage);
  }
}

void setupWebServerWithAuth() {
  // Stop any previous server
  webServer.stop();
  
  // Setup web server with authentication
  webServer.on("/", HTTP_GET, handleLogin);
  webServer.on("/login", HTTP_POST, handleLoginPost);
  webServer.on("/setup", HTTP_GET, handleRoot);
  webServer.on("/save", HTTP_POST, handleSave);
  webServer.onNotFound([]() {
    webServer.sendHeader("Location", "http://192.168.4.1/", true);
    webServer.send(302, "text/plain", "");
  });
  
  webServer.begin();
}


void handleLogin() {
  String html = "<!DOCTYPE html><html><head><title>PMD Health Device Login</title>";
  html += "<meta name='viewport' content='width=device-width, initial-scale=1'>";
  html += "<style>";
  html += "body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; color: #333; }";
  html += ".container { max-width: 500px; margin: 0 auto; background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1); }";
  html += "h1 { color: #2c3e50; text-align: center; margin-bottom: 20px; }";
  html += "p { line-height: 1.5; }";
  html += ".info { background-color: #e8f4fd; border-left: 4px solid #2196F3; padding: 12px; margin-bottom: 20px; }";
  html += "label { display: block; margin-bottom: 8px; font-weight: bold; }";
  html += "input[type='password'] { width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 4px; box-sizing: border-box; margin-bottom: 20px; }";
  html += "button { background-color: #4CAF50; color: white; border: none; padding: 12px 20px; border-radius: 4px; cursor: pointer; width: 100%; font-size: 16px; }";
  html += "button:hover { background-color: #45a049; }";
  html += ".error { color: #e74c3c; margin-bottom: 15px; }";
  html += "</style></head>";
  html += "<body><div class='container'>";
  html += "<h1>PMD Health Device</h1>";
  
  html += "<div class='info'>";
  html += "<p>Device ID: <strong>" + deviceId + "</strong></p>";
  html += "</div>";
  
  // Show error message if login failed
  if (webServer.hasArg("error")) {
    html += "<div class='error'><p>Invalid User ID. Please try again.</p></div>";
  }
  
  html += "<form action='/login' method='post'>";
  html += "<label for='userId'>Enter User ID:</label>";
  html += "<input type='password' id='userId' name='userId' placeholder='Enter your user ID' required>";
  html += "<button type='submit'>Login</button>";
  html += "</form></div></body></html>";
  
  webServer.send(200, "text/html", html);
}

// Login form handler
void handleLoginPost() {
  if (webServer.hasArg("userId")) {
    String loginUserId = webServer.arg("userId");
    loginUserId.trim();
    
    if (loginUserId.isEmpty()) {
      // Redirect back to login with error
      webServer.sendHeader("Location", "/?error=1", true);
      webServer.send(302, "text/plain", "");
      return;
    }
    
    // Verify the user ID
    bool userVerified = verifyUserID(loginUserId);
    
    if (!userVerified) {
      // Redirect back to login with error
      webServer.sendHeader("Location", "/?error=1", true);
      webServer.send(302, "text/plain", "");
      return;
    }
    
    // If we get here, user is verified
    // Set the user ID if it's not already set
    if (userId != loginUserId) {
      userId = loginUserId;
      preferences.putString("userId", userId);
      
      Serial.println("User ID set via login: (masked for security)");
    }
    
    // Redirect to setup page
    webServer.sendHeader("Location", "/setup", true);
    webServer.send(302, "text/plain", "");
  } else {
    // Redirect back to login with error
    webServer.sendHeader("Location", "/?error=1", true);
    webServer.send(302, "text/plain", "");
  }
}

void resetSteps() {
  stepCount = 0;
  caloriesBurned = 0;
  distanceInKm = 0;
  Serial.println("Step count and related metrics reset to zero");
  
  // Show confirmation on display
  if (displayOn) {
    display.clearDisplay();
    display.setTextSize(1);
    display.setCursor(0, 0);
    display.println("Steps Reset!");
    display.setCursor(0, 20);
    display.println("Count: 0");
    display.setCursor(0, 30);
    display.println("Calories: 0");
    display.setCursor(0, 40);
    display.println("Distance: 0 km");
    display.display();
    delay(2000);
    updateDisplay();
  }
}

void checkSerialCommand() {
  if (Serial.available() > 0) {
    String input = Serial.readStringUntil('\n');
    input.trim();
    
    if (input.startsWith("USERID:")) {
      String newUserId = input.substring(7);
      newUserId.trim();
           
      if (newUserId.length() > 0) {
        // Verify the User ID
        bool userVerified = verifyUserID(newUserId);
        
        if (userVerified) {
          userId = newUserId;
          preferences.putString("userId", userId);
          
          Serial.println("User ID updated via Serial (masked for security)");
          
          // Display on OLED
          display.clearDisplay();
          display.setCursor(0, 0);
          display.println("User ID Updated!");
          display.setCursor(0, 20);
          display.println("ID: " + maskString(userId));
          display.setCursor(0, 40);
          display.println("Update successful!");
          display.display();
        } else {
          Serial.println("Error: User ID verification failed. This ID does not exist in our system.");
          
          // Display error on OLED
          display.clearDisplay();
          display.setCursor(0, 0);
          display.println("User ID Error!");
          display.setCursor(0, 20);
          display.println("ID verification");
          display.setCursor(0, 30);
          display.println("failed!");
          display.display();
        }
      } else {
        Serial.println("Error: User ID cannot be empty");
      }
    } 
    else if (input.startsWith("WIFI:")) {
      // Format: WIFI:SSID,PASSWORD
      int commaPos = input.indexOf(',', 5);
      if (commaPos > 5) {
        String newSSID = input.substring(5, commaPos);
        String newPassword = input.substring(commaPos + 1);
        newSSID.trim();
        newPassword.trim();
        
        if (newSSID.length() > 0) {
          wifiSSID = newSSID;
          preferences.putString("wifiSSID", wifiSSID);
          
          if (newPassword.length() > 0) {
            wifiPassword = newPassword;
            preferences.putString("wifiPassword", wifiPassword);
          }
          
          Serial.println("WiFi settings updated via Serial");
          Serial.println("SSID: " + wifiSSID);
          
          // Display on OLED
          display.clearDisplay();
          display.setCursor(0, 0);
          display.println("WiFi Updated!");
          display.setCursor(0, 20);
          display.println("SSID: " + wifiSSID);
          display.setCursor(0, 40);
          display.println("Update successful!");
          display.display();
          
          // Attempt to connect with new settings
          connectToWiFi();
        } else {
          Serial.println("Error: WiFi SSID cannot be empty");
        }
      } else {
        Serial.println("Error: Invalid WiFi command format. Use WIFI:SSID,PASSWORD");
      }
    } 
    else if (input == "RESETSTEPS") {
      // New command to reset only the step counter
      stepCount = 0;
      caloriesBurned = 0;
      distanceInKm = 0;
      Serial.println("Step count and related metrics reset to zero");
      
      // Show confirmation on display
      if (displayOn) {
        display.clearDisplay();
        display.setTextSize(1);
        display.setCursor(0, 0);
        display.println("Steps Reset!");
        display.setCursor(0, 20);
        display.println("Count: 0");
        display.setCursor(0, 30);
        display.println("Calories: 0");
        display.setCursor(0, 40);
        display.println("Distance: 0 km");
        display.display();
        delay(2000);
        updateDisplay();
      }
    }
    else if (input == "STATUS") {
      // Command to query the current status
      Serial.println("\n=== PMD Health Device Status ===");
      Serial.println("Device ID: " + deviceId);
      
      // Mask the user ID in status output
      if (userId.isEmpty()) {
        Serial.println("User ID: Not set");
      } else {
        Serial.println("User ID: " + maskString(userId));
      }
      
      Serial.println("WiFi SSID: " + (wifiSSID.isEmpty() ? "Not set" : wifiSSID));
      Serial.println("Setup Mode: " + String(setupMode ? "Active" : "Inactive"));
      if (!setupMode) {
        Serial.println("WiFi Status: " + String(WiFi.status() == WL_CONNECTED ? "Connected" : "Disconnected"));
        Serial.println("Temperature: " + String(temperature) + "°C");
        Serial.println("Heart Rate: " + String(beatAvg) + " BPM");
        Serial.println("Step Count: " + String(stepCount));
        Serial.println("Calories: " + String(caloriesBurned));
        Serial.println("Distance: " + String(distanceInKm) + " km");
        Serial.println("Firebase BP Data:");
        Serial.println("  Systolic: " + String(systolicValue) + " mmHg");
        Serial.println("  Diastolic: " + String(diastolicValue) + " mmHg");
        Serial.println("  Remote BPM: " + String(remoteBPM));
      }
      Serial.println("==============================\n");
    } 
    else if (input == "DEBUGACCEL") {
      // New command to print accelerometer data continuously for debugging
      Serial.println("Starting accelerometer debug mode for 10 seconds...");
      
      unsigned long debugStartTime = millis();
      while (millis() - debugStartTime < 10000) {
        mpu.update();
        float accelX = mpu.getAccX();
        float accelY = mpu.getAccY();
        float accelZ = mpu.getAccZ();
        float accelMagnitude = sqrt(accelX*accelX + accelY*accelY + accelZ*accelZ);
        
        Serial.print("Accel: X=");
        Serial.print(accelX);
        Serial.print(" Y=");
        Serial.print(accelY);
        Serial.print(" Z=");
        Serial.print(accelZ);
        Serial.print(" Mag=");
        Serial.println(accelMagnitude);
        
        delay(100); // Print 10 times per second
      }
      
      Serial.println("Accelerometer debug mode finished");
    }
    else if (input == "BUZZERTEST") {
      Serial.println("Testing buzzer alert pattern...");
      playAlertPattern();
      Serial.println("Buzzer test complete");
    }
    else if (input == "RESETVITALTIMER") {
      lastVitalSignsUpdate = millis();
      alertSilenced = false;
      alertActive = false;  // Also reset alert active state
      forceTimerReset = false; // Reset this flag too
      preferences.putLong("lastVitalUpdate", lastVitalSignsUpdate);
      
      // Also save the current epoch time
      time_t now = time(nullptr);
      preferences.putLong("lastVitalEpoch", now);
      
      Serial.println("Vital signs timer manually reset. Next alert in 2 minutes.");
      
      // Display confirmation
      if (displayOn) {
        display.clearDisplay();
        display.setTextSize(1);
        display.setCursor(0, 0);
        display.println("Timer Reset");
        display.setCursor(0, 20);
        display.println("Next alert in");
        display.setCursor(0, 30);
        display.println("2 minutes");
        display.display();
        delay(2000);
        updateDisplay();
      }
    }
    else if (input == "RESET") {
      // Command to reset all configuration
      userId = "";
      wifiSSID = "";
      wifiPassword = "";
      preferences.putString("userId", "");
      preferences.putString("wifiSSID", "");
      preferences.putString("wifiPassword", "");
      Serial.println("All configuration has been reset. Device will need to be configured again.");
      
      display.clearDisplay();
      display.setCursor(0, 0);
      display.println("Settings Reset!");
      display.setCursor(0, 20);
      display.println("Please configure");
      display.setCursor(0, 30);
      display.println("device again.");
      display.display();
      
      // Enter setup mode
      if (!setupMode) {
        setupMode = true;
        setupModeTimeout = millis() + SETUP_MODE_DURATION;
        startCaptivePortal();
      }
    } 
    else if (input == "HELP") {
      // Print help information
      Serial.println("\n=== PMD Health Device Commands ===");
      Serial.println("USERID:[value]       - Set the user ID");
      Serial.println("WIFI:SSID,PASSWORD   - Set WiFi credentials");
      Serial.println("STATUS               - Show current device status");
      Serial.println("RESETSTEPS           - Reset step counter to zero");
      Serial.println("DEBUGACCEL           - Show accelerometer values for 10 seconds");
      Serial.println("BUZZERTEST           - Test the buzzer alert pattern");
      Serial.println("RESETVITALTIMER      - Reset the 2-minute vital signs alert timer");  // Updated text here
      Serial.println("RESET                - Reset all settings and enter setup mode");
      Serial.println("HELP                 - Show this help information");
      Serial.println("================================\n");
    }
  }
}

// Replace the preferences.contains check with a different approach
void initializeTimer() {
  // Initialize the timer value
  lastVitalSignsUpdate = millis();
  
  // Check if there's a saved value
  unsigned long savedUpdate = preferences.getLong("lastVitalUpdate", 0);
  if (savedUpdate > 0) {
    // Consider if device was rebooted
    if (savedUpdate > millis()) {
      // Device was rebooted, calculate elapsed time from epoch time
      time_t now = time(nullptr);
      time_t savedEpoch = preferences.getLong("lastVitalEpoch", 0);
      unsigned long elapsedSeconds = (now > savedEpoch) ? (now - savedEpoch) : 0;
      
      if (elapsedSeconds < (4 * 60 * 60)) {
        // Not yet 4 hours, calculate remaining time
        unsigned long remainingSeconds = (4 * 60 * 60) - elapsedSeconds;
        lastVitalSignsUpdate = millis() - (VITALS_SIGNS_ALERT_INTERVAL - (remainingSeconds * 1000));
      } else {
        // More than 4 hours, trigger alert soon
        lastVitalSignsUpdate = millis() - VITALS_SIGNS_ALERT_INTERVAL + (60 * 1000); // Alert in 1 minute
      }
    } else {
      // Normal case - load saved value
      lastVitalSignsUpdate = savedUpdate;
    }
  }
}

void displayStatus() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.println("PMD Health Device");
  
  display.setCursor(0, 12);
  display.println("Device ID:");
  display.setCursor(0, 22);
  display.println(deviceId.substring(0, 20));
  
  if (userId.isEmpty()) {
    display.setCursor(0, 34);
    display.println("User: Not set");
  } else {
    display.setCursor(0, 34);
    display.println("User: " + maskString(userId));
  }
  
  display.setCursor(0, 46);
  if (wifiSSID.isEmpty()) {
    display.println("WiFi: Not configured");
  } else {
    display.println("WiFi: " + wifiSSID.substring(0, 16) + (wifiSSID.length() > 16 ? "..." : ""));
  }
  
  display.display();
}
