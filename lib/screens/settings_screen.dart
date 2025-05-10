import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

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
    'user_id': '', // Add this for storing user ID
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
  
  // For copy success message
  bool _showCopySuccess = false;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize tab controller
    _tabController = TabController(length: 3, vsync: this); // Changed to 3 for the new Device tab
    
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


      }
      
      String userId = currentUser.uid;

      // Store the user ID
      setState(() {
        _userData['user_id'] = userId;
      });
      
      // Load user data
      DocumentSnapshot userDoc = await _firestore.collection('user').doc(userId).get();
      
      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        
        setState(() {
          _userData = {
            'user_id': userId, // Keep the user ID
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
        'is_currently_pregnant': _userData['is_currently_pregnant'],
        'has_had_hypertension': _userData['has_had_hypertension'],
        'pregnancy_count': _userData['pregnancy_count'],
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

  void _copyUserIdToClipboard() {
    Clipboard.setData(ClipboardData(text: _userData['user_id']));
    setState(() {
      _showCopySuccess = true;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('User ID copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
    
    // Hide the success message after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showCopySuccess = false;
        });
      }
    });
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
            Tab(text: 'Device'),
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
              _buildDeviceTab(),
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
  
  Widget _buildDeviceTab() {
  // Mask the user ID with asterisks, but keep first 4 and last 4 characters visible
  String userId = _userData['user_id'];
  String maskedUserId = userId;
  
  if (userId.length > 8) {
    String firstFour = userId.substring(0, 4);
    String lastFour = userId.substring(userId.length - 4);
    String middle = '*' * (userId.length - 8);
    maskedUserId = '$firstFour$middle$lastFour';
  }
  
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
                  'Device Pairing',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Use this ID to pair your monitoring devices with your account. Tap the button to copy your ID.',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                
                // User ID display and copy field
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            maskedUserId,
                            style: const TextStyle(
                              fontSize: 16,
                              fontFamily: 'Courier',
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          border: Border(
                            left: BorderSide(color: Colors.grey),
                          ),
                        ),
                        child: IconButton(
                          icon: _showCopySuccess 
                            ? const Icon(Icons.check, color: Colors.green)
                            : const Icon(Icons.copy, color: Colors.indigo),
                          onPressed: _copyUserIdToClipboard,
                          tooltip: 'Copy User ID',
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Image or illustration for device pairing
                Container(
                  width: double.infinity,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.bluetooth_connected,
                          size: 60,
                          color: Colors.indigo[300],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Device Pairing',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Device pairing instructions
                Text(
                  'How to pair your device:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 10),
                _buildInstructionStep(
                  '1',
                  'Turn on your monitoring device and ensure it is in pairing mode.',
                ),
                _buildInstructionStep(
                  '2',
                  'Copy your user ID by tapping the copy button above.',
                ),
                _buildInstructionStep(
                  '3',
                  'Open the device companion app and paste your user ID when prompted.',
                ),
                _buildInstructionStep(
                  '4',
                  'Follow the instructions in the companion app to complete pairing.',
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Paired devices section
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
                  'Paired Devices',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Example paired device item
                _buildPairedDeviceItem(
                  'BP Monitor',
                  'Last synced: Today, 10:30 AM',
                  Icons.favorite,
                  Colors.red,
                ),
                const Divider(),
                _buildPairedDeviceItem(
                  'Activity Tracker',
                  'Last synced: Yesterday, 8:15 PM',
                  Icons.directions_walk,
                  Colors.green,
                ),
                const Divider(),
                _buildPairedDeviceItem(
                  'Temperature Sensor',
                  'Last synced: 2 days ago',
                  Icons.thermostat,
                  Colors.orange,
                ),
                
                const SizedBox(height: 20),
                
                // Button to add new device
                Center(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Looking for new devices...'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                    label: const Text(
                      'Add New Device',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Troubleshooting section
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
                  'Troubleshooting',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.help_outline, color: Colors.orange),
                  ),
                  title: const Text('Having trouble with your device?'),
                  subtitle: const Text('View our troubleshooting guide'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Opening troubleshooting guide...'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.support_agent, color: Colors.blue),
                  ),
                  title: const Text('Contact Support'),
                  subtitle: const Text('Get help from our support team'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Opening support contact form...'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildInstructionStep(String number, String instruction) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Colors.indigo,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            instruction,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildPairedDeviceItem(String name, String status, IconData icon, Color color) {
  return Row(
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: color,
          size: 24,
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              status,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      PopupMenuButton(
        icon: const Icon(Icons.more_vert),
        onSelected: (value) {
          if (value == 'sync') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Syncing $name...')),
            );
          } else if (value == 'settings') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Opening $name settings...')),
            );
          } else if (value == 'remove') {
            // Show confirmation dialog
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Remove $name?'),
                content: const Text('Are you sure you want to unpair this device? You will need to pair it again to use it.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$name unpaired successfully')),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            );
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'sync',
            child: Row(
              children: [
                Icon(Icons.sync, size: 18),
                SizedBox(width: 8),
                Text('Sync Now'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'settings',
            child: Row(
              children: [
                Icon(Icons.settings, size: 18),
                SizedBox(width: 8),
                Text('Device Settings'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'remove',
            child: Row(
              children: [
                Icon(Icons.link_off, size: 18),
                SizedBox(width: 8),
                Text('Unpair Device'),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}