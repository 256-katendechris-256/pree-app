import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'overview.dart';
// Import DashboardScreen
import '../screens/insight_screen.dart';
import '../widgets/bottom_nav_bar.dart'; // Adjust path
import 'reports_screen.dart';
import 'settings_screen.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> with TickerProviderStateMixin {
  int _selectedNavIndex = 0;
  String _selectedCategory = 'Activity';
  bool _isNavigating = false;
  bool _isLoading = true;
  late TabController _tabController;

  // Firebase instances
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Activity data
  Map<String, dynamic> _activityData = {
    'steps': 0,
    'calories': 0,
    'distance': 0.0,
    'active_minutes': 0,
    'goal': 10000,
  };

  // Weekly activity data
  List<Map<String, dynamic>> _weeklyActivity = [];

  @override
  void initState() {
    super.initState();
    // Initialize TabController with 4 tabs
    _tabController = TabController(length: 4, vsync: this);
    _tabController.index = 1; // Set Activity tab selected by default

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

    // Load activity data from Firebase
    _loadActivityData();
  }

  Future<void> _loadActivityData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get current user
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        // Handle not logged in state
        _loadMockActivityData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to view your activity data')),
        );
        return;
      }

      String userId = currentUser.uid;

      // Load latest activity data
      await _fetchLatestActivity(userId);

      // Load weekly activity data
      await _fetchWeeklyActivity(userId);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading activity data: $e');
      _loadMockActivityData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading activity data: $e')),
        );
      }
    }
  }

  Future<void> _fetchLatestActivity(String userId) async {
    try {
      // Get latest activity entry
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
        
        // Get stored goal or use default
        var userDoc = await _firestore
            .collection('users')
            .doc(userId)
            .get();
            
        int goal = 10000; // Default goal
        if (userDoc.exists) {
          goal = userDoc.data()?['step_goal'] ?? 10000;
        }
        
        if (mounted) {
          setState(() {
            _activityData = {
              'steps': steps,
              'calories': calories,
              'distance': distance,
              'active_minutes': activeMinutes,
              'goal': goal,
            };
          });
        }
      }
    } catch (e) {
      print('Error fetching latest activity: $e');
      throw e;
    }
  }

  Future<void> _fetchWeeklyActivity(String userId) async {
    try {
      // Calculate date for 7 days ago
      DateTime sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      
      // Get last 7 days of activity data
      var weeklyActivityDocs = await _firestore
          .collection('activity')
          .where('user_id', isEqualTo: userId)
          .where('timestamp', isGreaterThanOrEqualTo: sevenDaysAgo)
          .orderBy('timestamp', descending: true)
          .limit(7)
          .get();

      if (weeklyActivityDocs.docs.isNotEmpty) {
        List<Map<String, dynamic>> weekActivity = [];
        
        // Create a map to store activity by day
        Map<String, Map<String, dynamic>> activityByDay = {};
        
        for (var doc in weeklyActivityDocs.docs) {
          var data = doc.data();
          
          // Extract date from timestamp for day grouping
          Timestamp timestamp = data['timestamp'];
          DateTime date = timestamp.toDate();
          String day = DateFormat('E').format(date); // Day of week abbreviation
          
          // Parse values
          int steps = int.tryParse(data['steps'] ?? '0') ?? 0;
          int calories = int.tryParse(data['calories'] ?? '0') ?? 0;
          double distance = double.tryParse(data['distance'] ?? '0.0') ?? 0.0;
          
          // Group by day (taking the latest entry for each day)
          if (!activityByDay.containsKey(day)) {
            activityByDay[day] = {
              'day': day,
              'steps': steps,
              'calories': calories,
              'distance': distance,
              'timestamp': timestamp,
            };
          }
        }
        
        // Convert map to list
        weekActivity = activityByDay.values.toList();
        
        // Sort by day of week
        final daysOfWeek = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        weekActivity.sort((a, b) {
          return daysOfWeek.indexOf(a['day']) - daysOfWeek.indexOf(b['day']);
        });
        
        // If we don't have all 7 days, fill in missing days with zeros
        if (weekActivity.length < 7) {
          for (var day in daysOfWeek) {
            if (!activityByDay.containsKey(day)) {
              weekActivity.add({
                'day': day,
                'steps': 0,
                'calories': 0,
                'distance': 0.0,
              });
            }
          }
          
          // Sort again after adding missing days
          weekActivity.sort((a, b) {
            return daysOfWeek.indexOf(a['day']) - daysOfWeek.indexOf(b['day']);
          });
        }
        
        if (mounted) {
          setState(() {
            _weeklyActivity = weekActivity;
          });
        }
      } else {
        // If no data, use mock data
        _loadMockWeeklyData();
      }
    } catch (e) {
      print('Error fetching weekly activity: $e');
      _loadMockWeeklyData();
      throw e;
    }
  }

  void _loadMockActivityData() {
    if (mounted) {
      setState(() {
        _activityData = {
          'steps': 7358,
          'calories': 345,
          'distance': 4.6,
          'active_minutes': 35,
          'goal': 10000,
        };
        
        _loadMockWeeklyData();
        
        _isLoading = false;
      });
    }
  }
  
  void _loadMockWeeklyData() {
    if (mounted) {
      setState(() {
        _weeklyActivity = [
          {'day': 'Mon', 'steps': 8234, 'calories': 380, 'distance': 5.2},
          {'day': 'Tue', 'steps': 9512, 'calories': 425, 'distance': 6.1},
          {'day': 'Wed', 'steps': 7869, 'calories': 362, 'distance': 5.0},
          {'day': 'Thu', 'steps': 10254, 'calories': 467, 'distance': 6.5},
          {'day': 'Fri', 'steps': 8543, 'calories': 390, 'distance': 5.5},
          {'day': 'Sat', 'steps': 6425, 'calories': 298, 'distance': 4.1},
          {'day': 'Sun', 'steps': 7358, 'calories': 345, 'distance': 4.6},
        ];
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
              _loadActivityData();
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
        onPressed: () => _addManualActivity(),
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
    if (_selectedCategory == 'Blood Pressure' && !_isNavigating) {
      _isNavigating = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pop(context);
      });
      return Container(
        color: Colors.white,
        child: const Center(
          child: Text('Loading Blood Pressure Screen...'),
        ),
      );
    } else if (_selectedCategory == 'Weight' && !_isNavigating) {
      _isNavigating = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pop(context);
      });
      return Container(
        color: Colors.white,
        child: const Center(
          child: Text('Loading Weight Screen...'),
        ),
      );
    } else if (_selectedCategory == 'Overview' && !_isNavigating) {
      _isNavigating = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const HealthOverviewScreen()),
        ).then((_) {
          setState(() {
            _selectedCategory = 'Activity';
            _isNavigating = false;
            _tabController.animateTo(1); // Reset tab selection to Activity
          });
        });
      });
    }

    switch (_selectedCategory) {
      case 'Activity':
        return _buildActivityContent();
      case 'Weight':
        return _buildActivityContent();
      default:
        return _buildActivityContent();
    }
  }

  Widget _buildActivityContent() {
    return RefreshIndicator(
      onRefresh: _loadActivityData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusCard(),
            _buildActivitySummaryCard(),
            _buildWeeklyChart(),
            _buildGoalProgressCard(),
            _buildActionButtons(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    // Calculate percentage of daily goal completed
    final double percentComplete = (_activityData['steps'] / _activityData['goal']) * 100;
    final String statusText = percentComplete >= 100
        ? 'Goal Achieved!'
        : percentComplete >= 75
        ? 'Almost There!'
        : percentComplete >= 50
        ? 'Good Progress'
        : 'Keep Moving';

    final Color statusColor = percentComplete >= 100
        ? Colors.green
        : percentComplete >= 75
        ? Colors.blue
        : percentComplete >= 50
        ? Colors.orange
        : Colors.amber;

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
                    color: statusColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Last updated: ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')} Today',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Based on daily goal',
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

  Widget _buildActivitySummaryCard() {
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
              'Today\'s Activity',
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
                _buildActivityItem('Steps', '${_activityData['steps']}', '', Colors.indigo),
                _buildActivityItem('Calories', '${_activityData['calories']}', 'kcal', Colors.orange),
                _buildActivityItem('Distance', '${_activityData['distance']}', 'km', Colors.green),
              ],
            ),
            if (_activityData.containsKey('active_minutes'))
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildActivityItem('Active Minutes', '${_activityData['active_minutes']}', 'min', Colors.purple),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem(String title, String value, String unit, Color color) {
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
              child: _weeklyActivity.isEmpty
                ? const Center(child: Text('No activity data available for this week'))
                : BarChart(
                  BarChartData(
                    gridData: const FlGridData(show: false),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            if (value.toInt() >= 0 && value.toInt() < _weeklyActivity.length) {
                              return Text(
                                _weeklyActivity[value.toInt()]['day'],
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
                            if (value % 2000 == 0 && value <= 10000) {
                              return Text(
                                '${value ~/ 1000}k',
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
                    barGroups: List.generate(_weeklyActivity.length, (index) {
                      // Determine if this is today's bar
                      bool isToday = _weeklyActivity[index]['day'] == 
                          DateFormat('E').format(DateTime.now());
                      
                      return BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: _weeklyActivity[index]['steps']?.toDouble() ?? 0,
                            color: isToday ? Colors.indigo : Colors.indigo.withOpacity(0.6),
                            width: 15,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(6),
                              topRight: Radius.circular(6),
                            ),
                          ),
                        ],
                      );
                    }),
                    minY: 0,
                    maxY: 12000,
                  ),
                ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('Steps', Colors.indigo),
                const SizedBox(width: 20),
                _buildLegendItem('Daily Goal', Colors.amber),
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

  Widget _buildGoalProgressCard() {
    final double progressPercentage = (_activityData['steps'] / _activityData['goal']).clamp(0.0, 1.0);

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
                  'Goal Progress',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                Text(
                  '${(_activityData['steps'] / _activityData['goal'] * 100).toInt()}% Complete',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Stack(
                children: [
                  FractionallySizedBox(
                    widthFactor: progressPercentage,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.indigo,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_activityData['steps']} steps',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Goal: ${_activityData['goal']} steps',
                  style: TextStyle(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Need ${_activityData['goal'] - _activityData['steps']} more steps to reach your goal',
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

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _addManualActivity(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add Activity',
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
              onPressed: () => _editStepGoal(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Colors.indigo),
                ),
              ),
              icon: const Icon(Icons.edit, color: Colors.indigo),
              label: const Text(
                'Edit Goal',
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

  void _addManualActivity() async {
    // Check if user is authenticated
    User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to add activity data')),
      );
      return;
    }
    
    // Show dialog to add activity manually
    final TextEditingController stepsController = TextEditingController();
    final TextEditingController caloriesController = TextEditingController();
    final TextEditingController distanceController = TextEditingController();
    final TextEditingController activeMinutesController = TextEditingController();
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Activity'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: stepsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Steps',
                  hintText: '0',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: caloriesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Calories (kcal)',
                  hintText: '0',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: distanceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Distance (km)',
                  hintText: '0.0',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: activeMinutesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Active Minutes',
                  hintText: '0',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              // This continues from where the previous code snippet left off

              // Validate input
              if (stepsController.text.isEmpty && 
                  caloriesController.text.isEmpty && 
                  distanceController.text.isEmpty && 
                  activeMinutesController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter at least one value')),
                );
                return;
              }
              
              try {
                // Parse input values
                int steps = int.tryParse(stepsController.text) ?? 0;
                int calories = int.tryParse(caloriesController.text) ?? 0;
                double distance = double.tryParse(distanceController.text) ?? 0.0;
                int activeMinutes = int.tryParse(activeMinutesController.text) ?? 0;
                
                // Save to Firestore
                await _saveActivityToFirebase(
                  steps: steps,
                  calories: calories,
                  distance: distance,
                  activeMinutes: activeMinutes,
                );
                
                Navigator.pop(context);
                
              } catch (e) {
                print('Error saving activity: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error adding activity: $e')),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.indigo,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _saveActivityToFirebase({
    required int steps,
    required int calories,
    required double distance,
    required int activeMinutes,
  }) async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }
      
      // Get current date and time
      final now = DateTime.now();
      
      // Create activity document
      await _firestore.collection('activity').add({
        'steps': steps.toString(),
        'calories': calories.toString(),
        'distance': distance.toString(),
        'active_minutes': activeMinutes.toString(),
        'timestamp': now,
        'user_id': currentUser.uid,
      });
      
      // Update local state
      setState(() {
        _activityData = {
          'steps': steps,
          'calories': calories,
          'distance': distance,
          'active_minutes': activeMinutes,
          'goal': _activityData['goal'],
        };
      });
      
      // Refresh data to update weekly chart
      _fetchWeeklyActivity(currentUser.uid);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Activity saved successfully')),
      );
    } catch (e) {
      print('Error saving activity to Firebase: $e');
      throw e;
    }
  }

  void _editStepGoal() async {
    // Check if user is authenticated
    User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to edit your goal')),
      );
      return;
    }
    
    // Show dialog to edit goal
    final TextEditingController goalController = TextEditingController(
      text: _activityData['goal'].toString(),
    );
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Step Goal'),
        content: TextField(
          controller: goalController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Daily Step Goal',
            hintText: '10000',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              // Validate and save
              String goalStr = goalController.text.trim();
              if (goalStr.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid goal')),
                );
                return;
              }
              
              int goal = int.tryParse(goalStr) ?? 10000;
              
              try {
                // Save to Firebase
                await _firestore
                    .collection('users')
                    .doc(currentUser.uid)
                    .set({'step_goal': goal}, SetOptions(merge: true));
                
                // Update local state
                setState(() {
                  _activityData['goal'] = goal;
                });
                
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Step goal updated successfully')),
                );
              } catch (e) {
                print('Error updating goal: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error updating goal: $e')),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.indigo,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  
}