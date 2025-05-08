import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../screens/dashboard.dart';
import '../screens/insight_screen.dart';
import '../widgets/bottom_nav_bar.dart'; // Adjust path
import 'reports_screen.dart';



class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with TickerProviderStateMixin {
  // Firebase instances
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Selected index for bottom navigation
  int _selectedNavIndex = 3; // Set to 3 for Settings tab
  
  // Loading state
  bool _isLoading = true;
  
  // User data
  Map<String, dynamic> _userData = {
    'full_name': '',
    'email': '',
    'phone_number': '',
    'date_of_birth': '',
    'gender': 'Female',
    'is_currently_pregnant': false,
    'has_had_hypertension': false,
    'pregnancy_count': 0,
  };
  
  // Next of kin data
  Map<String, dynamic> _nextOfKinData = {
    'kin_name': '',
    'kin_relationship': '',
    'kin_contact': '',
    'kin_email': '',
    'kin_address': '',
  };
  
  // Controllers for user data
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _dobController;
  
  // Controllers for next of kin data
  late TextEditingController _kinNameController;
  late TextEditingController _kinRelationshipController;
  late TextEditingController _kinContactController;
  late TextEditingController _kinEmailController;
  late TextEditingController _kinAddressController;
  
  // TabController for sections
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize tab controller
    _tabController = TabController(length: 2, vsync: this);
    
    // Initialize controllers with empty values
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _dobController = TextEditingController();
    
    _kinNameController = TextEditingController();
    _kinRelationshipController = TextEditingController();
    _kinContactController = TextEditingController();
    _kinEmailController = TextEditingController();
    _kinAddressController = TextEditingController();
    
    // Load user data
    _loadUserData();
  }
  
  @override
  void dispose() {
    // Dispose controllers
    _nameController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    
    _kinNameController.dispose();
    _kinRelationshipController.dispose();
    _kinContactController.dispose();
    _kinEmailController.dispose();
    _kinAddressController.dispose();
    
    _tabController.dispose();
    
    super.dispose();
  }
  
  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Get current user
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        // Handle not logged in state
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to view your settings')),
        );
        return;
      }
      
      String userId = currentUser.uid;
      
      // Load user data
      DocumentSnapshot userDoc = await _firestore.collection('user').doc(userId).get();
      
      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        
        setState(() {
          _userData = {
            'full_name': userData['full_name'] ?? '',
            'email': userData['email'] ?? '',
            'phone_number': userData['phone_number'] ?? '',
            'date_of_birth': userData['date_of_birth'] ?? '',
            'gender': userData['gender'] ?? 'Female',
            'is_currently_pregnant': userData['is_currently_pregnant'] ?? false,
            'has_had_hypertension': userData['has_had_hypertension'] ?? false,
            'pregnancy_count': userData['pregnancy_count'] ?? 0,
          };
        });
        
        // Set controller values
        _nameController.text = _userData['full_name'];
        _phoneController.text = _userData['phone_number'];
        _dobController.text = _userData['date_of_birth'];
      }
      
      // Load next of kin data
      QuerySnapshot nextOfKinSnapshot = await _firestore
          .collection('next_of_kin')
          .where('user_id', isEqualTo: userId)
          .limit(1)
          .get();
      
      if (nextOfKinSnapshot.docs.isNotEmpty) {
        Map<String, dynamic> kinData = nextOfKinSnapshot.docs.first.data() as Map<String, dynamic>;
        
        setState(() {
          _nextOfKinData = {
            'id': nextOfKinSnapshot.docs.first.id, // Save document ID for updates
            'kin_name': kinData['kin_name'] ?? '',
            'kin_relationship': kinData['kin_relationship'] ?? '',
            'kin_contact': kinData['kin_contact'] ?? '',
            'kin_email': kinData['kin_email'] ?? '',
            'kin_address': kinData['kin_address'] ?? '',
          };
        });
        
        // Set controller values
        _kinNameController.text = _nextOfKinData['kin_name'];
        _kinRelationshipController.text = _nextOfKinData['kin_relationship'];
        _kinContactController.text = _nextOfKinData['kin_contact'];
        _kinEmailController.text = _nextOfKinData['kin_email'];
        _kinAddressController.text = _nextOfKinData['kin_address'];
      }
      
      setState(() {
        _isLoading = false;
      });
      
    } catch (e) {
      print('Error loading user data: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  Future<void> _updateUserProfile() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }
      
      // Update user data
      await _firestore.collection('user').doc(currentUser.uid).update({
        'full_name': _nameController.text.trim(),
        'phone_number': _phoneController.text.trim(),
        'date_of_birth': _dobController.text.trim(),
      });
      
      // Update state
      setState(() {
        _userData['full_name'] = _nameController.text.trim();
        _userData['phone_number'] = _phoneController.text.trim();
        _userData['date_of_birth'] = _dobController.text.trim();
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
    } catch (e) {
      print('Error updating user profile: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating profile: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _updateNextOfKin() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }
      
      // Update data to save
      Map<String, dynamic> kinData = {
        'kin_name': _kinNameController.text.trim(),
        'kin_relationship': _kinRelationshipController.text.trim(),
        'kin_contact': _kinContactController.text.trim(),
        'kin_email': _kinEmailController.text.trim(),
        'kin_address': _kinAddressController.text.trim(),
        'user_id': currentUser.uid,
        'timestamp': FieldValue.serverTimestamp(),
      };
      
      if (_nextOfKinData.containsKey('id')) {
        // Update existing next of kin document
        await _firestore.collection('next_of_kin').doc(_nextOfKinData['id']).update(kinData);
      } else {
        // Create new next of kin document
        DocumentReference docRef = await _firestore.collection('next_of_kin').add(kinData);
        _nextOfKinData['id'] = docRef.id;
      }
      
      // Update state
      setState(() {
        _nextOfKinData['kin_name'] = _kinNameController.text.trim();
        _nextOfKinData['kin_relationship'] = _kinRelationshipController.text.trim();
        _nextOfKinData['kin_contact'] = _kinContactController.text.trim();
        _nextOfKinData['kin_email'] = _kinEmailController.text.trim();
        _nextOfKinData['kin_address'] = _kinAddressController.text.trim();
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Next of kin information updated successfully')),
      );
    } catch (e) {
      print('Error updating next of kin: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating next of kin: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  void _selectBirthDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 18)), // 18 years ago
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.indigo,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        _dobController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Profile'),
            Tab(text: 'Next of Kin'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadUserData,
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
        : TabBarView(
            controller: _tabController,
            children: [
              _buildProfileTab(),
              _buildNextOfKinTab(),
            ],
          ),
      bottomNavigationBar: BottomNavBar(
        selectedIndex: _selectedNavIndex,
        onItemTapped: (index) {
          if (index == _selectedNavIndex) {
            return; // Already on Dashboard screen
          }
          setState(() {
            _selectedNavIndex = index;
          });
          switch (index) {
            case 0: // Home
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const DashboardScreen()),
              );
              break;
            case 1: // Reports
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const ReportsScreen()),
              );
              break;
            case 2: // Insights
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const InsightsScreen()),
              );
              break;
            case 3: // Settings
              break;
          }
        },
      ),
    );
  }
  
  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildUserHeaderCard(),
          const SizedBox(height: 16),
          _buildProfileDetailsCard(),
          const SizedBox(height: 16),
          _buildHealthInformationCard(),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _updateUserProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Save Changes',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildUserHeaderCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.indigo[100],
              child: Text(
                _userData['full_name'].isNotEmpty 
                  ? _userData['full_name'][0].toUpperCase() 
                  : '?',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _userData['full_name'].isNotEmpty 
                      ? _userData['full_name'] 
                      : 'No Name Set',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _userData['email'],
                    style: TextStyle(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _userData['gender'],
                      style: const TextStyle(
                        color: Colors.indigo,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildProfileDetailsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Basic Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                prefixIcon: Icon(Icons.person, color: Colors.indigo),
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.indigo),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: Icon(Icons.phone, color: Colors.indigo),
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.indigo),
                ),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _selectBirthDate,
              child: AbsorbPointer(
                child: TextField(
                  controller: _dobController,
                  decoration: const InputDecoration(
                    labelText: 'Date of Birth',
                    prefixIcon: Icon(Icons.calendar_today, color: Colors.indigo),
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.indigo),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Email (cannot be changed): ${_userData['email']}',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHealthInformationCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Health Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Currently Pregnant'),
              value: _userData['is_currently_pregnant'],
              activeColor: Colors.indigo,
              contentPadding: EdgeInsets.zero,
              onChanged: (value) {
                setState(() {
                  _userData['is_currently_pregnant'] = value;
                });
              },
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('History of Hypertension'),
              value: _userData['has_had_hypertension'],
              activeColor: Colors.indigo,
              contentPadding: EdgeInsets.zero,
              onChanged: (value) {
                setState(() {
                  _userData['has_had_hypertension'] = value;
                });
              },
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Pregnancy Count:'),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () {
                        if (_userData['pregnancy_count'] > 0) {
                          setState(() {
                            _userData['pregnancy_count']--;
                          });
                        }
                      },
                    ),
                    Text(
                      '${_userData['pregnancy_count']}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () {
                        setState(() {
                          _userData['pregnancy_count']++;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildNextOfKinTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Next of Kin Information',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please provide details of your emergency contact person',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _kinNameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: Icon(Icons.person, color: Colors.indigo),
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.indigo),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _kinRelationshipController,
                    decoration: const InputDecoration(
                      labelText: 'Relationship',
                      prefixIcon: Icon(Icons.people, color: Colors.indigo),
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.indigo),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _kinContactController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      prefixIcon: Icon(Icons.phone, color: Colors.indigo),
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.indigo),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _kinEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: Icon(Icons.email, color: Colors.indigo),
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.indigo),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _kinAddressController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Physical Address',
                      prefixIcon: Icon(Icons.home, color: Colors.indigo),
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.indigo),
                      ),
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _updateNextOfKin,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Save Next of Kin Information',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  
}