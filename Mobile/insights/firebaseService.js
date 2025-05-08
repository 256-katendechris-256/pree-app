// insights/firebaseService.js
import firebase from 'firebase/app';
import 'firebase/database';

// Function to get user health data
export const getUserHealthData = async (userId) => {
  try {
    // 1. Get basic user profile
    const profileRef = firebase.database().ref(`users/${userId}/profile`);
    const profileSnapshot = await profileRef.once('value');
    const profile = profileSnapshot.val() || {};
    
    // 2. Get recent vital signs (last 2 weeks)
    const twoWeeksAgo = Date.now() - (14 * 24 * 60 * 60 * 1000);
    const vitalsRef = firebase.database().ref(`users/${userId}/vitals`);
    const vitalsQuery = vitalsRef.orderByChild('timestamp').startAt(twoWeeksAgo);
    const vitalsSnapshot = await vitalsQuery.once('value');
    
    const vitals = [];
    vitalsSnapshot.forEach((childSnapshot) => {
      vitals.push({
        id: childSnapshot.key,
        ...childSnapshot.val()
      });
    });
    
    // 3. Get recent symptoms
    const symptomsRef = firebase.database().ref(`users/${userId}/symptoms`);
    const symptomsQuery = symptomsRef.orderByChild('timestamp').startAt(twoWeeksAgo);
    const symptomsSnapshot = await symptomsQuery.once('value');
    
    const symptoms = [];
    symptomsSnapshot.forEach((childSnapshot) => {
      symptoms.push({
        id: childSnapshot.key,
        ...childSnapshot.val()
      });
    });
    
    return {
      profile,
      vitals,
      symptoms
    };
  } catch (error) {
    console.error('Error getting user health data:', error);
    throw error;
  }
};

export default { getUserHealthData };