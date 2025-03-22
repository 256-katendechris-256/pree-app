import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class WeightEntryScreen extends StatefulWidget {
  const WeightEntryScreen({super.key});

  @override
  State<WeightEntryScreen> createState() => _WeightEntryScreenState();
}

class _WeightEntryScreenState extends State<WeightEntryScreen> {
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final FocusNode _weightFocusNode = FocusNode();

  bool _showNumpad = false; // Initially hide the numpad
  String _currentFieldValue = '';
  TextEditingController? _currentController;
  FocusNode? _currentFocusNode;

  // Store weight unit
  String _weightUnit = 'kg'; // Default unit

  @override
  void initState() {
    super.initState();
    // Initialize with current date and time
    final now = DateTime.now();
    _dateController.text = DateFormat('dd/MM/yyyy').format(now);
    _timeController.text = DateFormat('h:mm a').format(now);

    // Set default values for focus and controllers
    _currentController = _weightController;
    _currentFocusNode = _weightFocusNode;
  }

  @override
  void dispose() {
    _weightController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    _noteController.dispose();
    _weightFocusNode.dispose();
    super.dispose();
  }

  void _onNumpadPressed(String value) {
    if (_currentController == null) return;

    setState(() {
      if (value == '⌫') { // Backspace
        if (_currentFieldValue.isNotEmpty) {
          _currentFieldValue = _currentFieldValue.substring(0, _currentFieldValue.length - 1);
        }
      } else if (value == 'Next') {
        _saveReading();
      } else if (value == '.') {
        // Only add decimal point if there isn't one already
        if (!_currentFieldValue.contains('.')) {
          _currentFieldValue = _currentFieldValue.isEmpty ? '0.' : '$_currentFieldValue.';
        }
      } else {
        // Only add the number if within reasonable range
        final newValue = _currentFieldValue + value;
        if (_currentController == _weightController) {
          // Allow decimal values for weight
          if (double.tryParse(newValue) != null) {
            // Limit to 1 decimal place
            final parts = newValue.split('.');
            if (parts.length == 1 || parts[1].length <= 1) {
              // Check if weight is within reasonable range (1-500 kg or 2-1100 lbs)
              final double weightValue = double.parse(newValue);
              final double maxWeight = _weightUnit == 'kg' ? 500.0 : 1100.0;
              if (weightValue > 0 && weightValue <= maxWeight) {
                _currentFieldValue = newValue;
              }
            }
          }
        }
      }

      // Update the controller text
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

  void _toggleWeightUnit() {
    setState(() {
      _weightUnit = _weightUnit == 'kg' ? 'lb' : 'kg';

      // Convert the current value if needed
      if (_weightController.text.isNotEmpty) {
        final double currentValue = double.tryParse(_weightController.text) ?? 0;
        if (currentValue > 0) {
          double convertedValue;
          if (_weightUnit == 'kg') {
            // Convert from lb to kg
            convertedValue = currentValue * 0.453592;
          } else {
            // Convert from kg to lb
            convertedValue = currentValue * 2.20462;
          }

          // Round to 1 decimal place
          _weightController.text = convertedValue.toStringAsFixed(1);
          _currentFieldValue = _weightController.text;
        }
      }
    });
  }

  void _saveReading() {
    // Validation
    if (_weightController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter weight value')),
      );
      return;
    }

    // Return the reading to the previous screen
    Navigator.pop(context, {
      'weight': double.parse(_weightController.text),
      'unit': _weightUnit,
      'date': _dateController.text,
      'time': _timeController.text,
      'note': _noteController.text,
    });
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
            onPressed: _saveReading,
            child: const Text(
              'ADD',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Column(
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
                  _buildWeightField(),
                  _buildInputField(
                    label: 'Note:',
                    controller: _noteController,
                    isMultiline: true,
                    onTap: () {
                      setState(() {
                        _showNumpad = false;
                      });
                    },
                  ),
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

  Widget _buildWeightField() {
    final bool isCurrentFocus = _currentFocusNode == _weightFocusNode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: const Text(
              'Weight:',
              style: TextStyle(
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                _setFocusToField(_weightController, _weightFocusNode);
                setState(() {
                  _showNumpad = true;
                });
              },
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
                            _weightController.text,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                          if (isCurrentFocus && _weightController.text.isEmpty)
                            Container(
                              width: 2,
                              height: 20,
                              color: Colors.blue.shade700,
                              margin: const EdgeInsets.only(left: 2),
                            ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          _weightUnit,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.swap_horiz, size: 20),
                          color: Colors.blue.shade800,
                          onPressed: _toggleWeightUnit,
                        ),
                      ],
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

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    String? suffix,
    bool readOnly = false,
    VoidCallback? onTap,
    IconData? trailingIcon,
    FocusNode? focusNode,
    bool isMultiline = false,
  }) {
    final bool isCurrentFocus = _currentFocusNode == focusNode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: isMultiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
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
                child: isMultiline
                    ? TextField(
                  controller: controller,
                  decoration: const InputDecoration.collapsed(
                    hintText: 'Add a note (optional)',
                  ),
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                )
                    : Row(
                  children: [
                    Expanded(
                      child: Text(
                        controller.text,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                        ),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildToolbarButton(Icons.note),
              _buildToolbarButton(Icons.mood),
              _buildToolbarButton(Icons.grid_on),
              _buildToolbarButton(Icons.mic),
              _buildToolbarButton(Icons.settings),
              _buildToolbarButton(Icons.more_horiz),
            ],
          ),
          const SizedBox(height: 8),
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