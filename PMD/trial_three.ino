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

// Config button
#define CONFIG_BUTTON_PIN 0

// Access Point settings
const char* apSSID = "PMD-HealthDevice";
const IPAddress apIP(192, 168, 4, 1);
const byte DNS_PORT = 53;

// WiFi settings for normal operation mode
const char* ssid = "Marvin";
const char* password = "12345678";

// Firestore settings
const char* firestoreProjectId = "finale-813d8"; // Your Firebase project ID
const char* firestoreAPIKey = "AIzaSyBiBVye_Jru8BLq96LeLhkNpbOhyHkLM6A"; // Your Firebase API key

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

// Heart Rate variables
const byte RATE_SIZE = 4;
byte rates[RATE_SIZE];
byte rateSpot = 0;
long lastBeat = 0;

// Time tracking
unsigned long lastReadingTime = 0;
unsigned long lastUploadTime = 0;
const unsigned long READING_INTERVAL = 2000;  // Read sensors every 2 seconds
const unsigned long UPLOAD_INTERVAL = 60000;  // Upload data every 60 seconds

// Display state
bool showingTime = true;
unsigned long displayToggleTime = 0;
const unsigned long DISPLAY_TOGGLE_INTERVAL = 5000; // Toggle display every 5 seconds

void setup() {
  // Start Serial for debugging
  Serial.begin(115200);
  delay(100); // Short delay to stabilize
  Serial.println("\n\nStarting PMD Health Device...");
  
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
  
  // Setup configuration button
  pinMode(CONFIG_BUTTON_PIN, INPUT_PULLUP);
  
  // Initialize preferences storage
  preferences.begin("pmdevice", false);
  
  // Load saved configuration
  userId = preferences.getString("userId", "");
  deviceId = preferences.getString("deviceId", "");
  
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
  
  // Check if we should enter setup mode
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
    Serial.println("Waiting for time sync");
    time_t now = time(nullptr);
    while (now < 8 * 3600 * 2) {
      delay(500);
      Serial.print(".");
      now = time(nullptr);
    }
    Serial.println("Time synchronized");
    
    // Display status
    displayStatus();
  }
  
  // Print serial configuration instructions
  Serial.println("\n=== PMD Health Device Configuration ===");
  Serial.println("Device ID: " + deviceId);
  Serial.println("Current User ID: " + (userId.isEmpty() ? "Not set" : userId));
  Serial.println("To set user ID via serial, send: USERID:[your-user-id]");
  Serial.println("Example: USERID:abc123def456");
  Serial.println("=======================================\n");
}

void loop() {
  if (setupMode) {
    // Handle DNS and HTTP requests in setup mode
    dnsServer.processNextRequest();
    webServer.handleClient();
    
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
      // Only perform normal operations if the device is configured
      
      // Read sensor data at regular intervals
      if (millis() - lastReadingTime >= READING_INTERVAL) {
        readSensorData();
        lastReadingTime = millis();
      }
      
      // Toggle display between time and sensor data
      if (millis() - displayToggleTime >= DISPLAY_TOGGLE_INTERVAL) {
        showingTime = !showingTime;
        displayToggleTime = millis();
        
        if (showingTime) {
          displayTime();
        } else {
          displaySensorData();
        }
      }
      
      // Upload data to Firestore at regular intervals
      if (WiFi.status() == WL_CONNECTED && (millis() - lastUploadTime >= UPLOAD_INTERVAL)) {
        uploadToFirestore();
        lastUploadTime = millis();
      }
      
      // Check if WiFi connection is lost and try to reconnect
      if (WiFi.status() != WL_CONNECTED && millis() - lastUploadTime >= 300000) { // Try reconnecting every 5 minutes
        Serial.println("WiFi connection lost. Attempting to reconnect...");
        connectToWiFi();
      }
    }
  }
  
  // Always check for serial commands
  checkSerialCommand();
  
  // Check for config button press during normal operation
  if (!setupMode && digitalRead(CONFIG_BUTTON_PIN) == LOW) {
    delay(50); // Debounce
    if (digitalRead(CONFIG_BUTTON_PIN) == LOW) {
      // Wait for button release
      while (digitalRead(CONFIG_BUTTON_PIN) == LOW) {
        delay(10);
      }
      
      Serial.println("Config button pressed, entering setup mode...");
      setupMode = true;
      setupModeTimeout = millis() + SETUP_MODE_DURATION;
      
      // Disconnect from WiFi
      WiFi.disconnect();
      
      // Start captive portal
      startCaptivePortal();
    }
  }
  
  // Small delay to prevent watchdog issues
  delay(10);
}

void connectToWiFi() {
  Serial.println("Connecting to WiFi...");
  display.clearDisplay();
  display.setCursor(0, 0);
  display.println("Connecting to WiFi");
  display.setCursor(0, 20);
  display.println(ssid);
  display.display();
  
  // Connect to WiFi
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);
  
  // Wait for connection with timeout
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print(".");
    display.print(".");
    display.display();
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi connected");
    Serial.println("IP address: " + WiFi.localIP().toString());
    
    display.clearDisplay();
    display.setCursor(0, 0);
    display.println("WiFi connected!");
    display.setCursor(0, 20);
    display.println("IP: " + WiFi.localIP().toString());
    display.display();
    delay(2000);  // Show connection info briefly
  } else {
    Serial.println("\nWiFi connection failed");
    display.clearDisplay();
    display.setCursor(0, 0);
    display.println("WiFi connection");
    display.setCursor(0, 10);
    display.println("failed!");
    display.setCursor(0, 30);
    display.println("Working in");
    display.setCursor(0, 40);
    display.println("offline mode");
    display.display();
    delay(2000);  // Show error briefly
  }
}

void readSensorData() {
  // Update MPU6050 readings
  mpu.update();
  float accelX = mpu.getAccX();
  float accelY = mpu.getAccY();
  float accelZ = mpu.getAccZ();
  float accelMagnitude = sqrt(accelX * accelX + accelY * accelY + accelZ * accelZ);
  
  // Detect steps
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
  
  // Calculate active minutes (simple - just count time device has been on)
  activeMinutes = (millis() / 60000) % 1000; // Minutes since power-on
  
  // Print sensor data to serial
  Serial.println("Sensor readings:");
  Serial.print("Steps: "); Serial.print(stepCount);
  Serial.print(" | Calories: "); Serial.print(caloriesBurned, 1);
  Serial.print(" | Distance: "); Serial.print(distanceInKm, 2); Serial.println(" km");
  Serial.print("Temperature: "); Serial.print(temperature); Serial.println(" C");
  Serial.print("Heart Rate: "); Serial.print(beatAvg); Serial.println(" BPM");
  Serial.print("Active Minutes: "); Serial.println(activeMinutes);
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

void displaySensorData() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  
  display.setCursor(0, 0);
  display.print("Time: ");
  
  struct tm timeinfo;
  if(getLocalTime(&timeinfo)){
    char timeStr[6];
    sprintf(timeStr, "%02d:%02d", timeinfo.tm_hour, timeinfo.tm_min);
    display.println(timeStr);
  } else {
    display.println("--:--");
  }
  
  display.setCursor(0, 12);
  display.print("Steps: ");
  display.print(stepCount);
  display.print(" Cal: ");
  display.print(caloriesBurned, 1);
  
  display.setCursor(0, 24);
  display.print("Dist: ");
  display.print(distanceInKm, 2);
  display.println(" km");
  
  display.setCursor(0, 36);
  display.print("Temp: ");
  display.print(temperature);
  display.print(" C");
  
  display.setCursor(0, 48);
  display.print("BPM: ");
  display.print(beatAvg);
  
  display.display();
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
  
  // For vital signs
  String vitalSignsJson = "{\"fields\":{";
  vitalSignsJson += "\"heart_rate\":{\"stringValue\":\"" + String(beatAvg) + "\"},";
  vitalSignsJson += "\"temperature\":{\"stringValue\":\"" + String(temperature) + "\"},";
  vitalSignsJson += "\"timestamp\":{\"timestampValue\":\"" + String(timestamp) + "\"},";
  vitalSignsJson += "\"user_id\":{\"stringValue\":\"" + userId + "\"}";
  vitalSignsJson += "}}";
  
  Serial.println("Uploading activity data to Firestore...");
  sendToFirestore("activity", jsonData);
  
  Serial.println("Uploading vital signs data to Firestore...");
  sendToFirestore("vital_signs", vitalSignsJson);
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
  Serial.println("Payload: " + jsonData);
  
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  
  int httpResponseCode = http.POST(jsonData);
  
  if (httpResponseCode > 0) {
    String response = http.getString();
    Serial.println("HTTP Response code: " + String(httpResponseCode));
    Serial.println("Response: " + response);
  } else {
    Serial.println("Error on sending POST request: " + String(httpResponseCode));
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
  html += "p { line-height: 1.5; }";
  html += ".info { background-color: #e8f4fd; border-left: 4px solid #2196F3; padding: 12px; margin-bottom: 20px; }";
  html += "label { display: block; margin-bottom: 8px; font-weight: bold; }";
  html += "input[type='text'] { width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 4px; box-sizing: border-box; margin-bottom: 20px; }";
  html += "button { background-color: #4CAF50; color: white; border: none; padding: 12px 20px; border-radius: 4px; cursor: pointer; width: 100%; font-size: 16px; }";
  html += "button:hover { background-color: #45a049; }";
  html += "</style></head>";
  html += "<body><div class='container'>";
  html += "<h1>PMD Health Device Setup</h1>";
  html += "<div class='info'>";
  html += "<p>Device ID: <strong>" + deviceId + "</strong></p>";
  html += "<p>Current User ID: <strong>" + (userId.isEmpty() ? "Not set" : userId) + "</strong></p>";
  html += "</div>";
  html += "<p>Enter your user ID provided by the PMD Health app:</p>";
  html += "<form action='/save' method='post'>";
  html += "<label for='userId'>User ID:</label>";
  html += "<input type='text' id='userId' name='userId' value='" + userId + "' placeholder='Enter your user ID'>";
  html += "<button type='submit'>Save Configuration</button>";
  html += "</form></div></body></html>";
  
  webServer.send(200, "text/html", html);
}

void handleSave() {
  if (webServer.hasArg("userId")) {
    String newUserId = webServer.arg("userId");
    newUserId.trim();
    
    if (newUserId.length() > 0) {
      userId = newUserId;
      preferences.putString("userId", userId);
      
      String html = "<!DOCTYPE html><html><head><title>Configuration Saved</title>";
      html += "<meta name='viewport' content='width=device-width, initial-scale=1'>";
      html += "<style>";
      html += "body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; color: #333; }";
      html += ".container { max-width: 500px; margin: 0 auto; background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1); text-align: center; }";
      html += "h1 { color: #4CAF50; }";
      html += "p { line-height: 1.5; margin-bottom: 15px; }";
      html += ".success { background-color: #e8f5e9; border-left: 4px solid #4CAF50; padding: 12px; margin: 20px 0; text-align: left; }";
      html += "button { background-color: #2196F3; color: white; border: none; padding: 12px 20px; border-radius: 4px; cursor: pointer; font-size: 16px; }";
      html += "button:hover { background-color: #0b7dda; }";
      html += "</style></head>";
      html += "<body><div class='container'>";
      html += "<h1>Configuration Saved!</h1>";
      html += "<div class='success'>";
      html += "<p>Your device is now configured with User ID: <strong>" + userId + "</strong></p>";
      html += "</div>";
      html += "<p>The device will automatically exit setup mode in 2 minutes, or you can restart it now.</p>";
      html += "<p>You can close this page.</p>";
      html += "</div></body></html>";
      
      webServer.send(200, "text/html", html);
      
      // Show success on display
      display.clearDisplay();
      display.setCursor(0, 0);
      display.println("User ID saved!");
      display.setCursor(0, 20);
      display.println("ID: " + userId.substring(0, 16) + (userId.length() > 16 ? "..." : ""));
      display.setCursor(0, 40);
      display.println("Setup successful!");
      display.display();
      
      Serial.println("User ID updated via WiFi to: " + userId);
    } else {
      webServer.send(400, "text/html", "<html><body><h1>Error</h1><p>User ID cannot be empty</p><p><a href='/'>Go back</a></p></body></html>");
    }
  } else {
    webServer.send(400, "text/html", "<html><body><h1>Error</h1><p>Missing user ID parameter</p><p><a href='/'>Go back</a></p></body></html>");
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
        userId = newUserId;
        preferences.putString("userId", userId);
        
        Serial.println("User ID updated via Serial to: " + userId);
        
        // Display on OLED
        display.clearDisplay();
        display.setCursor(0, 0);
        display.println("User ID Updated!");
        display.setCursor(0, 20);
        display.println("ID: " + userId.substring(0, 16) + (userId.length() > 16 ? "..." : ""));
        display.setCursor(0, 40);
        display.println("Setup successful!");
        display.display();
        
        // Exit setup mode if we were in it
        if (setupMode) {
          Serial.println("Exiting setup mode");
          setupMode = false;
          stopCaptivePortal();
          
          // Connect to WiFi for normal operation
          connectToWiFi();
          
          // Give time for the user to read the display
          delay(3000);
          displayStatus();
        }
      } else {
        Serial.println("Error: User ID cannot be empty");
      }
    } else if (input == "STATUS") {
      // Command to query the current status
      Serial.println("\n=== PMD Health Device Status ===");
      Serial.println("Device ID: " + deviceId);
      Serial.println("User ID: " + (userId.isEmpty() ? "Not set" : userId));
      Serial.println("Setup Mode: " + String(setupMode ? "Active" : "Inactive"));
      if (!setupMode) {
        Serial.println("WiFi Status: " + String(WiFi.status() == WL_CONNECTED ? "Connected" : "Disconnected"));
        Serial.println("Temperature: " + String(temperature) + "°C");
        Serial.println("Heart Rate: " + String(beatAvg) + " BPM");
        Serial.println("Step Count: " + String(stepCount));
        Serial.println("Calories: " + String(caloriesBurned));
        Serial.println("Distance: " + String(distanceInKm) + " km");
      }
      Serial.println("==============================\n");
    } else if (input == "RESET") {
      // Command to reset user ID
      userId = "";
      preferences.putString("userId", "");
      Serial.println("User ID has been reset. Device will need to be configured again.");
      
      display.clearDisplay();
      display.setCursor(0, 0);
      display.println("User ID Reset!");
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
    
    } else if (input == "HELP") {
      // Print help information
      Serial.println("\n=== PMD Health Device Commands ===");
      Serial.println("USERID:[value]  - Set the user ID");
      Serial.println("STATUS          - Show current device status");
      Serial.println("RESET           - Reset user ID and enter setup mode");
      Serial.println("HELP            - Show this help information");
      Serial.println("================================\n");
    }
  }
}

void displayStatus() {
  display.clearDisplay();
  display.setCursor(0, 0);
  display.println("PMD Health Device");
  display.setCursor(0, 16);
  display.println("Device ID:");
  display.setCursor(0, 26);
  display.println(deviceId.substring(0, 20));
  
  if (userId.isEmpty()) {
    display.setCursor(0, 46);
    display.println("Not configured!");
  } else {
    display.setCursor(0, 46);
    display.println("User: " + userId.substring(0, 16) + (userId.length() > 16 ? "..." : ""));
  }
  
  display.display();
}