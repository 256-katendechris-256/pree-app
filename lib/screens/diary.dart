import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MyDiaryScreen extends StatefulWidget {
  const MyDiaryScreen({super.key});

  @override
  State<MyDiaryScreen> createState() => _MyDiaryScreenState();
}

class _MyDiaryScreenState extends State<MyDiaryScreen> {
  // Firebase instances
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Selected tab index - default to "My Symptoms" since notes tab is removed
  int _selectedTabIndex = 0; 
  bool _isLoading = false;

  // Selected symptoms and consumption items
  final Set<String> _selectedSymptoms = {};
  final Set<String> _selectedConsumptionItems = {};
  
  // For custom symptom or consumption item
  final TextEditingController _customSymptomController = TextEditingController();
  final TextEditingController _customConsumptionController = TextEditingController();
  final TextEditingController _symptomDetailsController = TextEditingController();

  @override
  void dispose() {
    _customSymptomController.dispose();
    _customConsumptionController.dispose();
    _symptomDetailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue[800],
        title: const Text(
          'My Diary',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text(
              'CANCEL',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        leading: Container(), // Remove back button
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildTabBar(),
                Expanded(
                  child: _buildTabContent(),
                ),
              ],
            ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildTabBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[200],
      ),
      child: Row(
        children: [
          _buildTabItem('My Symptoms', 0),
          _buildTabItem('What I Consumed', 1),
        ],
      ),
    );
  }

  Widget _buildTabItem(String title, int index) {
    final isSelected = _selectedTabIndex == index;

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedTabIndex = index;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.grey[200],
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.grey[700],
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return _buildSymptomsTab();
      case 1:
        return _buildConsumptionTab();
      default:
        return _buildSymptomsTab();
    }
  }

  Widget _buildSymptomsTab() {
    return SingleChildScrollView(
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Do you have any symptoms today?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2D4356),
              ),
            ),
            const SizedBox(height: 10),
            _selectedSymptoms.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'You have not noted any discomfort today',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _selectedSymptoms.map((symptom) {
                      return Chip(
                        label: Text(symptom),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () {
                          setState(() {
                            _selectedSymptoms.remove(symptom);
                          });
                        },
                        backgroundColor: Colors.blue[50],
                        labelStyle: const TextStyle(color: Colors.blue),
                      );
                    }).toList(),
                  ),
            const SizedBox(height: 24),
            const Text(
              'Are you experiencing any of these today?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2D4356),
              ),
            ),
            const SizedBox(height: 16),
            _buildSymptomGrid(),
            const SizedBox(height: 20),
            
            if (_selectedSymptoms.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Add details about your symptoms:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF2D4356),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _symptomDetailsController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Describe your symptoms in more detail...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
            
            const SizedBox(height: 20),
            _buildAddSymptomButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildSymptomGrid() {
    // List of symptoms with their icon paths
    final symptoms = [
      {'name': 'Dry Cough', 'icon': Icons.healing},
      {'name': 'Headache', 'icon': Icons.flash_on},
      {'name': 'Dizziness', 'icon': Icons.face},
      {'name': 'Palpitations', 'icon': Icons.favorite_border},
      {'name': 'Hot Flash', 'icon': Icons.water_drop},
      {'name': 'Swollenness', 'icon': Icons.accessibility_new},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: symptoms.length,
      itemBuilder: (context, index) {
        final symptom = symptoms[index];
        final isSelected = _selectedSymptoms.contains(symptom['name']);

        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedSymptoms.remove(symptom['name']);
              } else {
                _selectedSymptoms.add(symptom['name'] as String);
              }
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? Colors.blue : Colors.grey[300]!,
                width: 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  symptom['icon'] as IconData,
                  color: Colors.blue,
                  size: 30,
                ),
                const SizedBox(height: 8),
                Text(
                  symptom['name'] as String,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.blue,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddSymptomButton() {
    return TextButton.icon(
      onPressed: () {
        _showAddCustomItemDialog(
          title: 'Add Custom Symptom',
          hint: 'Enter symptom name',
          controller: _customSymptomController,
          onAdd: (value) {
            if (value.isNotEmpty) {
              setState(() {
                _selectedSymptoms.add(value);
              });
            }
          },
        );
      },
      icon: const Icon(
        Icons.add_circle_outline,
        color: Colors.blue,
        size: 20,
      ),
      label: const Text(
        'My symptom is not listed. Add it',
        style: TextStyle(
          color: Colors.blue,
          fontSize: 14,
          fontWeight: FontWeight.normal,
        ),
      ),
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        alignment: Alignment.centerLeft,
      ),
    );
  }

  Widget _buildConsumptionTab() {
    return SingleChildScrollView(
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.more_horiz,
                  color: Colors.grey,
                  size: 24,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'What did you consume before taking this reading?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF2D4356),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _selectedConsumptionItems.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'You have not recorded any items yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _selectedConsumptionItems.map((item) {
                      return Chip(
                        label: Text(item),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () {
                          setState(() {
                            _selectedConsumptionItems.remove(item);
                          });
                        },
                        backgroundColor: Colors.blue[50],
                        labelStyle: const TextStyle(color: Colors.blue),
                      );
                    }).toList(),
                  ),
            const SizedBox(height: 24),
            const Text(
              'Options',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            _buildConsumptionOptionsGrid(),
            const SizedBox(height: 20),
            _buildAddItemButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildConsumptionOptionsGrid() {
    // List of consumption options with their icons
    final consumptionOptions = [
      {'name': 'Alcohol', 'icon': Icons.wine_bar},
      {'name': 'Cigarette', 'icon': Icons.smoking_rooms},
      {'name': 'Salt', 'icon': Icons.format_color_fill},
      {'name': 'Vegetables', 'icon': Icons.spa},
      {'name': 'Fluids', 'icon': Icons.local_drink},
      {'name': 'Caffeine', 'icon': Icons.coffee},
      {'name': 'Medications', 'icon': Icons.medical_services},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.9,
      ),
      itemCount: consumptionOptions.length,
      itemBuilder: (context, index) {
        final option = consumptionOptions[index];
        final isSelected = _selectedConsumptionItems.contains(option['name']);

        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedConsumptionItems.remove(option['name']);
              } else {
                _selectedConsumptionItems.add(option['name'] as String);
              }
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? Colors.blue : Colors.blue[50]!,
                width: 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  option['icon'] as IconData,
                  color: Colors.blue,
                  size: 30,
                ),
                const SizedBox(height: 8),
                Text(
                  option['name'] as String,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.blue,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddItemButton() {
    return Center(
      child: TextButton.icon(
        onPressed: () {
          _showAddCustomItemDialog(
            title: 'Add Custom Item',
            hint: 'Enter item name',
            controller: _customConsumptionController,
            onAdd: (value) {
              if (value.isNotEmpty) {
                setState(() {
                  _selectedConsumptionItems.add(value);
                });
              }
            },
          );
        },
        icon: const Icon(
          Icons.add_circle_outline,
          color: Colors.blue,
          size: 24,
        ),
        label: const Text(
          'Item is not listed. Add it.',
          style: TextStyle(
            color: Colors.blue,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
        child: ElevatedButton(
          onPressed: _isLoading ? null : _saveDiaryEntries,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7BCAAC), // Light green color from image
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            minimumSize: const Size(double.infinity, 50),
          ),
          child: _isLoading
              ? const CircularProgressIndicator(color: Colors.white)
              : const Text(
                  'Save',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }

  // Show dialog to add a custom symptom or consumption item
  void _showAddCustomItemDialog({
    required String title,
    required String hint,
    required TextEditingController controller,
    required Function(String) onAdd,
  }) {
    controller.clear();
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                onAdd(controller.text.trim());
                Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  // Save diary entries to Firebase
  Future<void> _saveDiaryEntries() async {
    // Validate if there's something to save
    if (_selectedSymptoms.isEmpty && _selectedConsumptionItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one symptom or consumption item'),
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

      final batch = _firestore.batch();

      // Save symptoms if any are selected
      if (_selectedSymptoms.isNotEmpty) {
        for (var symptom in _selectedSymptoms) {
          final symptomsRef = _firestore.collection('symptoms').doc();
          batch.set(symptomsRef, {
            'symptom': symptom,
            'symptom_details': _symptomDetailsController.text.trim(),
            'timestamp': FieldValue.serverTimestamp(),
            'user_id': user.uid,
          });
        }
      }

      // Save consumption items if any are selected
      if (_selectedConsumptionItems.isNotEmpty) {
        for (var item in _selectedConsumptionItems) {
          final consumptionRef = _firestore.collection('consumption').doc();
          batch.set(consumptionRef, {
            'stuff_consumed': item,
            'timestamp': FieldValue.serverTimestamp(),
            'user_id': user.uid,
          });
        }
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Diary entries saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving diary entries: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
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
}