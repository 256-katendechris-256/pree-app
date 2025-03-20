import 'package:flutter/material.dart';
import '../widgets/category_card.dart';
import '../screens/manual_reading.dart';
import 'activity.dart';
import 'dairy.dart';
import 'overview.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  String _selectedCategory = 'Blood Pressure'; // Changed default to Blood Pressure
  bool _isNavigating = false; // Flag to prevent multiple navigation attempts

  // Blood pressure data
  Map<String, dynamic> _latestReading = {
    'systolic': 119,
    'diastolic': 76,
    'pulse': 78,
    'status': 'Optimal',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 0,
        title: const Text(
          'Dashboard',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.help_outline,
              color: Colors.white,
            ),
            onPressed: () {},
          ),
          _buildSyncButton(),
        ],
      ),
      body: Column(
        children: [
          _buildCategorySection(),
          Expanded(
            child: _getContentForSelectedCategory(),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildSyncButton() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.sync,
            color: Colors.white,
            size: 16,
          ),
          SizedBox(width: 4),
          Text(
            'Sync',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // Method to handle category selection
  void _selectCategory(String category) {
    setState(() {
      _selectedCategory = category;
    });
  }

  // Get color and text color for a category card based on selection
  Map<String, Color> _getCategoryColors(String category) {
    Color backgroundColor;
    Color textColor;
    Color iconColor;

    if (_selectedCategory == category) {
      // Selected state - use solid colors
      switch (category) {
        case 'Overview':
          backgroundColor = Colors.orange;
          break;
        case 'Blood Pressure':
          backgroundColor = Colors.blue;
          break;
        case 'Activity':
          backgroundColor = Colors.green;
          break;
        case 'Weight':
          backgroundColor = Colors.purple;
          break;
        default:
          backgroundColor = Colors.blue;
      }
      textColor = Colors.white;
      iconColor = Colors.white;
    } else {
      // Unselected state
      backgroundColor = Colors.white;
      textColor = Colors.black87;
      switch (category) {
        case 'Overview':
          iconColor = Colors.orange;
          break;
        case 'Blood Pressure':
          iconColor = Colors.blue;
          break;
        case 'Activity':
          iconColor = Colors.green;
          break;
        case 'Weight':
          iconColor = Colors.purple;
          break;
        default:
          iconColor = Colors.blue;
      }
    }

    return {
      'backgroundColor': backgroundColor,
      'textColor': textColor,
      'iconColor': iconColor,
    };
  }

  // Updated _buildCategorySection method with solid highlighting
  Widget _buildCategorySection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildCategoryCard(
              'Overview',
              Icons.person,
            ),
            const SizedBox(width: 10),
            _buildCategoryCard(
              'Blood Pressure',
              Icons.favorite,
            ),
            const SizedBox(width: 10),
            _buildCategoryCard(
              'Activity',
              Icons.directions_run,
            ),
            const SizedBox(width: 10),
            _buildCategoryCard(
              'Weight',
              Icons.monitor_weight,
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to build category cards with consistent styling
  Widget _buildCategoryCard(String title, IconData icon) {
    final colors = _getCategoryColors(title);

    return SizedBox(
      width: 100,
      child: InkWell(
        onTap: () {
          _selectCategory(title);
        },
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          color: colors['backgroundColor'],
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: colors['iconColor'],
                  size: 30,
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors['textColor'],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Render different content based on selected category
  Widget _getContentForSelectedCategory() {
    if (_selectedCategory == 'Overview' && !_isNavigating) {
      _isNavigating = true;
      // Use a post-frame callback to avoid build issues
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const HealthOverviewScreen()),
        ).then((_) {
          setState(() {
            _selectedCategory = 'Blood Pressure';
            _isNavigating = false;
          });
        });
      });
    } else if (_selectedCategory == 'Activity' && !_isNavigating) {
      _isNavigating = true;
      // Use a post-frame callback to avoid build issues
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ActivityScreen()),
        ).then((_) {
          setState(() {
            _selectedCategory = 'Blood Pressure';
            _isNavigating = false;
          });
        });
      });
    }

    // Default rendering
    switch (_selectedCategory) {
      case 'Blood Pressure':
        return _buildMainContent();
      case 'Activity':
        return Container(
          color: Colors.white,
          child: const Center(
            child: Text('Loading Activity Screen...'),
          ),
        );
      case 'Overview':
        return Container(
          color: Colors.white,
          child: const Center(
            child: Text('Loading Overview Screen...'),
          ),
        );
      case 'Weight':
        return Container(
          color: Colors.white,
          child: const Center(
            child: Text('Weight Screen is under development'),
          ),
        );
      default:
        return _buildMainContent();
    }
  }

  Widget _buildMainContent() {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildReadingsSection(),
            _buildStatusIndicator(),
            _buildReadingCards(),
            _buildActionButtons(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildReadingCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Column(
        children: [
          // First row with two cards
          Row(
            children: [
              // Systolic card
              Expanded(
                child: _buildReadingCard(
                  title: 'SYS',
                  value: _latestReading['systolic'].toString(),
                  unit: 'mmHg',
                  color: Colors.blue[700]!,
                ),
              ),
              const SizedBox(width: 15),
              // Diastolic card
              Expanded(
                child: _buildReadingCard(
                  title: 'DIA',
                  value: _latestReading['diastolic'].toString(),
                  unit: 'mmHg',
                  color: Colors.blue[700]!,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          // Second row with centered pulse card
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.45,
            child: _buildReadingCard(
              title: 'PULSE',
              value: _latestReading['pulse'].toString(),
              unit: 'bpm',
              color: Colors.red[400]!,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadingCard({
    required String title,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withOpacity(0.3), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  unit,
                  style: TextStyle(
                    color: color.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadingsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                const Text(
                  'Morning',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildReadingIcon(Colors.blue[300]!, false),
                    const SizedBox(width: 10),
                    _buildReadingIcon(Colors.blue[300]!, false),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  '2 more readings needed',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 60,
            color: Colors.grey[300],
          ),
          Expanded(
            child: Column(
              children: [
                const Text(
                  'Evening',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildReadingIcon(Colors.blue[700]!, true),
                    const SizedBox(width: 10),
                    _buildReadingIcon(Colors.blue[300]!, false),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '1 more readings needed',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(
                      Icons.edit,
                      size: 16,
                      color: Colors.blue[700],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadingIcon(Color color, bool checked) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
      child: Center(
        child: checked
            ? Icon(Icons.check, color: color, size: 18)
            : Icon(Icons.favorite_border, color: color, size: 18),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 80),
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: Colors.green,
            borderRadius: BorderRadius.circular(5),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Optimal',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 5),
          child: Text(
            'Per ESH guidelines',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () async {
                // Navigate to manual reading page
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ManualReadingScreen()),
                );

                // Process result if available
                if (result != null && result is Map<String, dynamic>) {
                  setState(() {
                    _latestReading = {
                      'systolic': result['systolic'],
                      'diastolic': result['diastolic'],
                      'pulse': result['pulse'],
                      'status': _calculateStatus(result['systolic'], result['diastolic']),
                    };
                  });

                  // Show confirmation
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reading saved successfully')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Manual Reading',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                // Navigate to My Diary screen
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const MyDiaryScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              icon: const Icon(Icons.edit_note, color: Colors.white),
              label: const Text(
                'My Diary',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      selectedItemColor: Colors.blue[700],
      unselectedItemColor: Colors.grey,
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Dashboard',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.history),
          label: 'History',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.notifications),
          label: 'My Reminders',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'Profile',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.more_horiz),
          label: 'More',
        ),
      ],
      onTap: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
    );
  }

  // Helper function to calculate blood pressure status
  String _calculateStatus(int systolic, int diastolic) {
    if (systolic < 120 && diastolic < 80) {
      return 'Optimal';
    } else if ((systolic >= 120 && systolic < 130) && diastolic < 80) {
      return 'Normal';
    } else if ((systolic >= 130 && systolic < 140) || (diastolic >= 80 && diastolic < 90)) {
      return 'High Normal';
    } else if ((systolic >= 140 && systolic < 160) || (diastolic >= 90 && diastolic < 100)) {
      return 'Grade 1';
    } else if ((systolic >= 160 && systolic < 180) || (diastolic >= 100 && diastolic < 110)) {
      return 'Grade 2';
    } else {
      return 'Grade 3';
    }
  }
}