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
#define SCREEN_TOGGLE_PIN 6  // Button for toggling display on/off (GPIO0)
// #define DATA_CYCLE_PIN 7     // Button for cycling through data screens (GPIO1)

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
const int NUM_SCREENS = 2;

// Button state
bool screenTogglePressed = false;
bool dataCyclePressed = false;
unsigned long lastButtonPress = 0;
const unsigned long BUTTON_LONG_PRESS = 1000; // 1 second for long press


String maskString(String input, int visibleChars = 3) {
  if (input.length() <= visibleChars * 2) {
    return input; // If string is short, don't mask
  }
  
  String first = input.substring(0, visibleChars);
  String last = input.substring(input.length() - visibleChars);
  
  // Return masked string with asterisks in the middle
  return first + "****" + last;
}

// Function to verify user ID against the backend
bool verifyUserID(String userIdToVerify) {
  if (userIdToVerify.isEmpty()) {
    return false;
  }
  
  // We need to check if this user ID exists in our backend (Firebase)
  if (WiFi.status() != WL_CONNECTED) {
    // Try to connect to WiFi with current credentials, if we have them
    if (!wifiSSID.isEmpty() && !wifiPassword.isEmpty()) {
      WiFi.begin(wifiSSID.c_str(), wifiPassword.c_str());
      
      // Short wait for connection
      int attempts = 0;
      while (WiFi.status() != WL_CONNECTED && attempts < 10) {
        delay(500);
        attempts++;
      }
    }
    
    // If still not connected, we can't verify
    if (WiFi.status() != WL_CONNECTED) {
      Serial.println("Cannot verify user ID: No WiFi connection");
      return true; // Allow the user ID to be set without verification when offline
    }
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
    userExists = false;
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

// Function to test WiFi credentials before saving them
bool testWiFiConnection(String ssid, String password) {
  if (ssid.isEmpty()) {
    return false;
  }
  
  Serial.println("Testing WiFi credentials for SSID: " + ssid);
  
  // Save current connection state
  WiFiMode_t currentMode = WiFi.getMode();
  bool wasConnected = (WiFi.status() == WL_CONNECTED);
  String originalSSID = WiFi.SSID();
  
  // Disconnect from current network
  WiFi.disconnect();
  delay(100);
  
  // Try the new connection
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid.c_str(), password.c_str());
  
  // Wait for connection with timeout
  int attempts = 0;
  bool connectionSuccess = false;
  
  while (WiFi.status() != WL_CONNECTED && attempts < 15) { // ~7.5 second timeout
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi test successful!");
    Serial.println("IP: " + WiFi.localIP().toString());
    connectionSuccess = true;
  } else {
    Serial.println("\nWiFi test failed!");
    connectionSuccess = false;
  }
  
  // Restore original connection if needed
  if (wasConnected && originalSSID != ssid) {
    WiFi.disconnect();
    delay(100);
    WiFi.begin(wifiSSID.c_str(), wifiPassword.c_str());
    
    // Wait a bit for reconnection to the original network
    attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 10) {
      delay(500);
      attempts++;
    }
  }
  
  // Restore original mode if we changed it
  if (currentMode != WiFi.getMode()) {
    WiFi.mode(currentMode);
  }
  
  return connectionSuccess;
}


void setup() {
  // Start Serial for debugging
  Serial.begin(115200);
  delay(100); // Short delay to stabilize
  Serial.println("\n\nStarting PMD Health Device...");
  
  // Initialize button pins
  pinMode(CONFIG_BUTTON_PIN, INPUT_PULLUP);
  pinMode(SCREEN_TOGGLE_PIN, INPUT_PULLUP);
  // pinMode(DATA_CYCLE_PIN, INPUT_PULLUP);
  
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
  wifiSSID = preferences.getString("wifiSSID","");
  wifiPassword = preferences.getString("wifiPassword","");

  
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
    // Serial.println("Waiting for time sync");
    // time_t now = time(nullptr);
    // while (now < 8 * 3600 * 2) {
    //   delay(500);
    //   Serial.print(".");
    //   now = time(nullptr);
    // }
    // Serial.println("Time synchronized");

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
  Serial.println("=======================================\n");
  
  // Set initial display timeout
  displaySleepTime = millis() + DISPLAY_TIMEOUT;
}


void loop() {
  if (setupMode) {
    // Handle DNS and HTTP requests in setup mode
    dnsServer.processNextRequest();
    webServer.handleClient();
    
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
        fetchBPDataFromFirebase();
        lastFetchTime = millis();
      }
      
      // Check if WiFi connection is lost and try to reconnect
      if (WiFi.status() != WL_CONNECTED && millis() - lastUploadTime >= 600000) { // Try reconnecting every 10 minutes
        Serial.println("WiFi connection lost. Attempting to reconnect...");
        connectToWiFi();
      }
      
      // Check for display timeout
      if (displayOn && millis() > displaySleepTime) {
        displayOn = false;
        display.clearDisplay();
        display.display();
        Serial.println("Display turned off due to inactivity");
      }
    }
  }
  
  // Always check for serial commands
  checkSerialCommand();
  
  // Small delay to prevent watchdog issues
  delay(10);
}


void checkButtons() {
  // Check screen toggle button (pin 6)
  if (digitalRead(SCREEN_TOGGLE_PIN) == LOW && !screenTogglePressed) {
    screenTogglePressed = true;
    
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
    
    delay(50); // Debounce
  } else if (digitalRead(SCREEN_TOGGLE_PIN) == HIGH && screenTogglePressed) {
    screenTogglePressed = false;
    delay(50); // Debounce
  }
  
  // Check if setup mode needs to be triggered (pin 4)
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
  }
}


void displayMainScreen() {
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
  
  // Display time and date
  display.setTextSize(2);
  display.setCursor(20, 12);
  display.println(timeStr);
  
  display.setTextSize(1);
  display.setCursor(32, 30);
  display.println(dateStr);
  
  // Display steps and calories
  display.setCursor(0, 42);
  display.print("Steps: ");
  display.println(stepCount);
  
  display.setCursor(0, 54);
  display.print("Calories: ");
  display.print(caloriesBurned, 1);
  
  display.display();
}



void connectToWiFi() {
  Serial.println("Connecting to WiFi...");
  
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
      display.display();
      delay(500);
    }
    return;
  }
  
  if (displayOn) {
    display.clearDisplay();
    display.setCursor(0, 0);
    display.println("Connecting to WiFi");
    display.setCursor(0, 20);
    display.println(wifiSSID);
    display.display();
  }
  
  // Connect to WiFi
  WiFi.mode(WIFI_STA);
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
    
    if (displayOn) {
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
      delay(500);
    }
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
  
  // Print sensor data to serial at a lower frequency to save console output
  if (millis() % 10000 < 100) { // Print approximately every 10 seconds
    Serial.println("Sensor readings:");
    Serial.print("Steps: "); Serial.print(stepCount);
    Serial.print(" | Calories: "); Serial.print(caloriesBurned, 1);
    Serial.print(" | Distance: "); Serial.print(distanceInKm, 2); Serial.println(" km");
    Serial.print("Temperature: "); Serial.print(temperature); Serial.println(" C");
    Serial.print("Heart Rate: "); Serial.print(beatAvg); Serial.println(" BPM");
  }
}

void detectStep(float accelMagnitude) {
  unsigned long currentTime = millis();
  if (accelMagnitude > STEP_THRESHOLD && !stepDetected &&
      (currentTime - lastStepTime > STEP_COOLDOWN)) {
    stepCount++;
    lastStepTime = currentTime;
    stepDetected = true;
    
    // Reset display timeout on activity
    displaySleepTime = millis() + DISPLAY_TIMEOUT;
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
  
  display.setCursor(0, 0);
  display.println("Health Metrics");
  
  // Blood pressure from Firebase
  display.setCursor(0, 10);
  display.print("Systolic: ");
  display.print(systolicValue);
  display.println(" mmHg");
  
  display.setCursor(0, 20);
  display.print("Diastolic: ");
  display.print(diastolicValue);
  display.println(" mmHg");
  
  display.setCursor(0, 30);
  display.print("Pulse: ");
  display.print(remoteBPM);
  display.println(" BPM");
  
  // Local temperature and heart rate
  display.setCursor(0, 42);
  display.print("Temp: ");
  display.print(temperature);
  display.println(" C");
  
  display.setCursor(0, 54);
  display.print("Heart Rate: ");
  display.print(beatAvg);
  display.println(" BPM");
  
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
void fetchBPDataFromFirebase() {
  if (WiFi.status() != WL_CONNECTED || userId.isEmpty()) {
    Serial.println("Cannot fetch vital signs: WiFi not connected or user ID not set");
    return;
  }
  
  Serial.println("Fetching vital signs data from Firebase...");
  
  // Fetch vital_signs documents with ordering
  HTTPClient http;
  
  // Construct URL for Firestore query with proper ordering to get the most recent
  String url = "https://firestore.googleapis.com/v1/projects/";
  url += firestoreProjectId;
  url += "/databases/(default)/documents/vital_signs";
  url += "?pageSize=20"; // Limit to 20 documents for efficiency
  url += "&orderBy=timestamp%20desc"; // Order by timestamp descending (URL encoded)
  url += "&key=";
  url += firestoreAPIKey;
  
  http.begin(url);
  int httpCode = http.GET();
  
  if (httpCode == HTTP_CODE_OK) {
    String payload = http.getString();
    Serial.println("Vital signs data fetched successfully");
    
    // Parse the JSON response
    DynamicJsonDocument doc(8192); // Increased buffer size
    DeserializationError error = deserializeJson(doc, payload);
    
    if (!error) {
      // Check if we have documents
      if (doc.containsKey("documents") && doc["documents"].size() > 0) {
        Serial.println("Found " + String(doc["documents"].size()) + " documents");
        
        // Variables to keep track of the most recent document
        String latestTimestamp = "";
        bool foundMatchingUser = false;
        
        // Iterate through all documents to find the most recent one for our user
        for (JsonVariant documentVar : doc["documents"].as<JsonArray>()) {
          JsonObject document = documentVar.as<JsonObject>();
          
          // Check if this document belongs to our user
          if (document.containsKey("fields") && 
              document["fields"].containsKey("user_id") && 
              document["fields"]["user_id"].containsKey("stringValue")) {
            
            String docUserId = document["fields"]["user_id"]["stringValue"].as<String>();
            
            if (docUserId == userId) {
              foundMatchingUser = true;
              Serial.println("Found document for our user ID");
              
              // Get this document's timestamp
              if (document["fields"].containsKey("timestamp") && 
                  document["fields"]["timestamp"].containsKey("stringValue")) {
                String timestampStr = document["fields"]["timestamp"]["stringValue"].as<String>();
                
                // If this is the first matching document or it's newer than what we've seen
                if (latestTimestamp.isEmpty() || timestampStr > latestTimestamp) {
                  latestTimestamp = timestampStr;
                  
                  // Extract systolic value
                  if (document["fields"].containsKey("systolic_BP") && 
                      document["fields"]["systolic_BP"].containsKey("stringValue")) {
                    String systolicStr = document["fields"]["systolic_BP"]["stringValue"].as<String>();
                    if (systolicStr.length() > 0) {
                      systolicValue = systolicStr.toInt();
                      Serial.print("Systolic value updated: ");
                      Serial.println(systolicValue);
                    }
                  }
                  
                  // Extract diastolic value
                  if (document["fields"].containsKey("diastolic") && 
                      document["fields"]["diastolic"].containsKey("stringValue")) {
                    String diastolicStr = document["fields"]["diastolic"]["stringValue"].as<String>();
                    if (diastolicStr.length() > 0) {
                      diastolicValue = diastolicStr.toInt();
                      Serial.print("Diastolic value updated: ");
                      Serial.println(diastolicValue);
                    }
                  }
                  
                  // Extract pulse value
                  if (document["fields"].containsKey("pulse") && 
                      document["fields"]["pulse"].containsKey("stringValue")) {
                    String pulseStr = document["fields"]["pulse"]["stringValue"].as<String>();
                    if (pulseStr.length() > 0) {
                      remoteBPM = pulseStr.toInt();
                      Serial.print("Pulse value updated: ");
                      Serial.println(remoteBPM);
                    }
                  }
                  
                  // Extract date and time of measurement
                  if (document["fields"].containsKey("date") && 
                      document["fields"]["date"].containsKey("stringValue")) {
                    bpMeasurementDate = document["fields"]["date"]["stringValue"].as<String>();
                    Serial.print("Measurement date: ");
                    Serial.println(bpMeasurementDate);
                  }
                  
                  if (document["fields"].containsKey("time") && 
                      document["fields"]["time"].containsKey("stringValue")) {
                    bpMeasurementTime = document["fields"]["time"]["stringValue"].as<String>();
                    Serial.print("Measurement time: ");
                    Serial.println(bpMeasurementTime);
                  }
                  
                  Serial.println("Found latest data with timestamp: " + timestampStr);
                }
              }
            }
          }
        }
        
        if (foundMatchingUser && !latestTimestamp.isEmpty()) {
          Serial.println("Updated vital signs data from most recent entry");
        } else if (!foundMatchingUser) {
          Serial.println("No vital_signs documents found for user ID: " + userId);
        }
      } else {
        Serial.println("No vital_signs documents found in collection");
      }
    } else {
      Serial.print("JSON parsing error: ");
      Serial.println(error.c_str());
      
      // If orderBy fails, try without ordering as fallback
      fetchBPDataWithoutOrdering();
    }
  } else {
    Serial.print("Failed to fetch vital signs data. HTTP code: ");
    Serial.println(httpCode);
    
    // Try fallback method if original query fails
    fetchBPDataWithoutOrdering();
  }
  
  http.end();
  
  // Update last fetch time
  lastFetchTime = millis();
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
  
  // For vital signs - we'll only upload the most recent reading
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
    // Test the connection before saving
    display.clearDisplay();
    display.setCursor(0, 0);
    display.println("Testing WiFi...");
    display.setCursor(0, 20);
    display.println(newWifiSSID);
    display.display();
    
    wifiValid = testWiFiConnection(newWifiSSID, newWifiPassword);
    
    if (!wifiValid) {
      errorMessage += "<p>WiFi connection test failed. Please check your network name and password.</p>";
    }
  }
  
  // Validate user ID if provided
  bool userValid = true;
  if (!newUserId.isEmpty() && newUserId != userId) {
    display.clearDisplay();
    display.setCursor(0, 0);
    display.println("Verifying user...");
    display.setCursor(0, 20);
    display.println(maskString(newUserId));
    display.display();
    
    userValid = verifyUserID(newUserId);
    
    if (!userValid) {
      errorMessage += "<p>User ID verification failed. This ID does not exist in our system.</p>";
    }
  }
  
  // If validation failures, show error
  if (!wifiValid || !userValid) {
    String html = "<!DOCTYPE html><html><head><title>Configuration Error</title>";
    html += "<meta name='viewport' content='width=device-width, initial-scale=1'>";
    html += "<style>";
    html += "body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; color: #333; }";
    html += ".container { max-width: 500px; margin: 0 auto; background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1); }";
    html += "h1 { color: #e74c3c; text-align: center; }";
    html += "p { line-height: 1.5; }";
    html += ".error { background-color: #fdecea; border-left: 4px solid #e74c3c; padding: 12px; margin-bottom: 20px; }";
    html += "button { background-color: #3498db; color: white; border: none; padding: 12px 20px; border-radius: 4px; cursor: pointer; width: 100%; font-size: 16px; }";
    html += "button:hover { background-color: #2980b9; }";
    html += "</style></head>";
    html += "<body><div class='container'>";
    html += "<h1>Configuration Error</h1>";
    html += "<div class='error'>" + errorMessage + "</div>";
    html += "<p>Please go back and correct the information.</p>";
    html += "<button onclick='window.history.back()'>Go Back</button>";
    html += "</div></body></html>";
    
    webServer.send(400, "text/html", html);
    return;
  }
  
  // All validation passed, update configurations
  if (!newUserId.isEmpty() && newUserId != userId) {
    userId = newUserId;
    preferences.putString("userId", userId);
    configUpdated = true;
    message += "<li>User ID updated to: <strong>" + maskString(userId) + "</strong></li>";
  }
  
  if (!newWifiSSID.isEmpty() && newWifiSSID != wifiSSID) {
    wifiSSID = newWifiSSID;
    preferences.putString("wifiSSID", wifiSSID);
    configUpdated = true;
    message += "<li>WiFi network updated to: <strong>" + wifiSSID + "</strong></li>";
  }
  
  if (!newWifiPassword.isEmpty()) {
    wifiPassword = newWifiPassword;
    preferences.putString("wifiPassword", wifiPassword);
    configUpdated = true;
    message += "<li>WiFi password updated</li>";
  }
  
  message += "</ul>";
  
  if (configUpdated) {
    String html = "<!DOCTYPE html><html><head><title>Configuration Saved</title>";
    html += "<meta name='viewport' content='width=device-width, initial-scale=1'>";
    html += "<style>";
    html += "body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; color: #333; }";
    html += ".container { max-width: 500px; margin: 0 auto; background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1); text-align: center; }";
    html += "h1 { color: #4CAF50; }";
    html += "p { line-height: 1.5; margin-bottom: 15px; }";
    html += ".success { background-color: #e8f5e9; border-left: 4px solid #4CAF50; padding: 12px; margin: 20px 0; text-align: left; }";
    html += "ul { text-align: left; }";
    html += "button { background-color: #2196F3; color: white; border: none; padding: 12px 20px; border-radius: 4px; cursor: pointer; font-size: 16px; }";
    html += "button:hover { background-color: #0b7dda; }";
    html += "</style></head>";
    html += "<body><div class='container'>";
    html += "<h1>Configuration Saved!</h1>";
    html += "<div class='success'>";
    html += message;
    html += "</div>";
    html += "<p>The device will automatically exit setup mode in 2 minutes, or you can restart it now.</p>";
    html += "<p>You can close this page.</p>";
    html += "</div></body></html>";
    
    webServer.send(200, "text/html", html);
    
    // Show success on display
    display.clearDisplay();
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
    
    Serial.println("Configuration updated:");
    if (!userId.isEmpty()) Serial.println("User ID: (ID set - masked for security)");
    if (!wifiSSID.isEmpty()) Serial.println("WiFi SSID: " + wifiSSID);
    if (!wifiPassword.isEmpty()) Serial.println("WiFi password was updated");
  } else {
    webServer.send(400, "text/html", "<html><body><h1>Error</h1><p>No configuration changes were made</p><p><a href='/'>Go back</a></p></body></html>");
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
      

    } else if (input.startsWith("WIFI:")) {
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
    } else if (input == "STATUS") {
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
    } else if (input == "RESET") {
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
    } else if (input == "HELP") {
      // Print help information
      Serial.println("\n=== PMD Health Device Commands ===");
      Serial.println("USERID:[value]       - Set the user ID");
      Serial.println("WIFI:SSID,PASSWORD   - Set WiFi credentials");
      Serial.println("STATUS               - Show current device status");
      Serial.println("RESET                - Reset all settings and enter setup mode");
      Serial.println("HELP                 - Show this help information");
      Serial.println("================================\n");
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
