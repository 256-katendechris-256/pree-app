import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/dashboard.dart';

class HealthConditionsScreen extends StatefulWidget {
  final int pregnancyCount;
  final bool isCurrentlyPregnant;
  final bool hasHadHypertension;

  const HealthConditionsScreen({
    super.key,
    required this.pregnancyCount,
    required this.isCurrentlyPregnant,
    required this.hasHadHypertension,
  });

  @override
  State<HealthConditionsScreen> createState() => _HealthConditionsScreenState();
}

class _HealthConditionsScreenState extends State<HealthConditionsScreen> {
  // Firebase instances
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Loading state
  bool _isLoading = false;
  
  // List of health conditions to select from
  final List<String> _healthConditions = [
    'Diabetes',
    'Asthma',
    'Heart Disease',
    'Thyroid Disorder',
    'None of the above',
  ];

  // Selected health conditions
  final Set<String> _selectedConditions = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 0,
        title: const Text(
          'Health Conditions',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Progress indicator
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(
                  value: 1.0, // 100% progress
                  backgroundColor: Color(0xFFE0E0E0),
                  color: Colors.blue,
                ),
              ),

              // Progress text
              const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Text(
                  'Step 2 of 2: Health Conditions',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 14,
                  ),
                ),
              ),

              const Text(
                'Please select any health conditions that apply to you.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),

              const SizedBox(height: 30),

              // Health conditions list
              Column(
                children: _healthConditions.map((condition) {
                  return CheckboxListTile(
                    title: Text(
                      condition,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[800],
                      ),
                    ),
                    value: _selectedConditions.contains(condition),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedConditions.add(condition);
                        } else {
                          _selectedConditions.remove(condition);
                        }

                        // Ensure "None of the above" deselects all other options
                        if (condition == 'None of the above' && value == true) {
                          _selectedConditions.clear();
                          _selectedConditions.add('None of the above');
                        } else if (_selectedConditions.contains('None of the above')) {
                          _selectedConditions.remove('None of the above');
                        }
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                }).toList(),
              ),

              const SizedBox(height: 40),

              // Information note
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.blue.withOpacity(0.3),
                  ),
                ),
                child: const Text(
                  'Your responses will help us provide personalized health recommendations.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blue,
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitHealthData,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Submit',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Function to handle data submission
  Future<void> _submitHealthData() async {
    // Check if any condition is selected
    if (_selectedConditions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one health condition'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      // Get the user document reference
      final userRef = _firestore.collection('user').doc(user.uid);

      // Create health data to save
      final healthData = {
        'pregnancy_count': widget.pregnancyCount,
        'is_currently_pregnant': widget.isCurrentlyPregnant,
        'has_had_hypertension': widget.hasHadHypertension,
      };

      // Save pregnancy and hypertension data to user document
      await userRef.update(healthData);

      // Create a batch to save all health conditions
      final batch = _firestore.batch();
      
      // Reference to user's health_condition subcollection
      final healthConditionCollection = userRef.collection('health_condition');
      
      // First delete any existing health conditions
      final existingConditions = await healthConditionCollection.get();
      
      for (var doc in existingConditions.docs) {
        batch.delete(doc.reference);
      }
      
      // Then add new health conditions
      for (var condition in _selectedConditions) {
        // Skip "None of the above" to prevent saving it as an actual condition
        if (condition == 'None of the above') continue;

        final conditionRef = healthConditionCollection.doc();
        batch.set(conditionRef, {
          'condition': condition,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
      
      // Commit the batch
      await batch.commit();

      // Navigate to the dashboard screen
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const DashboardScreen()),
          (route) => false, // This removes all previous routes from the stack
        );
      }
    } catch (e) {
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving health data: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}