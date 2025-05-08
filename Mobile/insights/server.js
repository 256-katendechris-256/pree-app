// Install these packages first:
// npm install express dotenv cors axios

// server.js - Using Hugging Face API
const express = require('express');
const dotenv = require('dotenv');
const cors = require('cors');
const axios = require('axios');

// Load environment variables
dotenv.config();

const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// Test route
app.get('/api/test', (req, res) => {
  res.json({ message: 'Backend is working!' });
});

// Insights route using Hugging Face
app.post('/api/insights', async (req, res) => {
  try {
    // Get user data from request body
    const { userData } = req.body;
    
    if (!userData) {
      return res.status(400).json({ error: 'User data is required' });
    }
    
    // Format the BP readings for easier reading
    const formattedBP = userData.vitals 
      ? userData.vitals.map(v => `${new Date(v.timestamp).toLocaleDateString()}: ${v.systolic}/${v.diastolic}`)
      : [];
      
    // Format symptoms
    const formattedSymptoms = userData.symptoms
      ? userData.symptoms.map(s => `${new Date(s.timestamp).toLocaleDateString()}: ${s.symptomsList.join(', ')}`)
      : [];
    
    // Create a prompt
    const prompt = `
    You are a health insights assistant for a preeclampsia monitoring app.
    
    Patient profile:
    - Age: ${userData.profile?.age || 'Unknown'}
    - Pregnancy week: ${userData.profile?.gestationalAge || 'Unknown'}
    - Previous conditions: ${userData.profile?.conditions?.join(', ') || 'None reported'}
    
    Recent blood pressure readings:
    ${formattedBP.join('\n')}
    
    Recent symptoms:
    ${formattedSymptoms.join('\n')}
    
    Based on this information, please provide:
    1. A summary of key health trends
    2. General wellness recommendations
    3. Any patterns that might be worth discussing with a healthcare provider
    
    Format your response as JSON with fields: "summary", "recommendations", "discussWithDoctor".
    `;
    
    // Call Hugging Face API with Mistral or another free model
    const response = await axios.post(
      'https://api-inference.huggingface.co/models/mistralai/Mistral-7B-Instruct-v0.2',
      {
        inputs: prompt,
        parameters: {
          max_new_tokens: 1024,
          temperature: 0.7,
          return_full_text: false
        }
      },
      {
        headers: {
          'Authorization': `Bearer ${process.env.HUGGINGFACE_API_KEY}`,
          'Content-Type': 'application/json'
        }
      }
    );
    
    // Extract the text from Hugging Face's response
    const aiResponse = response.data[0]?.generated_text || '';
    
    // Try to parse JSON from the response
    let insights;
    try {
      // Look for JSON in the response
      const jsonMatch = aiResponse.match(/```json\n([\s\S]*?)\n```/) || 
                      aiResponse.match(/{[\s\S]*?}/);
                      
      if (jsonMatch) {
        insights = JSON.parse(jsonMatch[1] || jsonMatch[0]);
      } else {
        // If no JSON found, create a simple structure
        insights = {
          summary: aiResponse.substring(0, 500), // First 500 chars as summary
          recommendations: ['Stay hydrated', 'Monitor blood pressure regularly', 'Rest adequately'],
          discussWithDoctor: ['Any significant changes in blood pressure', 'Persistent headaches']
        };
      }
    } catch (error) {
      console.error('Error parsing AI response:', error);
      insights = {
        summary: aiResponse.substring(0, 500),
        recommendations: ['Stay hydrated', 'Monitor blood pressure regularly', 'Rest adequately'],
        discussWithDoctor: ['Any significant changes in blood pressure', 'Persistent headaches']
      };
    }
    
    // Send insights back to client
    res.json({ insights });
    
  } catch (error) {
    console.error('Error generating insights:', error);
    res.status(500).json({ 
      error: 'Failed to generate insights',
      details: error.message
    });
  }
});

// Start server
const PORT = process.env.PORT || 5000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});