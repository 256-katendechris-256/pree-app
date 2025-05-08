import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../screens/manual_reading.dart';
import '../screens/manual_reading_weight.dart';
import '../screens/activity.dart';
import '../screens/diary.dart';
import '../screens/overview.dart';
import '../screens/weight.dart';
import '../widgets/bottom_nav_bar.dart'; // Adjust path
import 'reports_screen.dart';
import 'insight_screen.dart';
import 'settings_screen.dart';


class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  int _selectedNavIndex = 0;
  String _selectedCategory = 'Blood Pressure';
  bool _isNavigating = false;
  bool _isLoading = true;
  late TabController _tabController;

  // Firebase instances
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Weekly blood pressure data
  List<Map<String, dynamic>> _weeklyReadings = [];

  // Current reading
  Map<String, dynamic> _latestReading = {
    'systolic': 0,
    'diastolic': 0,
    'pulse': 0,
    'status': 'Loading...',
    'timestamp': '8:22 AM',
    'date': 'Today'
  };

  // Activity data

  // Weight data

  @override
  void initState() {
    super.initState();
    // Initialize TabController with 4 tabs
    _tabController = TabController(length: 4, vsync: this);

    // Add listener to handle tab changes
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          switch (_tabController.index) {
            case 0:
              _selectedCategory = 'Blood Pressure';
              break;
            case 1:
              _selectedCategory = 'Activity';
              break;
            case 2:
              _selectedCategory = 'Weight';
              break;
            case 3:
              _selectedCategory = 'Overview';
              break;
          }
        });
      }
    });

    // Load data from Firebase
    _loadFirebaseData();
  }

  Future<void> _loadFirebaseData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get current user
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        // Handle not logged in state
        _loadMockData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to view your data')),
        );
        return;
      }

      String userId = currentUser.uid;

      // Load vital signs data
      await _loadVitalSignsData(userId);

      // Load activity data
      await _loadActivityData(userId);

      // Load weight data
      await _loadWeightData(userId);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading data: $e');
      _loadMockData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  Future<void> _loadVitalSignsData(String userId) async {
    try {
      // Get latest vital signs reading
      var latestReadingDoc = await _firestore
          .collection('vital_signs')
          .where('user_id', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (latestReadingDoc.docs.isNotEmpty) {
        var data = latestReadingDoc.docs.first.data();
        
        // Extract values with proper null handling
        int systolic = data['systolic_BP'] ?? 0;
        int diastolic = data['diastolic'] ?? 0;
        int pulse = data['pulse'] ?? 0;
        String time = data['time'] ?? '8:22 AM';
        String date = data['date'] ?? 'Today';
        
        // Calculate status
        String status = _calculateStatus(systolic, diastolic);
        
        if (mounted) {
          setState(() {
            _latestReading = {
              'systolic': systolic,
              'diastolic': diastolic,
              'pulse': pulse,
              'status': status,
              'timestamp': time,
              'date': date,
            };
          });
        }
      }

      // Get last 7 days of readings for chart
      var weeklyReadingsDoc = await _firestore
          .collection('vital_signs')
          .where('user_id', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(7)
          .get();

      if (weeklyReadingsDoc.docs.isNotEmpty) {
        List<Map<String, dynamic>> readings = [];
        
        for (var doc in weeklyReadingsDoc.docs) {
          var data = doc.data();
          
          // Extract date from timestamp for day display
          Timestamp timestamp = data['timestamp'];
          DateTime date = timestamp.toDate();
          String day = DateFormat('E').format(date); // Day of week abbreviation
          
          readings.add({
            'day': day,
            'systolic': data['systolic_BP'] ?? 0,
            'diastolic': data['diastolic'] ?? 0,
            'timestamp': timestamp,
          });
        }
        
        // Sort by timestamp ascending for chart display
        readings.sort((a, b) {
          Timestamp aTime = a['timestamp'];
          Timestamp bTime = b['timestamp'];
          return aTime.compareTo(bTime);
        });
        
        if (mounted) {
          setState(() {
            _weeklyReadings = readings;
          });
        }
      } else {
        // Use mock data if no readings found
        if (mounted) {
          setState(() {
            _weeklyReadings = [
              {'day': 'Mon', 'systolic': 122, 'diastolic': 78},
              {'day': 'Tue', 'systolic': 119, 'diastolic': 76},
              {'day': 'Wed', 'systolic': 121, 'diastolic': 75},
              {'day': 'Thu', 'systolic': 118, 'diastolic': 74},
              {'day': 'Fri', 'systolic': 120, 'diastolic': 77},
              {'day': 'Sat', 'systolic': 117, 'diastolic': 75},
              {'day': 'Sun', 'systolic': 119, 'diastolic': 76},
            ];
          });
        }
      }
    } catch (e) {
      print('Error loading vital signs: $e');
      throw e;
    }
  }

  Future<void> _loadActivityData(String userId) async {
    try {
      // Get latest activity data
      var latestActivityDoc = await _firestore
          .collection('activity')
          .where('user_id', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (latestActivityDoc.docs.isNotEmpty) {
        var data = latestActivityDoc.docs.first.data();
        
        // Parse values, handling potential string values
        int steps = int.tryParse(data['steps'] ?? '0') ?? 0;
        int calories = int.tryParse(data['calories'] ?? '0') ?? 0;
        double distance = double.tryParse(data['distance'] ?? '0.0') ?? 0.0;
        int activeMinutes = int.tryParse(data['active_minutes'] ?? '0') ?? 0;
        
        if (mounted) {
          setState(() {
          });
        }
      }
    } catch (e) {
      print('Error loading activity data: $e');
      throw e;
    }
  }

  Future<void> _loadWeightData(String userId) async {
    try {
      // Get latest weight data
      var latestWeightDoc = await _firestore
          .collection('weight')
          .where('user_id', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (latestWeightDoc.docs.isNotEmpty) {
        var data = latestWeightDoc.docs.first.data();
        
        // Parse values with proper handling
        double weight = double.tryParse(data['weight'] ?? '0.0') ?? 0.0;
        double bmi = double.tryParse(data['current'] ?? '0.0') ?? 0.0;
        String status = data['status'] ?? 'Unknown';
        String change = data['change'] ?? '+0.0';
        Timestamp timestamp = data['timestamp'];
        
        if (mounted) {
          setState(() {
          });
        }
      }
    } catch (e) {
      print('Error loading weight data: $e');
      throw e;
    }
  }

  void _loadMockData() {
    if (mounted) {
      setState(() {
        // Mock BP data
        _latestReading = {
          'systolic': 119,
          'diastolic': 76,
          'pulse': 68,
          'status': 'Optimal',
          'timestamp': '8:22 AM',
          'date': 'Today'
        };
        
        _weeklyReadings = [
          {'day': 'Mon', 'systolic': 122, 'diastolic': 78},
          {'day': 'Tue', 'systolic': 119, 'diastolic': 76},
          {'day': 'Wed', 'systolic': 121, 'diastolic': 75},
          {'day': 'Thu', 'systolic': 118, 'diastolic': 74},
          {'day': 'Fri', 'systolic': 120, 'diastolic': 77},
          {'day': 'Sat', 'systolic': 117, 'diastolic': 75},
          {'day': 'Sun', 'systolic': 119, 'diastolic': 76},
        ];
        
        // Mock activity data
        
        // Mock weight data
        
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        elevation: 0,
        title: const Text(
          'Health Monitor',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: () {
              _loadFirebaseData();
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Syncing data...'))
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCategoryTabs(),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
              : _getContentForSelectedCategory(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.indigo,
        onPressed: () => _addNewEntry(),
        child: const Icon(Icons.add, color: Colors.white),
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
              // Stay on this screen
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
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
              break;
          }
        },
      ),
    );
  }

  // Handle different add actions based on selected category
  void _addNewEntry() {
    switch (_selectedCategory) {
      case 'Blood Pressure':
        _addNewReading();
        break;
      case 'Weight':
        _addNewWeight();
        break;
      case 'Activity':
        // Would implement manual activity entry
        break;
      default:
        _addNewReading();
    }
  }

  void _addNewWeight() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to add weight data')),
        );
        return;
      }

      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ManualWeightScreen()),
      );

      if (result == true) {
        // Refresh data when returning from weight screen
        _loadWeightData(currentUser.uid);
      }
    } catch (e) {
      print('Error adding weight: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding weight: $e')),
      );
    }
  }

  Widget _buildCategoryTabs() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorColor: Colors.indigo,
        indicatorWeight: 3,
        labelColor: Colors.indigo,
        unselectedLabelColor: Colors.grey[600],
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        tabs: [
          Tab(
            icon: Icon(
              Icons.favorite,
              color: _selectedCategory == 'Blood Pressure' ? Colors.indigo : Colors.grey[600],
            ),
            text: 'Blood Pressure',
          ),
          Tab(
            icon: Icon(
              Icons.directions_run,
              color: _selectedCategory == 'Activity' ? Colors.indigo : Colors.grey[600],
            ),
            text: 'Activity',
          ),
          Tab(
            icon: Icon(
              Icons.monitor_weight,
              color: _selectedCategory == 'Weight' ? Colors.indigo : Colors.grey[600],
            ),
            text: 'Weight',
          ),
          Tab(
            icon: Icon(
              Icons.dashboard,
              color: _selectedCategory == 'Overview' ? Colors.indigo : Colors.grey[600],
            ),
            text: 'Overview',
          ),
        ],
      ),
    );
  }

  // Render different content based on selected category
  Widget _getContentForSelectedCategory() {
    if (_selectedCategory == 'Overview' && !_isNavigating) {
      _isNavigating = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const HealthOverviewScreen()),
        ).then((_) {
          setState(() {
            _selectedCategory = 'Blood Pressure';
            _isNavigating = false;
            _tabController.animateTo(0); // Reset tab selection
          });
        });
      });
    }
    else if (_selectedCategory == 'Weight' && !_isNavigating) {
      _isNavigating = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const WeightScreen()),
        ).then((_) {
          setState(() {
            _selectedCategory = 'Blood Pressure';
            _isNavigating = false;
            _tabController.animateTo(0); // Reset tab selection
          });
        });
      });
    }


    else if (_selectedCategory == 'Activity' && !_isNavigating) {
      _isNavigating = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ActivityScreen()),
        ).then((_) {
          setState(() {
            _selectedCategory = 'Blood Pressure';
            _isNavigating = false;
            _tabController.animateTo(0); // Reset tab selection
            _loadFirebaseData(); // Refresh data when returning
          });
        });
      });
    }
    
    else if (_selectedCategory == 'Weight' && !_isNavigating) {
      _isNavigating = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const WeightScreen()),
        ).then((_) {
          setState(() {
            _selectedCategory = 'Blood Pressure';
            _isNavigating = false;
            _tabController.animateTo(0); // Reset tab selection
            _loadFirebaseData(); // Refresh data when returning
          });
        });
      });
    }

    switch (_selectedCategory) {
      case 'Blood Pressure':
        return _buildBpContent();
      case 'Activity':
        return Container(
          color: Colors.white,
          child: const Center(
            child: CircularProgressIndicator(color: Colors.indigo),
          ),
        );
      case 'Overview':
        return Container(
          color: Colors.white,
          child: const Center(
            child: CircularProgressIndicator(color: Colors.indigo),
          ),
        );
      case 'Weight':
        return Container(
          color: Colors.white,
          child: const Center(
            child: CircularProgressIndicator(color: Colors.indigo),
          ),
        );
      default:
        return _buildBpContent();
    }
  }

  Widget _buildBpContent() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusCard(),
          _buildLatestReadingCard(),
          _buildWeeklyChart(),
          _buildReadingsList(),
          _buildActionButtons(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final statusColors = {
      'Optimal': Colors.green,
      'Normal': Colors.blue,
      'High Normal': Colors.orange,
      'Grade 1': Colors.amber[700],
      'Grade 2': Colors.deepOrange,
      'Grade 3': Colors.red
    };

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColors[_latestReading['status']] ?? Colors.green,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _latestReading['status'],
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Last updated: ${_latestReading['timestamp']} ${_latestReading['date']}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Per ESH guidelines',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLatestReadingCard() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              'Latest Reading',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildReadingItem('Systolic', '${_latestReading['systolic']}', 'mmHg', Colors.indigo),
                _buildReadingItem('Diastolic', '${_latestReading['diastolic']}', 'mmHg', Colors.indigo),
                _buildReadingItem('Pulse', '${_latestReading['pulse']}', 'bpm', Colors.redAccent),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadingItem(String title, String value, String unit, Color color) {
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              unit,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWeeklyChart() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Weekly Trends',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.calendar_month, size: 16),
                  label: const Text('View More'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 200,
              padding: const EdgeInsets.only(right: 16, top: 16),
              child: _weeklyReadings.isEmpty 
                ? const Center(child: Text('No data available'))
                : LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: false),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            if (value.toInt() >= 0 && value.toInt() < _weeklyReadings.length) {
                              return Text(
                                _weeklyReadings[value.toInt()]['day'],
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 10,
                                ),
                              );
                            }
                            return const Text('');
                          },
                          reservedSize: 22,
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            if (value % 20 == 0) {
                              return Text(
                                '${value.toInt()}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 10,
                                ),
                              );
                            }
                            return const Text('');
                          },
                          reservedSize: 30,
                        ),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      // Systolic line
                      LineChartBarData(
                        spots: List.generate(_weeklyReadings.length, (index) {
                          return FlSpot(index.toDouble(), _weeklyReadings[index]['systolic'].toDouble());
                        }),
                        isCurved: true,
                        color: Colors.indigo,
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: Colors.indigo.withOpacity(0.1),
                        ),
                      ),
                      // Diastolic line
                      LineChartBarData(
                        spots: List.generate(_weeklyReadings.length, (index) {
                          return FlSpot(index.toDouble(), _weeklyReadings[index]['diastolic'].toDouble());
                        }),
                        isCurved: true,
                        color: Colors.blue,
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: Colors.blue.withOpacity(0.1),
                        ),
                      ),
                    ],
                    minY: 60,
                    maxY: 140,
                  ),
                ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('Systolic', Colors.indigo),
                const SizedBox(width: 20),
                _buildLegendItem('Diastolic', Colors.blue),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildReadingsList() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Readings Needed Today',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline, color: Colors.grey),
                  onPressed: () {},
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildTimeOfDayReadings(
                    title: 'Morning',
                    completed: 0,
                    total: 2,
                  ),
                ),
                Container(
                  height: 80,
                  width: 1,
                  color: Colors.grey[300],
                ),
                Expanded(
                  child: _buildTimeOfDayReadings(
                    title: 'Evening',
                    completed: 1,
                    total: 2,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeOfDayReadings({
    required String title,
    required int completed,
    required int total,
  }) {
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(total, (index) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: index < completed ? Colors.indigo : Colors.grey[400]!,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Icon(
                    index < completed ? Icons.check : Icons.favorite_border,
                    size: 18,
                    color: index < completed ? Colors.indigo : Colors.grey[400],
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        Text(
          '${total - completed} more ${(total - completed) == 1 ? 'reading' : 'readings'} needed',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _addNewReading(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add Reading',
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
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const MyDiaryScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Colors.indigo),
                ),
              ),
              icon: const Icon(Icons.book, color: Colors.indigo),
              label: const Text(
                'My Diary',
                style: TextStyle(
                  color: Colors.indigo,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addNewReading() async {
    try {
      // Check if user is authenticated
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to add readings')),
        );
        return;
      }
      
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ManualReadingScreen()),
      );

      if (result != null && result is Map<String, dynamic>) {
        // Calculate status
        String status = _calculateStatus(result['systolic'], result['diastolic']);
        
        // Get current date and time formatted
        final now = DateTime.now();
        final dateStr = DateFormat('dd/MM/yyyy').format(now);
        final timeStr = DateFormat('h:mm a').format(now);
        
        // Create Firestore document
        await _firestore.collection('vital_signs').add({
          'systolic_BP': result['systolic'],
          'diastolic': result['diastolic'],
          'pulse': result['pulse'],
          'temperature': '',
          'date': dateStr,
          'time': timeStr,
          'timestamp': now,
          'user_id': currentUser.uid,
        });

        // Update local state
        setState(() {
          _latestReading = {
            'systolic': result['systolic'],
            'diastolic': result['diastolic'],
            'pulse': result['pulse'],
            'status': status,
            'timestamp': timeStr,
            'date': 'Today'
          };
        });
        
        // Refresh data to update weekly chart
        _loadVitalSignsData(currentUser.uid);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reading saved successfully')),
        );
      }
    } catch (e) {
      print('Error adding reading: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving reading: $e')),
      );
    }
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