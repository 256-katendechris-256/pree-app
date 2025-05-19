// Updated ManualWeightScreen class
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';
import 'package:intl/intl.dart';

class ManualWeightScreen extends StatefulWidget {
  const ManualWeightScreen({super.key});

  @override
  State<ManualWeightScreen> createState() => _ManualWeightScreenState();
}

class _ManualWeightScreenState extends State<ManualWeightScreen> {
  // Text controllers
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  
  // Firebase instances
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Height in cm
  double _heightInCm = 170.0;
  
  // Weight in kg
  double _weightInKg = 70.0;
  
  // BMI
  double _bmi = 0.0;
  
  // Previous weight value from Firestore
  double? _previousWeight;
  
  // Loading state
  bool _isLoading = false;
  
  @override
  void initState() {
    super.initState();
    _loadUserData();
  }
  
  Future<void> _loadUserData() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) return;
      
      // Try to get the user's height from their profile
      var userDoc = await _firestore.collection('user').doc(currentUser.uid).get();
      if (userDoc.exists && userDoc.data()!.containsKey('height')) {
        _heightInCm = userDoc.data()!['height'] ?? 170.0;
        _heightController.text = _heightInCm.toString();
      }
      
      // Get the most recent weight entry to calculate change
      var weightDocs = await _firestore
          .collection('weight')
          .where('user_id', isEqualTo: currentUser.uid)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();
      
      if (weightDocs.docs.isNotEmpty) {
        _previousWeight = weightDocs.docs.first.data()['current'] ?? 0.0;
      }
    } catch (e) {
      print('Error loading user data: $e');
    }
  }
  
  void _calculateBMI() {
    // Formula: BMI = weight(kg) / height(m)²
    double heightInMeters = _heightInCm / 100;
    _bmi = _weightInKg / (heightInMeters * heightInMeters);
    
    // Round to 1 decimal place
    _bmi = double.parse(_bmi.toStringAsFixed(1));
  }
  
  String _getBMIStatus(double bmi) {
    if (bmi < 18.5) {
      return 'Underweight';
    } else if (bmi < 25) {
      return 'Normal';
    } else if (bmi < 30) {
      return 'Overweight';
    } else {
      return 'Obese';
    }
  }
  
  Future<void> _saveWeight() async {
    // Validate inputs
    if (_weightController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your weight')),
      );
      return;
    }
    
    if (_heightController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your height for BMI calculation')),
      );
      return;
    }
    
    // Parse weight and height
    _weightInKg = double.tryParse(_weightController.text) ?? 0.0;
    _heightInCm = double.tryParse(_heightController.text) ?? 0.0;
    
    if (_weightInKg <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid weight')),
      );
      return;
    }
    
    if (_heightInCm <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid height')),
      );
      return;
    }
    
    // Calculate BMI
    _calculateBMI();
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not logged in');
      }
      
      // Calculate weight change if we have a previous weight
      double change = 0.0;
      if (_previousWeight != null) {
        change = _weightInKg - _previousWeight!;
      }
      
      // Get the current timestamp
      Timestamp timestamp = Timestamp.now();
      
      // Save weight entry directly to the weight collection
      await _firestore.collection('weight').add({
        'user_id': currentUser.uid,
        'current': _weightInKg,
        'bmi': _bmi,
        'status': _getBMIStatus(_bmi),
        'timestamp': timestamp,
        'change': change,
        'goal': 70.0, // Default goal - can be updated from settings
      });
      
      // Update user's height in the user profile
      await _firestore.collection('user').doc(currentUser.uid).set({
        'height': _heightInCm,
        'last_updated': timestamp,
      }, SetOptions(merge: true));
      
      // Return to previous screen with success status
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('Error saving weight entry: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving weight: $e')),
        );
      }
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
      appBar: AppBar(
        title: const Text('Add Weight Entry'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter your current weight and height',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _weightController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Weight (kg)',
                      border: OutlineInputBorder(),
                      suffixText: 'kg',
                    ),
                    onChanged: (value) {
                      if (value.isNotEmpty && _heightController.text.isNotEmpty) {
                        setState(() {
                          _weightInKg = double.tryParse(value) ?? 0.0;
                          _calculateBMI();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _heightController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Height (cm)',
                      border: OutlineInputBorder(),
                      suffixText: 'cm',
                    ),
                    onChanged: (value) {
                      if (value.isNotEmpty && _weightController.text.isNotEmpty) {
                        setState(() {
                          _heightInCm = double.tryParse(value) ?? 0.0;
                          _calculateBMI();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  if (_weightController.text.isNotEmpty && _heightController.text.isNotEmpty && _bmi > 0)
                    _buildBMIPreview(),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saveWeight,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Save Weight Entry'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
  
  Widget _buildBMIPreview() {
    Color bmiColor;
    String bmiCategory = _getBMIStatus(_bmi);
    
    if (_bmi < 18.5) {
      bmiColor = Colors.blue;
    } else if (_bmi < 25) {
      bmiColor = Colors.green;
    } else if (_bmi < 30) {
      bmiColor = Colors.orange;
    } else {
      bmiColor = Colors.red;
    }
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BMI Preview',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_bmi.toStringAsFixed(1)}',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const Text(
                      'kg/m²',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: bmiColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    bmiCategory,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: (_bmi / 40).clamp(0.0, 1.0),
              backgroundColor: Colors.grey[200],
              color: bmiColor,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildBMICategoryLabel('Underweight', Colors.blue),
                _buildBMICategoryLabel('Normal', Colors.green),
                _buildBMICategoryLabel('Overweight', Colors.orange),
                _buildBMICategoryLabel('Obese', Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildBMICategoryLabel(String label, Color color) {
    return Column(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
  
  @override
  void dispose() {
    _weightController.dispose();
    _heightController.dispose();
    super.dispose();
  }
}