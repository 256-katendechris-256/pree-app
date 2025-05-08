const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const { OpenAI } = require("openai");
const functions = require("firebase-functions");
const crypto = require('crypto');

admin.initializeApp();

// Clinical thresholds based on medical guidelines
const CLINICAL_THRESHOLDS = {
  bloodPressure: {
    systolicConcern: 140,
    diastolicConcern: 90,
    systolicEmergency: 160,
    diastolicEmergency: 110
  },
  weight: {
    rapidGainPerWeek: 2 // kg
  },
  pulse: {
    tachycardia: 100,
    bradycardia: 60
  }
};

// Preeclampsia warning symptoms 
const PREECLAMPSIA_SYMPTOMS = [
  "headache", "severe headache", "persistent headache", 
  "vision", "blurry vision", "vision changes", "blur", "light sensitivity",
  "abdominal pain", "upper abdominal pain", "right upper quadrant pain",
  "nausea", "vomiting",
  "shortness of breath", "difficulty breathing",
  "swelling", "face swelling", "hand swelling", "sudden swelling",
  "edema"
];

/**
 * Privacy-focused Firebase Cloud Function that generates preeclampsia insights
 * when new health data is added without exposing PHI to external APIs
 */
exports.generatePreeclampsiaInsight = onDocumentCreated("{collectionId}/{docId}", async (event) => {
  try {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data associated with the event");
      return;
    }
   
    const data = snapshot.data();
    const collectionId = event.params.collectionId;
    console.log(`Received data from ${collectionId} collection`);
   
    // Only process specific collections
    const validCollections = ["activity", "vital_signs", "weight", "symptoms", "temperature", "consumption"];
    if (!validCollections.includes(collectionId)) {
      console.log(`Ignoring document from ${collectionId} collection`);
      return;
    }
   
    const userId = data.user_id || "unknown";
   
    // SECURITY IMPROVEMENT 1: Use fallback insights by default, avoid sending PHI to OpenAI
    // Only use the AI-generated insights if explicitly configured to do so
    let useAI = false;
    try {
      useAI = functions.config().insights?.use_ai === 'true';
      console.log("AI integration enabled:", useAI);
    } catch (e) {
      console.log("Error getting AI configuration, defaulting to fallback insights");
    }
    
    let generatedInsight = "";
    let source = "fallback";
    
    if (useAI) {
      // SECURITY IMPROVEMENT 2: Use anonymized data for OpenAI
      const { anonymizedPrompt, mappings } = anonymizeHealthData(collectionId, data, userId);
      
      // Log that we're using anonymized data (do not log the mappings)
      console.log("Using anonymized data for AI processing");
      
      // Only try to use OpenAI if we have anonymized data properly
      if (anonymizedPrompt) {
        generatedInsight = await tryGenerateAIInsight(anonymizedPrompt, mappings);
        if (generatedInsight) {
          source = "openai";
        } else {
          // Fallback if AI generation fails
          generatedInsight = generateClinicalFallbackInsight(collectionId, data);
        }
      } else {
        console.log("Could not properly anonymize data, using fallback");
        generatedInsight = generateClinicalFallbackInsight(collectionId, data);
      }
    } else {
      // Use non-AI fallback
      console.log("Using non-AI fallback insights");
      generatedInsight = generateClinicalFallbackInsight(collectionId, data);
    }

    // Generate dietary insight if appropriate
    let dietaryInsight = null;
    if (shouldGenerateDietaryRecommendation(collectionId, data)) {
      dietaryInsight = generateDietaryRecommendation(collectionId, data);
    }
   
    // SECURITY IMPROVEMENT 3: Store minimal necessary data
    const sanitizedSourceData = sanitizeSourceData(data);
    
    console.log("Writing to Firestore -> Insites collection");
    await admin.firestore()
      .collection("Insites")
      .add({
        user_id: userId,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        generatedInsight: generatedInsight,
        sourceCollection: collectionId,
        sourceData: sanitizedSourceData, // Only store sanitized data
        source: source,
        type: "clinical"
      });
   
    // Store dietary insight if generated
    if (dietaryInsight) {
      await admin.firestore()
        .collection("DietaryInsights")
        .add({
          user_id: userId,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          generatedInsight: dietaryInsight,
          sourceCollection: collectionId,
          sourceData: sanitizedSourceData, // Only store sanitized data
          source: "algorithm",
          type: "dietary"
        });
      console.log("Successfully saved dietary insight to DietaryInsights collection");
    }
   
    console.log("Successfully saved to Insites collection");
    return null;
  } catch (error) {
    console.error("Error in function:", error);
    return null;
  }
});

/**
 * Anonymize health data to protect PHI before sending to external APIs
 */
function anonymizeHealthData(collectionId, data, userId) {
  try {
    // Create a deep copy of the data to avoid modifying the original
    const dataCopy = JSON.parse(JSON.stringify(data));
    
    // Remove direct identifiers completely
    delete dataCopy.user_id;
    delete dataCopy.patient_name;
    delete dataCopy.patient_id;
    delete dataCopy.email;
    delete dataCopy.phone;
    delete dataCopy.address;
    delete dataCopy.date_of_birth;
    
    // Create a map to store the original values that we'll replace with tokens
    const mappings = {};
    
    // Build prompt content with anonymized data
    let promptContent = `You are monitoring a pregnant patient (ID: PATIENT_TOKEN) who is being tracked for preeclampsia risk. `;
    
    // Add collection-specific data with anonymization
    if (collectionId === "activity") {
      promptContent += `The patient has logged physical activity: `;
      if (dataCopy.steps !== undefined) promptContent += `\n- Steps: ${dataCopy.steps}`;
      if (dataCopy.calories !== undefined) promptContent += `\n- Calories: ${dataCopy.calories}`;
      if (dataCopy.distance !== undefined) promptContent += `\n- Distance: ${dataCopy.distance}`;
      if (dataCopy.active_minutes !== undefined) promptContent += `\n- Active minutes: ${dataCopy.active_minutes}`;
    }
    else if (collectionId === "vital_signs") {
      promptContent += `The patient has logged vital signs: `;
      if (dataCopy.systolic !== undefined) promptContent += `\n- Systolic Blood Pressure: ${dataCopy.systolic} mmHg`;
      if (dataCopy.diastolic !== undefined) promptContent += `\n- Diastolic Blood Pressure: ${dataCopy.diastolic} mmHg`;
      if (dataCopy.pulse !== undefined) promptContent += `\n- Pulse: ${dataCopy.pulse} bpm`;
    }
    else if (collectionId === "weight") {
      promptContent += `The patient has logged a new weight measurement: `;
      if (dataCopy.current !== undefined) promptContent += `\n- Weight: ${dataCopy.current} kg`;
      if (dataCopy.change !== undefined) promptContent += `\n- Weight change: ${dataCopy.change} kg`;
      if (dataCopy.bmi !== undefined) promptContent += `\n- BMI: ${dataCopy.bmi}`;
      if (dataCopy.status !== undefined) promptContent += `\n- Status: ${dataCopy.status}`;
    }
    else if (collectionId === "symptoms") {
      promptContent += `The patient has logged symptoms: `;
      if (dataCopy.symptom) {
        // Symptoms could potentially contain identifiable information
        const symptomToken = `SYMPTOM_${generateToken()}`;
        mappings[symptomToken] = dataCopy.symptom;
        promptContent += `\n- Symptom: ${symptomToken}`;
      }
      // Don't include symptom details as they could contain sensitive info
    }
    else if (collectionId === "temperature") {
      promptContent += `The patient has logged temperature information: `;
      if (dataCopy.temperature !== undefined) promptContent += `\n- Temperature: ${dataCopy.temperature}°C`;
    }
    else if (collectionId === "consumption") {
      promptContent += `The patient has logged dietary information: `;
      if (dataCopy.stuff_consumed) {
        // Food consumption could potentially contain identifiable information
        const foodToken = `FOOD_${generateToken()}`;
        mappings[foodToken] = dataCopy.stuff_consumed;
        promptContent += `\n- Food/drink consumed: ${foodToken}`;
      }
    }
    
    // Add generic medical history information without specifics
    promptContent += `\n\nPatient has relevant pregnancy history and may have pre-existing conditions.`;
    
    // Add system prompt for clinical response style
    promptContent += `\n\nBased on this data, provide a clinical assessment focusing strictly on preeclampsia monitoring. Format your response like a medical status report:
    1. Start with a clear STATUS indicator (e.g., "BP STATUS: ELEVATED")
    2. Include specific measurements where relevant
    3. Avoid pleasantries, supportive language, or unnecessary words
    4. Provide clear, direct action items if needed
    5. Use medical terminology appropriate for clinical documentation
    6. Maximum 50 words, direct and professional tone
    
Example format:
"BP STATUS: ELEVATED (142/88). Monitor for headache, visual disturbances. Recheck in 4 hours. Report readings >150/95 immediately. Increase rest periods."`;
    
    return { anonymizedPrompt: promptContent, mappings };
  } catch (error) {
    console.error("Error anonymizing health data:", error);
    return { anonymizedPrompt: null, mappings: {} };
  }
}

/**
 * Generate a random token for anonymization
 */
function generateToken() {
  return crypto.randomBytes(4).toString('hex');
}

/**
 * Try to generate AI insight with safety measures
 */
async function tryGenerateAIInsight(anonymizedPrompt, mappings) {
  try {
    let openaiApiKey;
    try {
      openaiApiKey = functions.config().openai?.key;
      if (!openaiApiKey) {
        console.log("No OpenAI API key found");
        return null;
      }
    } catch (e) {
      console.log("Error getting OpenAI API key from config");
      return null;
    }
    
    console.log("Initializing OpenAI client");
    const openai = new OpenAI({
      apiKey: openaiApiKey
    });
    
    console.log("Sending anonymized prompt to OpenAI");
    const completion = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        {
          role: "system",
          content: "You are a clinical decision support system focused on preeclampsia monitoring. Provide direct, concise insights in a clinical format. Use language similar to medical reports: status-focused, data-driven, and objective. Avoid pleasantries and conversational language. Start with a clear status indicator (e.g., 'BP STATUS: ELEVATED'). Keep under 50 words."
        },
        {
          role: "user",
          content: anonymizedPrompt
        }
      ],
      max_tokens: 200
    });
    
    let generatedInsight = completion.choices[0].message.content;
    console.log("OpenAI responded successfully");
    
    // De-tokenize the response: replace tokens with original values
    Object.keys(mappings).forEach(token => {
      generatedInsight = generatedInsight.replace(new RegExp(token, 'g'), mappings[token]);
    });
    
    // Also replace the generic patient token
    generatedInsight = generatedInsight.replace(/PATIENT_TOKEN/g, "");
    
    return generatedInsight;
  } catch (error) {
    console.error("Error generating AI insight:", error);
    return null;
  }
}

/**
 * Sanitize source data to minimize sensitive information storage
 */
function sanitizeSourceData(data) {
  // Create a deep copy to avoid modifying the original
  const sanitized = JSON.parse(JSON.stringify(data));
  
  // Remove any potentially sensitive or redundant fields
  delete sanitized.raw_device_data;
  delete sanitized.location;
  delete sanitized.device_id;
  delete sanitized.patient_name;
  delete sanitized.email;
  delete sanitized.phone;
  delete sanitized.address;
  delete sanitized.date_of_birth;
  delete sanitized.insurance_info;
  delete sanitized.family_history;
  delete sanitized.notes; // Free text fields often contain PHI
  
  // For symptom details, keep only the essential information
  if (sanitized.symptom_details && typeof sanitized.symptom_details === 'string') {
    // Only keep short symptom descriptions, truncate long ones
    if (sanitized.symptom_details.length > 100) {
      sanitized.symptom_details = sanitized.symptom_details.substring(0, 100) + "...";
    }
  }
  
  return sanitized;
}

// Function to generate clinical fallback insights
function generateClinicalFallbackInsight(collectionId, data) {
  switch (collectionId) {
    case "activity":
      return generateActivityClinicalInsight(data);
    case "vital_signs":
      return generateVitalSignsClinicalInsight(data);
    case "weight":
      return generateWeightClinicalInsight(data);
    case "symptoms":
      return generateSymptomsClinicalInsight(data);
    case "temperature":
      return generateTemperatureClinicalInsight(data);
    case "consumption":
      return generateConsumptionClinicalInsight(data);
    default:
      return "STATUS: MONITORING. Continue recording health data for preeclampsia surveillance. No specific clinical recommendations based on current data.";
  }
}

function generateActivityClinicalInsight(data) {
  if (!data.steps) {
    return "ACTIVITY STATUS: INCOMPLETE DATA. Continue monitoring activity patterns. Report unusual fatigue, shortness of breath, or decreased exercise tolerance.";
  }
  
  if (data.steps >= 10000) {
    return "ACTIVITY STATUS: HIGH INTENSITY. Consider moderate reduction in activity level. Monitor for exercise-induced symptoms. Report headache, visual disturbances, or unusual fatigue post-exercise.";
  } else if (data.steps >= 5000) {
    return "ACTIVITY STATUS: MODERATE. Current level appropriate for preeclampsia monitoring. Maintain hydration. Report any exercise-induced symptoms promptly.";
  } else {
    return "ACTIVITY STATUS: LOW INTENSITY. Current level appropriate. Gentle, consistent activity supports circulation. Report any new symptoms promptly. Avoid long periods of inactivity.";
  }
}

function generateVitalSignsClinicalInsight(data) {
  if (data.systolic === undefined || data.diastolic === undefined) {
    return "BP STATUS: INCOMPLETE DATA. Continue regular monitoring. Report readings >140/90 immediately. Monitor for headache, visual changes, epigastric pain.";
  }
  
  const { systolicConcern, diastolicConcern, systolicEmergency, diastolicEmergency } = CLINICAL_THRESHOLDS.bloodPressure;
  
  if (data.systolic >= systolicEmergency || data.diastolic >= diastolicEmergency) {
    return `BP STATUS: SEVERE ELEVATION (${data.systolic}/${data.diastolic}). URGENT MEDICAL EVALUATION REQUIRED. Position in left lateral recumbent. Proceed to medical facility immediately.`;
  } else if (data.systolic >= systolicConcern || data.diastolic >= diastolicConcern) {
    return `BP STATUS: ELEVATED (${data.systolic}/${data.diastolic}). Contact provider within 24 hours. Rest in left lateral position for 1 hour and recheck. Monitor for headache, visual changes, RUQ pain.`;
  } else {
    return `BP STATUS: NORMAL RANGE (${data.systolic}/${data.diastolic}). Continue regular monitoring. Report any sudden increases or new symptoms of headache, visual changes, or epigastric pain.`;
  }
}

function generateWeightClinicalInsight(data) {
  const weightValue = data.weight !== undefined ? data.weight : data.current;
  const weightChange = data.change;
  
  if (weightValue === undefined && weightChange === undefined) {
    return "WEIGHT STATUS: INCOMPLETE DATA. Continue regular weight monitoring. Report rapid gain (>2kg/week) immediately. Assess for concurrent edema.";
  }
  
  if (weightChange !== undefined && weightChange > CLINICAL_THRESHOLDS.weight.rapidGainPerWeek) {
    return `WEIGHT STATUS: RAPID GAIN (${weightChange}kg). Assess for edema. Evaluate for other preeclampsia signs. Report to provider within 24h. Not indicative of need for caloric restriction.`;
  } else if (weightChange !== undefined) {
    return `WEIGHT STATUS: STABLE (${weightChange}kg change). Continue monitoring. Report sudden increases >2kg/week, particularly with edema. Maintain balanced nutritional intake.`;
  } else {
    return `WEIGHT STATUS: BASELINE RECORDED (${weightValue}kg). Monitor for rapid changes >2kg/week, which may indicate fluid retention. Report sudden changes with concurrent symptoms.`;
  }
}

function generateSymptomsClinicalInsight(data) {
  if (!data.symptom) {
    return "SYMPTOM STATUS: NONE REPORTED. Continue vigilance for preeclampsia-specific symptoms. Monitor for headache, visual changes, RUQ pain, and edema.";
  }
  
  const symptomLower = data.symptom.toLowerCase();
  const isPotentialPreeclampsiaSymptom = PREECLAMPSIA_SYMPTOMS.some(s => 
    symptomLower.includes(s)
  );
  
  if (isPotentialPreeclampsiaSymptom) {
    return `SYMPTOM STATUS: PREECLAMPSIA INDICATOR PRESENT. Reported ${data.symptom}. Immediate BP assessment required. Contact healthcare provider. Assess for additional symptoms and edema.`;
  } else {
    return `SYMPTOM STATUS: NON-SPECIFIC FINDING. Reported ${data.symptom}. Continue monitoring for preeclampsia-specific symptoms: headache, visual changes, RUQ pain, sudden edema.`;
  }
}

function generateTemperatureClinicalInsight(data) {
  if (data.temperature === undefined) {
    return "TEMPERATURE STATUS: INCOMPLETE DATA. Continue monitoring. Report fever >38°C immediately, as it may indicate infection which can complicate preeclampsia management.";
  }
  
  if (data.temperature >= 38.0) {
    return `TEMPERATURE STATUS: ELEVATED (${data.temperature}°C). Potential infection. Contact provider promptly. Infection may exacerbate preeclampsia. Increase fluid intake. Monitor BP closely.`;
  } else if (data.temperature <= 36.0) {
    return `TEMPERATURE STATUS: BELOW NORMAL (${data.temperature}°C). Continue monitoring. Report if accompanied by other symptoms. Maintain adequate warming.`;
  } else {
    return `TEMPERATURE STATUS: NORMAL RANGE (${data.temperature}°C). Continue routine monitoring. Report significant changes or development of fever promptly.`;
  }
}

function generateConsumptionClinicalInsight(data) {
  if (!data.stuff_consumed) {
    return "DIETARY STATUS: INCOMPLETE DATA. Maintain balanced diet rich in fruits, vegetables, lean protein. No sodium restriction required based on current evidence. Report unusual cravings or aversions.";
  }
  
  return "DIETARY STATUS: INTAKE RECORDED. Maintain balanced nutritional profile. Focus on nutrient-dense foods. Adequate protein and hydration important. No specific restrictions recommended for preeclampsia prevention.";
}

// Determine if dietary recommendation should be generated
function shouldGenerateDietaryRecommendation(collectionId, data) {
  // For vital signs, check BP values
  if (collectionId === "vital_signs" && data.systolic !== undefined && data.diastolic !== undefined) {
    if (data.systolic >= CLINICAL_THRESHOLDS.bloodPressure.systolicConcern || 
        data.diastolic >= CLINICAL_THRESHOLDS.bloodPressure.diastolicConcern) {
      return true;
    }
  }
  
  // For weight, check for significant changes
  if (collectionId === "weight" && data.change !== undefined && Math.abs(data.change) > 1) {
    return true;
  }
  
  // For symptoms, check for relevant symptoms
  if (collectionId === "symptoms" && data.symptom) {
    const symptomLower = data.symptom.toLowerCase();
    const relevantSymptoms = ["swelling", "edema", "headache", "nausea"];
    if (relevantSymptoms.some(symptom => symptomLower.includes(symptom))) {
      return true;
    }
  }
  
  // Always generate for consumption entries
  if (collectionId === "consumption" && data.stuff_consumed) {
    return true;
  }
  
  return false;
}

// Generate evidence-based dietary recommendations
function generateDietaryRecommendation(collectionId, data) {
  // For elevated BP
  if (collectionId === "vital_signs" && data.systolic !== undefined && data.diastolic !== undefined) {
    const { systolicConcern, diastolicConcern } = CLINICAL_THRESHOLDS.bloodPressure;
    
    if (data.systolic >= systolicConcern || data.diastolic >= diastolicConcern) {
      return "DIETARY RECOMMENDATION: PREECLAMPSIA RISK PATTERN. Focus on DASH diet pattern: fruits, vegetables, whole grains, lean protein. Adequate calcium intake (1000-1300mg/day). Current evidence does not support sodium restriction. Report continued BP elevation.";
    }
  }
  
  // For rapid weight gain
  if (collectionId === "weight" && data.change !== undefined) {
    if (data.change > 2) {
      return "DIETARY RECOMMENDATION: RAPID WEIGHT GAIN PATTERN. Focus on nutrient-dense foods. High-quality protein at each meal (1.1g/kg/day). Include potassium-rich foods. Ensure adequate calcium (1000-1300mg/day). Report continued rapid weight gain.";
    }
  }
  
  // For specific symptoms
  if (collectionId === "symptoms" && data.symptom) {
    const symptomLower = data.symptom.toLowerCase();
    
    if (symptomLower.includes("headache")) {
      return "DIETARY RECOMMENDATION: HEADACHE MANAGEMENT. Ensure regular meal timing to prevent hypoglycemia. Maintain adequate hydration (2-3L/day). Include magnesium-rich foods (nuts, seeds, leafy greens). Consider vitamin D status. Avoid meal skipping.";
    }
    
    if (symptomLower.includes("swelling") || symptomLower.includes("edema")) {
      return "DIETARY RECOMMENDATION: EDEMA MANAGEMENT. Evidence does not support salt restriction. Focus on adequate protein (1.1g/kg/day). Include potassium-rich foods. Maintain hydration with water rather than sugar-sweetened beverages. Report if edema worsens.";
    }
  }
  
  // For consumption entries
  if (collectionId === "consumption") {
    return "DIETARY RECOMMENDATION: PREECLAMPSIA PREVENTION. Emphasize DASH dietary pattern: fruits, vegetables, whole grains, lean protein. Include calcium-rich foods (1000-1300mg/day). Adequate protein (1.1g/kg/day). No need for sodium restriction based on current evidence.";
  }
  
  // Default recommendation
  return "DIETARY RECOMMENDATION: GENERAL PREECLAMPSIA SUPPORT. Maintain balanced diet with adequate protein (1.1g/kg/day). Include calcium-rich foods. Focus on fruits, vegetables, whole grains, and lean protein. Current evidence does not support sodium restriction.";
}