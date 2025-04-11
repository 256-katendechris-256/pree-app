import 'package:flutter/material.dart';
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
                  onPressed: () {
                    // Handle submission logic here
                    _submitHealthData();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
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
  void _submitHealthData() {
    // Collect all user inputs
    final Map<String, dynamic> userData = {
      'pregnancyCount': widget.pregnancyCount,
      'isCurrentlyPregnant': widget.isCurrentlyPregnant,
      'hasHadHypertension': widget.hasHadHypertension,
      'healthConditions': _selectedConditions.toList(),
    };

    // For now, just print the collected data
    print('User Data: $userData');

    // Navigate to the dashboard screen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const DashboardScreen()),
    );
  }
}