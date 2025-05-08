import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'health_conditions.dart';

class HealthQuestionnaireScreen extends StatefulWidget {
  const HealthQuestionnaireScreen({super.key});

  @override
  State<HealthQuestionnaireScreen> createState() => _HealthQuestionnaireScreenState();
}

class _HealthQuestionnaireScreenState extends State<HealthQuestionnaireScreen> {
  // Firebase instances
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  final _pregnancyController = TextEditingController(text: '0');
  bool _hasHadHypertension = false;
  bool _currentlyPregnant = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  @override
  void dispose() {
    _pregnancyController.dispose();
    super.dispose();
  }

  // Load existing pregnancy history data if available
  Future<void> _loadExistingData() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      final user = _auth.currentUser;
      if (user == null) return;
      
      // Get the latest pregnancy history record
      final pregnancyHistorySnapshot = await _firestore
          .collection('user')
          .doc(user.uid)
          .collection('pregnancy_history')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();
      
      if (pregnancyHistorySnapshot.docs.isNotEmpty) {
        final data = pregnancyHistorySnapshot.docs.first.data();
        setState(() {
          _pregnancyController.text = data['number_of_pregnancies_had']?.toString() ?? '0';
          _currentlyPregnant = data['currently_pregnant'] ?? false;
          _hasHadHypertension = data['ever_had_hypertension'] ?? false;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading data: ${e.toString()}'),
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

  // Save pregnancy history data before navigating to next screen
  Future<void> _savePregnancyHistory() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }
      
      // Create the pregnancy history data
      final pregnancyData = {
        'number_of_pregnancies_had': int.parse(_pregnancyController.text),
        'currently_pregnant': _currentlyPregnant,
        'ever_had_hypertension': _hasHadHypertension,
        'timestamp': FieldValue.serverTimestamp(),
      };
      
      // Add to pregnancy_history subcollection
      await _firestore
          .collection('user')
          .doc(user.uid)
          .collection('pregnancy_history')
          .add(pregnancyData);
      
      // Navigate to the next screen
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HealthConditionsScreen(
              pregnancyCount: int.parse(_pregnancyController.text),
              isCurrentlyPregnant: _currentlyPregnant,
              hasHadHypertension: _hasHadHypertension,
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving data: ${e.toString()}'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 0,
        title: const Text(
          'Pregnancy History',
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Progress indicator
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: LinearProgressIndicator(
                        value: 0.5, // 50% progress
                        backgroundColor: Color(0xFFE0E0E0),
                        color: Colors.blue,
                      ),
                    ),

                    // Progress text
                    const Padding(
                      padding: EdgeInsets.only(bottom: 24),
                      child: Text(
                        'Step 1 of 2: Pregnancy Information',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 14,
                        ),
                      ),
                    ),

                    const Text(
                      'Please provide your pregnancy history information to help us personalize your health monitoring.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Number of pregnancies
                    const Text(
                      'Number of pregnancies you have had:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () {
                              int value = int.parse(_pregnancyController.text);
                              if (value > 0) {
                                setState(() {
                                  _pregnancyController.text = (value - 1).toString();
                                });
                              }
                            },
                          ),
                          Expanded(
                            child: TextField(
                              controller: _pregnancyController,
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () {
                              int value = int.parse(_pregnancyController.text);
                              setState(() {
                                _pregnancyController.text = (value + 1).toString();
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Currently pregnant
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Are you currently pregnant?',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[800],
                              ),
                            ),
                          ),
                          Switch(
                            value: _currentlyPregnant,
                            activeColor: Theme.of(context).primaryColor,
                            onChanged: (value) {
                              setState(() {
                                _currentlyPregnant = value;
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Hypertension before pregnancy
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Have you had hypertension before pregnancy?',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[800],
                              ),
                            ),
                          ),
                          Switch(
                            value: _hasHadHypertension,
                            activeColor: Theme.of(context).primaryColor,
                            onChanged: (value) {
                              setState(() {
                                _hasHadHypertension = value;
                              });
                            },
                          ),
                        ],
                      ),
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
                        'This information will help us tailor your health monitoring experience. '
                            'Please answer honestly and accurately.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blue,
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Continue Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _savePregnancyHistory,
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
                                'Continue',
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
}