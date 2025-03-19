import 'package:flutter/material.dart';
import '../widgets/category_card.dart';
import '../screens/manual_reading.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  // Blood pressure data
  Map<String, dynamic> _latestReading = {
    'systolic': 119,
    'diastolic': 76,
    'pulse': 68,
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
            child: _buildMainContent(),
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

  Widget _buildCategorySection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
      child: Row(
        children: [
          Expanded(
            child: CategoryCard(
              icon: Icons.person,
              title: 'My Overview',
              color: Colors.white,
              iconColor: Colors.orange,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: CategoryCard(
              icon: Icons.favorite,
              title: 'Blood Pressure',
              color: const Color(0xFF1E88C7),
              iconColor: Colors.white,
              textColor: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: CategoryCard(
              icon: Icons.directions_run,
              title: 'Activity',
              color: Colors.white,
              iconColor: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildReadingsSection(),
            _buildStatusIndicator(),
            // HeartShapeDisplay(
            //   systolic: _latestReading['systolic'],
            //   diastolic: _latestReading['diastolic'],
            //   pulse: _latestReading['pulse'],
            // ),
            _buildReadingCards(), // Added reading cards here
            _buildActionButtons(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // New method to build reading cards
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

  // Helper method to build each reading card
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
                // My Diary functionality would go here
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