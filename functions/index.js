const functions = require("firebase-functions/v2"); // Use v2 base import if needed elsewhere
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions/v2"); // Import logger for v2
const admin = require("firebase-admin");
const OpenAI = require("openai");

admin.initializeApp();
const db = admin.firestore();

const validCollections = ["activity", "vital_signs", "weight", "day"];
const fieldLabels = {
  activity: { steps: "Steps", calories: "Calories" },
  vital_signs: {
    systolic: "Systolic Blood Pressure (mmHg)",
    diastolic: "Diastolic Blood Pressure (mmHg)",
    pulse: "Pulse (bpm)"
  },
  weight: { weight: "Weight (kg)" },
  day: {
    symptoms: "Symptoms",
    food_consumed: "Food consumed"
  }
};

function buildPrompt(data, collectionId, userData) {
  let sections = [`You are monitoring a pregnant patient for preeclampsia risk.`];

  const labels = fieldLabels[collectionId];
  if (labels) {
    sections.push(`The patient has logged ${collectionId.replace("_", " ")}:`);
    for (const key in labels) {
      const value = data[key];
      if (value !== undefined && value !== null && value.length !== 0) {
        const formatted = Array.isArray(value) ? value.join(", ") : value;
        sections.push(`- ${labels[key]}: ${formatted}`);
      }
    }
  }

  // Pregnancy history
  if (userData.gravida !== undefined || userData.parity !== undefined) {
    sections.push(`
Patient pregnancy history:`); // Corrected newline
    if (userData.gravida !== undefined) sections.push(`- Gravida: ${userData.gravida}`);
    if (userData.parity !== undefined) sections.push(`- Parity: ${userData.parity}`);
  }

  if (userData.pre_existing_conditions) {
    sections.push(`
Pre-existing conditions: ${userData.pre_existing_conditions}`); // Corrected newline
  }

  sections.push(
    `

Based on this information, provide a personalized health insight focusing on preeclampsia monitoring and management.`, // Corrected newline
    `Address relevant factors (blood pressure, sudden weight gain, symptoms like headaches, vision changes, abdominal pain, etc.).`,
    `Be supportive and educational, not alarming. Keep under 120 words. Avoid clinical diagnosis or treatment advice.`
  );

  return sections.join(""); // Corrected newline join separator
}

async function getInsightFromOpenAI(promptContent, apiKey) {
  try {
    const openai = new OpenAI({ apiKey });
    const response = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        {
          role: "system",
          content:
            "You are a supportive health assistant specializing in preeclampsia monitoring during pregnancy. Provide encouraging, evidence-based insights without giving clinical diagnosis."
        },
        { role: "user", content: promptContent }
      ],
      max_tokens: 200
    });

    return { content: response.choices[0].message.content, source: "openai" };
  } catch (error) {
    logger.error("OpenAI API error:", error); // Use v2 logger
    return null;
  }
}

// Define generateHealthInsight using v2 syntax
exports.generateHealthInsight = onDocumentCreated("{collectionId}/{docId}", async (event) => {
    const snap = event.data; // Snapshot is in event.data
    if (!snap) {
      logger.error("No data associated with the event");
      return;
    }

    const { collectionId } = event.params; // Parameters are in event.params
    const data = snap.data();
    const userId = data.user_id;

    if (!userId) {
        logger.error("Missing user_id in document data", data);
        return;
    }

    if (!validCollections.includes(collectionId)) {
        logger.info(`Skipping document creation in irrelevant collection: ${collectionId}`);
        return; // Changed from null to void return
    }

    let userData = {};
    try {
        const userDoc = await db.collection("Users").doc(userId).get();
        if (userDoc.exists) {
            userData = userDoc.data();
        } else {
            logger.warn(`User document not found for user_id: ${userId}`);
        }
    } catch (error) {
        logger.error(`Error fetching user document for user_id: ${userId}`, error);
        return; // Exit if user data fetch fails
    }


    const prompt = buildPrompt(data, collectionId, userData);
    // Reading configuration; ensure OPENAI_API_KEY is set
    // Use functions.config() if set via `firebase functions:config:set openai.key="..."`
    // Fallback to process.env.OPENAI_API_KEY if set as an environment variable
    const apiKey = functions.config()?.openai?.key || process.env.OPENAI_API_KEY;

     if (!apiKey) {
        logger.error("OpenAI API key is not configured. Set OPENAI_API_KEY environment variable or 'openai.key' Firebase function config.");
        return;
    }

    const insight = await getInsightFromOpenAI(prompt, apiKey);

    if (!insight) {
        logger.warn("Failed to get insight from OpenAI.");
        return; // Changed from null to void return
    }

    try {
        // Optional: prevent storing duplicate insights (consider if needed, can be resource-intensive)
        const duplicateCheck = await db.collection("Insites")
          .where("user_id", "==", userId)
          .where("sourceCollection", "==", collectionId)
          .where("sourceData", "==", data) // Firestore equality check on objects can be tricky
          .limit(1)
          .get();

        if (!duplicateCheck.empty) {
          logger.log("Duplicate insight detected based on sourceData. Skipping...");
          return; // Changed from null to void return
        }

        await db.collection("Insites").add({
          user_id: userId,
          content: insight.content,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          sourceCollection: collectionId,
          sourceData: data // Storing the source data might be large/redundant, consider storing docId instead
        });
        logger.log(`Insight successfully generated and stored for user ${userId}, collection ${collectionId}`);

    } catch (error) {
        logger.error(`Error checking for duplicates or adding insight to Firestore for user ${userId}`, error);
    }

    // v2 functions should typically return void or a Promise that resolves to void
    return;
  });
