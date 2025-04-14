const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const { OpenAI } = require("openai");

admin.initializeApp();

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

// Using v2 syntax
exports.onActivityAdded = onDocumentCreated("activity/{docId}", async (event) => {
  const snapshot = event.data;
  if (!snapshot) {
    console.log("No data associated with the event");
    return;
  }
  
  const data = snapshot.data();
  const userId = data.user_id;

  console.log("✅ Triggered by new activity doc");
  console.log("📥 Received activity data:", JSON.stringify(data));

  const prompt = `
A pregnant patient has logged the following physical activity:
- Steps: ${data.steps}
- Calories: ${data.calories}

Based on this limited data, offer a gentle health insight or encouragement. Mention the importance of maintaining healthy activity during pregnancy. Avoid clinical advice since no medical vitals are available yet.
`;

  try {
    console.log("🤖 Sending prompt to OpenAI...");
    const completion = await openai.chat.completions.create({
      model: "gpt-3.5-turbo",
      messages: [
        {
          role: "system",
          content: "You are a supportive assistant encouraging healthy habits during pregnancy.",
        },
        {
          role: "user",
          content: prompt,
        },
      ],
    });

    const response = completion.choices[0].message.content;
    console.log("✅ OpenAI responded successfully");
    console.log("📤 Insight:", response);

    console.log("📝 Writing to Firestore -> Insites...");
    await admin.firestore()
      .collection("Insites")
      .add({
        user_id: userId,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        generatedInsight: response,
        rawData: data,
      });

    console.log("✅ Successfully saved to Insites collection");

  } catch (error) {
    console.error("❌ Error in generating insight or saving to Firestore:", error);
  }
});