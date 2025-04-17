const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const { OpenAI } = require("openai");
const functions = require("firebase-functions");

admin.initializeApp();

exports.generatePreeclampsiaInsight = onDocumentCreated("{collectionId}/{docId}", async (event) => {
  try {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data associated with the event");
      return;
    }
    
    const data = snapshot.data();
    const collectionId = event.params.collectionId;
    console.log(`Received data from ${collectionId} collection:`, JSON.stringify(data));
    
    // Only process specific collections
    const validCollections = ["activity", "vital_signs", "weight", "day"];
    if (!validCollections.includes(collectionId)) {
      console.log(`Ignoring document from ${collectionId} collection`);
      return;
    }
    
    const userId = data.user_id || "unknown";
    
    // Fetch additional user data for context
    let userData = {};
    try {
      const userDoc = await admin.firestore().collection("user").doc(userId).get();
      if (userDoc.exists) {
        userData = userDoc.data();
      }
    } catch (error) {
      console.log("Error fetching user data:", error);
    }
    
    // Prepare prompt based on collection type and available data
    let promptContent = `You are monitoring a pregnant patient who is being tracked for preeclampsia risk. `;
    
    // Add collection-specific data when available
    if (collectionId === "activity") {
      promptContent += `The patient has logged physical activity: `;
      if (data.steps !== undefined) promptContent += `\n- Steps: ${data.steps}`;
      if (data.calories !== undefined) promptContent += `\n- Calories: ${data.calories}`;
    } 
    else if (collectionId === "vital_signs") {
      promptContent += `The patient has logged vital signs: `;
      if (data.systolic !== undefined) promptContent += `\n- Systolic Blood Pressure: ${data.systolic} mmHg`;
      if (data.diastolic !== undefined) promptContent += `\n- Diastolic Blood Pressure: ${data.diastolic} mmHg`;
      if (data.pulse !== undefined) promptContent += `\n- Pulse: ${data.pulse} bpm`;
    } 
    else if (collectionId === "weight") {
      promptContent += `The patient has logged a new weight measurement: `;
      if (data.weight !== undefined) promptContent += `\n- Weight: ${data.weight} kg`;
    } 
    else if (collectionId === "day") {
      promptContent += `The patient has logged daily information: `;
      if (data.symptoms && data.symptoms.length > 0) promptContent += `\n- Symptoms: ${data.symptoms.join(", ")}`;
      if (data.food_consumed && data.food_consumed.length > 0) promptContent += `\n- Food consumed: ${data.food_consumed.join(", ")}`;
    }
    
    // Add user context if available
    if (userData.gravida !== undefined || userData.parity !== undefined) {
      promptContent += `\n\nPatient pregnancy history:`;
      if (userData.gravida !== undefined) promptContent += `\n- Gravida (number of pregnancies): ${userData.gravida}`;
      if (userData.parity !== undefined) promptContent += `\n- Parity (number of births): ${userData.parity}`;
    }
    
    if (userData.pre_existing_conditions) {
      promptContent += `\n\nPre-existing conditions: ${userData.pre_existing_conditions}`;
    }
    
    promptContent += `\n\nBased on this information, provide a personalized health insight focusing on preeclampsia monitoring and management. Address the most relevant factors for preeclampsia from the available data (blood pressure, sudden weight gain, symptoms like headaches, vision changes, upper abdominal pain, etc.). Your response should be supportive and educational but not alarming. If the data suggests potential concern, gently encourage the patient to discuss with their healthcare provider. Keep your response under 120 words and avoid clinical diagnosis or treatment advice.`;
    
    // Generate insight using OpenAI or fallback
    let generatedInsight = "";
    let source = "fallback";
    
    // Try to get OpenAI API key
    let openaiApiKey;
    try {
      openaiApiKey = functions.config().openai?.key;
      console.log("API key retrieved:", openaiApiKey ? "Yes" : "No");
    } catch (e) {
      console.log("Error getting OpenAI API key from config");
    }
    
    if (openaiApiKey) {
      try {
        console.log("Initializing OpenAI client");
        const openai = new OpenAI({
          apiKey: openaiApiKey
        });
        
        console.log("Sending prompt to OpenAI");
        const completion = await openai.chat.completions.create({
          model: "gpt-4o-mini",
          messages: [
            {
              role: "system",
              content: "You are a supportive health assistant specializing in preeclampsia monitoring during pregnancy. Provide encouraging, evidence-based insights without giving clinical diagnosis."
            },
            {
              role: "user",
              content: promptContent
            }
          ],
          max_tokens: 200
        });
        
        generatedInsight = completion.choices[0].message.content;
        source = "openai";
        console.log("OpenAI responded successfully");
      } catch (error) {
        console.error("Error using OpenAI:", error);
        generatedInsight = generatePreeclampsiaFallbackInsight(collectionId, data);
      }
    } else {
      console.log("No OpenAI API key found, using fallback");
      generatedInsight = generatePreeclampsiaFallbackInsight(collectionId, data);
    }
    
    console.log("Writing to Firestore -> Insites collection");
    await admin.firestore()
      .collection("Insites")
      .add({
        user_id: userId,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        generatedInsight: generatedInsight,
        sourceCollection: collectionId,
        sourceData: data,
        source: source
      });
    
    console.log("Successfully saved to Insites collection");
    return null;
  } catch (error) {
    console.error("Error in function:", error);
    return null;
  }
});

// Function to generate preeclampsia-focused fallback insights
function generatePreeclampsiaFallbackInsight(collectionId, data) {
  switch (collectionId) {
    case "activity":
      const activityInsights = [
        "Moderate physical activity can be beneficial during pregnancy, but listen to your body. If you experience headaches, dizziness, or unusual fatigue after exercise, take it as a sign to rest and mention it to your healthcare provider.",
        "Regular, gentle movement helps maintain healthy circulation, which is important for preeclampsia monitoring. Remember to stay hydrated and avoid overexertion.",
        "Tracking your daily activity helps create a complete picture of your health. For preeclampsia monitoring, balancing activity with adequate rest is important. Pay attention to how you feel during and after exercise."
      ];
      return activityInsights[Math.floor(Math.random() * activityInsights.length)];
      
    case "vital_signs":
      let bpMessage = "";
      if (data.systolic !== undefined && data.diastolic !== undefined) {
        // Add more specific insight if BP is elevated (but don't diagnose)
        if (data.systolic >= 140 || data.diastolic >= 90) {
          bpMessage = "Your blood pressure reading is worth discussing with your healthcare provider at your next appointment.";
        } else {
          bpMessage = "Your blood pressure reading appears within the range typically monitored during pregnancy.";
        }
      }
      
      const vitalInsights = [
        `Regular blood pressure monitoring is a crucial part of preeclampsia management. ${bpMessage} Continue tracking consistently and report any sudden changes to your healthcare team.`,
        `Thank you for tracking your vital signs. ${bpMessage} Remember that preeclampsia monitoring includes watching for symptoms like headaches, vision changes, or upper abdominal pain along with blood pressure readings.`,
        `Consistent vital sign tracking is excellent for preeclampsia monitoring. ${bpMessage} Stay aware of how you're feeling overall and report any concerning symptoms promptly.`
      ];
      return vitalInsights[Math.floor(Math.random() * vitalInsights.length)];
      
    case "weight":
      let weightMessage = "";
      if (data.weight !== undefined) {
        weightMessage = "Tracking your weight regularly helps monitor for sudden changes, which can be relevant for preeclampsia management.";
      }
      
      const weightInsights = [
        `${weightMessage} A sudden increase in weight (especially with swelling) is something to mention to your healthcare provider, as it can be related to fluid retention.`,
        `${weightMessage} In preeclampsia monitoring, both the pattern and rate of weight gain can provide useful information for your healthcare team.`,
        `${weightMessage} While some weight gain is normal during pregnancy, sudden changes (especially with swelling in the face or hands) should be discussed with your healthcare provider.`
      ];
      return weightInsights[Math.floor(Math.random() * weightInsights.length)];
      
    case "day":
      let symptomMessage = "";
      const preeclampsiaSymptoms = ["headache", "vision", "blur", "light", "abdominal pain", "nausea", "shortness of breath", "swelling"];
      
      if (data.symptoms && data.symptoms.length > 0) {
        const reportedSymptoms = data.symptoms.join(" ").toLowerCase();
        const hasPreeclampsiaSymptoms = preeclampsiaSymptoms.some(symptom => 
          reportedSymptoms.includes(symptom)
        );
        
        if (hasPreeclampsiaSymptoms) {
          symptomMessage = "Some of the symptoms you've reported are worth discussing with your healthcare provider as they monitor you for preeclampsia.";
        } else {
          symptomMessage = "Tracking all symptoms, even those that seem minor, helps build a complete picture for preeclampsia monitoring.";
        }
      }
      
      const dayInsights = [
        `${symptomMessage} Remember that preeclampsia-related symptoms can include persistent headaches, vision changes, upper abdominal pain, and sudden swelling of the face or hands.`,
        `${symptomMessage} Daily tracking helps identify patterns that might be relevant to preeclampsia monitoring. Continue to note any changes in how you feel.`,
        `${symptomMessage} Paying attention to your daily symptoms is an important part of preeclampsia management. Your attentiveness to your body's signals is valuable.`
      ];
      return dayInsights[Math.floor(Math.random() * dayInsights.length)];
      
    default:
      return "Tracking your health information is an essential part of preeclampsia monitoring. Regular recording of symptoms, vital signs, and physical changes helps you and your healthcare team manage your pregnancy more effectively.";
  }
}