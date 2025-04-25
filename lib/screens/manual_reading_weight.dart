// screens/manual_weight_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

class ManualWeightScreen extends StatefulWidget {
  const ManualWeightScreen({super.key});

  @override
  State<ManualWeightScreen> createState() => _ManualWeightScreenState();
}

class _ManualWeightScreenState extends State<ManualWeightScreen> {
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final FocusNode _weightFocusNode = FocusNode();
  
  bool _showNumpad = false;
  bool _isLoading = false;
  String _currentFieldValue = '';
  TextEditingController? _currentController;
  FocusNode? _currentFocusNode;
  
  // Weight unit selection
  String _selectedUnit = 'kg'; // Default to kg

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateController.text = DateFormat('dd/MM/yyyy').format(now);
    _timeController.text = DateFormat('h:mm a').format(now);
    _currentController = _weightController;
    _currentFocusNode = _weightFocusNode;
  }

  @override
  void dispose() {
    _weightController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    _weightFocusNode.dispose();
    super.dispose();
  }

  void _onNumpadPressed(String value) {
    if (_currentController == null) return;

    setState(() {
      if (value == '⌫') {
        if (_currentFieldValue.isNotEmpty) {
          _currentFieldValue = _currentFieldValue.substring(0, _currentFieldValue.length - 1);
        }
      } else if (value == 'Next') {
        _saveWeight();
      } else if (value == '.' && !_currentFieldValue.contains('.')) {
        // Allow decimal point only if it doesn't already exist
        _currentFieldValue = _currentFieldValue.isEmpty ? '0.' : '$_currentFieldValue.';
      } else if (value != '.' && value != ',') {
        // Handle numeric input
        final newValue = _currentFieldValue + value;
        // Validate weight input - allow up to 250 kg or 550 lbs with one decimal place
        if (_selectedUnit == 'kg') {
          if (newValue.contains('.')) {
            // Allow one decimal place
            final parts = newValue.split('.');
            if (parts.length == 2 && parts[1].length <= 1) {
              if (double.tryParse(newValue) != null && double.parse(newValue) <= 250) {
                _currentFieldValue = newValue;
              }
            }
          } else {
            if (int.tryParse(newValue) != null && int.parse(newValue) <= 250) {
              _currentFieldValue = newValue;
            }
          }
        } else { // lbs
          if (newValue.contains('.')) {
            // Allow one decimal place
            final parts = newValue.split('.');
            if (parts.length == 2 && parts[1].length <= 1) {
              if (double.tryParse(newValue) != null && double.parse(newValue) <= 550) {
                _currentFieldValue = newValue;
              }
            }
          } else {
            if (int.tryParse(newValue) != null && int.parse(newValue) <= 550) {
              _currentFieldValue = newValue;
            }
          }
        }
      }
      _currentController!.text = _currentFieldValue;
    });
  }

  void _setFocusToField(TextEditingController controller, FocusNode focusNode) {
    setState(() {
      _currentController = controller;
      _currentFocusNode = focusNode;
      _currentFieldValue = controller.text;
      focusNode.requestFocus();
    });
  }

  Future<void> _saveWeight() async {
    if (_weightController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a weight value')),
      );
      return;
    }

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not authenticated')),
      );
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });
      
      final date = DateFormat('dd/MM/yyyy').parse(_dateController.text);
      final time = DateFormat('h:mm a').parse(_timeController.text);
      
      final DateTime timestamp = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );

      // Convert to double and handle unit conversion if needed
      double weightValue = double.parse(_weightController.text);
      double weightInKg = _selectedUnit == 'kg' ? weightValue : weightValue * 0.45359237;

      // Get user's height from the users collection (in cm)
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!userDoc.exists || !userDoc.data()!.containsKey('height')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Height information is missing. Please update your profile first.')),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Height should be in cm, convert to meters for BMI calculation
      double heightInCm = double.parse(userDoc.data()!['height'].toString());
      double heightInMeters = heightInCm / 100;

      // Calculate BMI = weight(kg) / height²(m)
      double bmi = weightInKg / pow(heightInMeters, 2);
      String bmiValue = bmi.toStringAsFixed(1);

      // Determine BMI status
      String bmiStatus;
      if (bmi < 18.5) {
        bmiStatus = "Underweight";
      } else if (bmi >= 18.5 && bmi < 25) {
        bmiStatus = "Normal";
      } else if (bmi >= 25 && bmi < 30) {
        bmiStatus = "Overweight";
      } else {
        bmiStatus = "Obese";
      }

      // Get previous BMI for change calculation
      String change = "+0.0"; // Default if no previous entry exists
      
      final previousBmi = await FirebaseFirestore.instance
          .collection('bmi')
          .where('user_id', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();
      
      if (previousBmi.docs.isNotEmpty) {
        double previousBmiValue = double.parse(previousBmi.docs.first['current']);
        double difference = bmi - previousBmiValue;
        change = difference >= 0 ? "+${difference.toStringAsFixed(1)}" : difference.toStringAsFixed(1);
      }

      // Save weight measurement
      await FirebaseFirestore.instance.collection('weight_measurements').add({
        'weight': weightValue,
        'weight_kg': double.parse(weightInKg.toStringAsFixed(1)), // Standardize to 1 decimal place
        'unit': _selectedUnit,
        'date': _dateController.text,
        'time': _timeController.text,
        'timestamp': Timestamp.fromDate(timestamp),
        'user_id': user.uid,
      });
      
      // Save BMI record
      await FirebaseFirestore.instance.collection('bmi').add({
        'bmi': bmiValue,
        'current': bmiValue,
        'change': change,
        'status': bmiStatus,
        'timestamp': Timestamp.fromDate(timestamp),
        'user_id': user.uid,
      });

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0069B4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Add weight measurement',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveWeight,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'ADD',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Form fields
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                  _buildInputField(
                    label: 'Date:',
                    controller: _dateController,
                    readOnly: true,
                    trailingIcon: Icons.calendar_today,
                    onTap: () async {
                      // Hide numpad when selecting date
                      setState(() {
                        _showNumpad = false;
                      });

                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() {
                          _dateController.text = DateFormat('dd/MM/yyyy').format(picked);
                        });
                      }
                    },
                  ),
                  _buildInputField(
                    label: 'Time:',
                    controller: _timeController,
                    readOnly: true,
                    onTap: () async {
                      // Hide numpad when selecting time
                      setState(() {
                        _showNumpad = false;
                      });

                      final TimeOfDay? picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (picked != null) {
                        setState(() {
                          final now = DateTime.now();
                          final dt = DateTime(
                              now.year, now.month, now.day, picked.hour, picked.minute);
                          _timeController.text = DateFormat('h:mm a').format(dt);
                        });
                      }
                    },
                  ),
                  _buildWeightFieldWithUnit(
                    label: 'Weight:',
                    controller: _weightController,
                    focusNode: _weightFocusNode,
                    showCursor: true,
                    onTap: () {
                      _setFocusToField(_weightController, _weightFocusNode);
                      setState(() {
                        _showNumpad = true;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  _buildWeightInfo(),
                ],
              ),
            ),
          ),

          // Numpad (only shown when a numeric field is tapped)
          if (_showNumpad)
            _buildNumpad(),
        ],
      ),
    );
  }

  Widget _buildWeightInfo() {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseAuth.instance.currentUser != null
          ? FirebaseFirestore.instance
              .collection('bmi')
              .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
              .orderBy('timestamp', descending: true)
              .limit(1)
              .get()
          : Future.value(null),
      builder: (context, snapshot) {
        // Default BMI info
        Widget bmiInfo = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Healthy Weight Range:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedUnit == 'kg' 
                  ? '• Underweight: Less than 18.5 kg/m²\n• Healthy weight: 18.5 to 24.9 kg/m²\n• Overweight: 25 to 29.9 kg/m²\n• Obesity: 30 kg/m² or higher'
                  : '• Underweight: Less than 40.8 lbs/m²\n• Healthy weight: 40.8 to 54.9 lbs/m²\n• Overweight: 55.1 to 65.9 lbs/m²\n• Obesity: 66.1 lbs/m² or higher',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.blue,
              ),
            ),
          ],
        );

        // Show last BMI if available
        if (snapshot.hasData && snapshot.data != null && snapshot.data!.docs.isNotEmpty) {
          final bmiData = snapshot.data!.docs.first.data() as Map<String, dynamic>;
          if (bmiData.isNotEmpty) {
            bmiInfo = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your BMI Information:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current BMI: ${bmiData['current']}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.blue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Status: ${bmiData['status']}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Change: ${bmiData['change']}',
                          style: TextStyle(
                            fontSize: 14,
                            color: bmiData['change'].toString().startsWith('+') 
                                ? Colors.red 
                                : (bmiData['change'] == '+0.0' || bmiData['change'] == '0.0') 
                                    ? Colors.grey 
                                    : Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Date: ${DateFormat('dd/MM/yyyy').format(
                            (bmiData['timestamp'] as Timestamp).toDate()
                          )}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.blue),
                const SizedBox(height: 8),
                Text(
                  _selectedUnit == 'kg' 
                      ? '• Underweight: Less than 18.5 kg/m²\n• Healthy weight: 18.5 to 24.9 kg/m²\n• Overweight: 25 to 29.9 kg/m²\n• Obesity: 30 kg/m² or higher'
                      : '• Underweight: Less than 40.8 lbs/m²\n• Healthy weight: 40.8 to 54.9 lbs/m²\n• Overweight: 55.1 to 65.9 lbs/m²\n• Obesity: 66.1 lbs/m² or higher',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.blue,
                  ),
                ),
              ],
            );
          }
        }
        
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bmiInfo,
              const SizedBox(height: 8),
              const Text(
                'Note: These are general BMI ranges and may not apply to all individuals.',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 12,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWeightFieldWithUnit({
    required String label,
    required TextEditingController controller,
    VoidCallback? onTap,
    FocusNode? focusNode,
    bool showCursor = false,
  }) {
    final bool isCurrentFocus = _currentFocusNode == focusNode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isCurrentFocus ? Colors.blue.shade700 : Colors.grey.shade300,
                    width: isCurrentFocus ? 2.0 : 1.0,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Text(
                            controller.text,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                          if (showCursor && isCurrentFocus && controller.text.isEmpty)
                            Container(
                              width: 2,
                              height: 20,
                              color: Colors.blue.shade700,
                              margin: const EdgeInsets.only(left: 2),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildUnitSelector(),
        ],
      ),
    );
  }

  Widget _buildUnitSelector() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildUnitOption('kg'),
          _buildUnitOption('lbs'),
        ],
      ),
    );
  }

  Widget _buildUnitOption(String unit) {
    final isSelected = _selectedUnit == unit;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_selectedUnit != unit) {
            // Convert weight value when changing units
            if (_weightController.text.isNotEmpty) {
              double currentValue = double.tryParse(_weightController.text) ?? 0;
              if (unit == 'kg' && _selectedUnit == 'lbs') {
                // Convert from lbs to kg
                double kgValue = currentValue * 0.45359237;
                _weightController.text = kgValue.toStringAsFixed(1);
                _currentFieldValue = _weightController.text;
              } else if (unit == 'lbs' && _selectedUnit == 'kg') {
                // Convert from kg to lbs
                double lbsValue = currentValue / 0.45359237;
                _weightController.text = lbsValue.toStringAsFixed(1);
                _currentFieldValue = _weightController.text;
              }
            }
            _selectedUnit = unit;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade800 : Colors.white,
          borderRadius: unit == 'kg' 
              ? const BorderRadius.only(topLeft: Radius.circular(3), bottomLeft: Radius.circular(3))
              : const BorderRadius.only(topRight: Radius.circular(3), bottomRight: Radius.circular(3)),
        ),
        child: Text(
          unit,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.blue.shade800,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    String? suffix,
    bool readOnly = false,
    VoidCallback? onTap,
    IconData? trailingIcon,
    FocusNode? focusNode,
    bool showCursor = false,
  }) {
    final bool isCurrentFocus = _currentFocusNode == focusNode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isCurrentFocus ? Colors.blue.shade700 : Colors.grey.shade300,
                    width: isCurrentFocus ? 2.0 : 1.0,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Text(
                            controller.text,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                          if (showCursor && isCurrentFocus && controller.text.isEmpty)
                            Container(
                              width: 2,
                              height: 20,
                              color: Colors.blue.shade700,
                              margin: const EdgeInsets.only(left: 2),
                            ),
                        ],
                      ),
                    ),
                    if (suffix != null)
                      Text(
                        suffix,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    if (trailingIcon != null)
                      Icon(
                        trailingIcon,
                        color: Colors.blue.shade800,
                        size: 20,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumpad() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          // Numpad shortcuts row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildToolbarButton(Icons.note),
              _buildToolbarButton(Icons.mood),
              _buildToolbarButton(Icons.grid_on),
              _buildToolbarButton(Icons.scale),
              _buildToolbarButton(Icons.settings),
              _buildToolbarButton(Icons.more_horiz),
            ],
          ),
          const SizedBox(height: 8),
          // Numpad grid
          Row(
            children: [
              Expanded(
                child: GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.5,
                  padding: EdgeInsets.zero,
                  children: [
                    _buildNumpadKey('1'),
                    _buildNumpadKey('2'),
                    _buildNumpadKey('3'),
                    _buildNumpadKey('⌫'),
                    _buildNumpadKey('4'),
                    _buildNumpadKey('5'),
                    _buildNumpadKey('6'),
                    _buildNumpadKey('Next', isBlue: true),
                    _buildNumpadKey('7'),
                    _buildNumpadKey('8'),
                    _buildNumpadKey('9'),
                    _buildNumpadKey('.'),
                    _buildNumpadKey('0'),
                    _buildNumpadKey(''),
                    _buildNumpadKey(''),
                    _buildNumpadKey(''),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarButton(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey,
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: 20,
      ),
    );
  }

  Widget _buildNumpadKey(String value, {bool isBlue = false}) {
    return InkWell(
      onTap: value.isEmpty ? null : () => _onNumpadPressed(value),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade800,
          border: Border.all(color: Colors.black, width: 0.5),
        ),
        child: Center(
          child: Text(
            value,
            style: TextStyle(
              color: isBlue ? Colors.blue : Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}