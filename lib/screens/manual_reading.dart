// screens/manual_reading_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ManualReadingScreen extends StatefulWidget {
  const ManualReadingScreen({super.key});

  @override
  State<ManualReadingScreen> createState() => _ManualReadingScreenState();
}

class _ManualReadingScreenState extends State<ManualReadingScreen> {
  final TextEditingController _systolicController = TextEditingController();
  final TextEditingController _diastolicController = TextEditingController();
  final TextEditingController _pulseController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final FocusNode _systolicFocusNode = FocusNode();
  final FocusNode _diastolicFocusNode = FocusNode();
  final FocusNode _pulseFocusNode = FocusNode();

  bool _showNumpad = false; // Initially hide the numpad
  String _currentFieldValue = '';
  TextEditingController? _currentController;
  FocusNode? _currentFocusNode;

  @override
  void initState() {
    super.initState();
    // Initialize with current date and time
    final now = DateTime.now();
    _dateController.text = DateFormat('dd/MM/yyyy').format(now);
    _timeController.text = DateFormat('h:mm a').format(now);

    // Set default values for focus and controllers
    _currentController = _systolicController;
    _currentFocusNode = _systolicFocusNode;
  }

  @override
  void dispose() {
    _systolicController.dispose();
    _diastolicController.dispose();
    _pulseController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    _systolicFocusNode.dispose();
    _diastolicFocusNode.dispose();
    _pulseFocusNode.dispose();
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
        // Handle next field logic
        if (_currentController == _systolicController) {
          _setFocusToField(_diastolicController, _diastolicFocusNode);
        } else if (_currentController == _diastolicController) {
          _setFocusToField(_pulseController, _pulseFocusNode);
        } else {
          // Submit form if on the last field
          _saveReading();
        }
      } else {
        // Only add the number if within reasonable range
        final newValue = _currentFieldValue + value;
        if (int.tryParse(newValue) != null) {
          if (_currentController == _systolicController && int.parse(newValue) <= 250 ||
              _currentController == _diastolicController && int.parse(newValue) <= 150 ||
              _currentController == _pulseController && int.parse(newValue) <= 220) {
            _currentFieldValue = newValue;
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

  void _saveReading() {
    // Validation
    if (_systolicController.text.isEmpty ||
        _diastolicController.text.isEmpty ||
        _pulseController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter all values')),
      );
      return;
    }

    // Return the reading to the previous screen
    Navigator.pop(context, {
      'systolic': int.parse(_systolicController.text),
      'diastolic': int.parse(_diastolicController.text),
      'pulse': int.parse(_pulseController.text),
      'date': _dateController.text,
      'time': _timeController.text,
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
          'Add blood pressure reading',
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
                  _buildInputField(
                    label: 'Systolic\n(Upper Number):',
                    controller: _systolicController,
                    suffix: 'mmHg',
                    focusNode: _systolicFocusNode,
                    showCursor: true,
                    onTap: () {
                      _setFocusToField(_systolicController, _systolicFocusNode);
                      setState(() {
                        _showNumpad = true;
                      });
                    },
                  ),
                  _buildInputField(
                    label: 'Diastolic\n(Lower Number):',
                    controller: _diastolicController,
                    suffix: 'mmHg',
                    focusNode: _diastolicFocusNode,
                    showCursor: true,
                    onTap: () {
                      _setFocusToField(_diastolicController, _diastolicFocusNode);
                      setState(() {
                        _showNumpad = true;
                      });
                    },
                  ),
                  _buildInputField(
                    label: 'Pulse:',
                    controller: _pulseController,
                    suffix: 'BPM',
                    focusNode: _pulseFocusNode,
                    showCursor: true,
                    onTap: () {
                      _setFocusToField(_pulseController, _pulseFocusNode);
                      setState(() {
                        _showNumpad = true;
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
              _buildToolbarButton(Icons.mic),
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
                    _buildNumpadKey('.-'),
                    _buildNumpadKey('0'),
                    _buildNumpadKey(''),
                    _buildNumpadKey(','),
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