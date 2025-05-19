import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

// Import dashboard screen
import '../screens/dashboard.dart';
import '../widgets/bottom_nav_bar.dart'; // Adjust path
import 'reports_screen.dart';
import 'settings_screen.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> with TickerProviderStateMixin {
  // Firebase instances
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.week;
  DateTime _focusedDay = DateTime.now();
  
  // Selected category and navigation
  int _selectedNavIndex = 2; // Set to 2 for Insights tab
  
  // Insight data - now a list to hold multiple insights for a day
  List<Map<String, dynamic>> _insightsList = [];
  
  // Collection of insights by date
  Map<DateTime, List<Map<String, dynamic>>> _insightsByDate = {};
  
  @override
  void initState() {
    super.initState();
    _loadInsightData();
  }
  
  Future<void> _loadInsightData() async {
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
          const SnackBar(content: Text('Please log in to view your insights')),
        );
        return;
      }

      String userId = currentUser.uid;
      
      // Load insights for the selected date
      await _loadInsightsForDate(userId, _selectedDate);
      
      // Load insights for the last 30 days for the calendar
      await _loadInsightsForDateRange(userId);
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading insights: $e');
      _loadMockData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading insights: $e')),
        );
      }
    }
  }
  
  Future<void> _loadInsightsForDate(String userId, DateTime date) async {
    try {
      // Format date for comparison (reset time to beginning of day)
      DateTime startOfDay = DateTime(date.year, date.month, date.day);
      DateTime endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);
      
      // Query insights for the selected date
      var insightDocs = await _firestore
          .collection('Insites')
          .where('user_id', isEqualTo: userId)
          .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
          .where('timestamp', isLessThanOrEqualTo: endOfDay)
          .orderBy('timestamp', descending: true)
          .get();
      
      List<Map<String, dynamic>> insightsList = [];
      
      if (insightDocs.docs.isNotEmpty) {
        for (var doc in insightDocs.docs) {
          var data = doc.data();
          
          Map<String, dynamic> insightData = {
            'id': doc.id,
            'generatedInsight': data['generatedInsight'] ?? 'No insight available.',
            'timestamp': data['timestamp'] != null ? (data['timestamp'] as Timestamp).toDate() : DateTime.now(),
            'type': data['type'] ?? 'general',
            'source': data['source'] ?? '',
            'sourceCollection': data['sourceCollection'] ?? '',
          };
          
          // Add source data based on the collection type
          if (data['sourceData'] != null) {
            if (data['sourceCollection'] == 'activity') {
              insightData['active_minutes'] = data['sourceData']['active_minutes'] ?? 0;
              insightData['calories'] = data['sourceData']['calories'] ?? 0;
              insightData['distance'] = data['sourceData']['distance'] ?? 0;
              insightData['steps'] = data['sourceData']['steps'] ?? 0;
            } else if (data['sourceCollection'] == 'temperature') {
              insightData['temperature'] = data['sourceData']['temperature'] ?? 0;
              insightData['heart_rate'] = data['sourceData']['heart_rate'] ?? 0;
            } else if (data['sourceCollection'] == 'vital_signs') {
              insightData['systolic_BP'] = data['sourceData']['systolic_BP'] ?? 0;
              insightData['diastolic'] = data['sourceData']['diastolic'] ?? 0;
              insightData['pulse'] = data['sourceData']['pulse'] ?? 0;
            } else if (data['sourceCollection'] == 'weight') {
              insightData['weight'] = data['sourceData']['current'] ?? 0;
              insightData['bmi'] = data['sourceData']['bmi'] ?? 0;
            }
          } else {
            // Handle legacy format or insights without sourceData
            if (data['active_minutes'] != null) insightData['active_minutes'] = data['active_minutes'];
            if (data['calories'] != null) insightData['calories'] = data['calories'];
            if (data['distance'] != null) insightData['distance'] = data['distance'];
            if (data['steps'] != null) insightData['steps'] = data['steps'];
          }
          
          insightsList.add(insightData);
        }
      }
      
      if (mounted) {
        setState(() {
          _insightsList = insightsList;
          
          // If no insights available, show placeholder
          if (_insightsList.isEmpty) {
            _insightsList = [{
              'generatedInsight': 'No insights available for this date.',
              'timestamp': date,
              'type': 'general',
            }];
          }
        });
      }
    } catch (e) {
      print('Error loading insights for date: $e');
      throw e;
    }
  }
  
  Future<void> _loadInsightsForDateRange(String userId) async {
    try {
      // Calculate date range (last 30 days)
      DateTime now = DateTime.now();
      DateTime thirtyDaysAgo = now.subtract(const Duration(days: 30));
      
      // Query insights for date range
      var insightDocs = await _firestore
          .collection('Insites')
          .where('user_id', isEqualTo: userId)
          .where('timestamp', isGreaterThanOrEqualTo: thirtyDaysAgo)
          .orderBy('timestamp', descending: true)
          .get();
      
      Map<DateTime, List<Map<String, dynamic>>> insightsByDate = {};
      
      for (var doc in insightDocs.docs) {
        var data = doc.data();
        DateTime timestamp = (data['timestamp'] as Timestamp).toDate();
        DateTime dateKey = DateTime(timestamp.year, timestamp.month, timestamp.day);
        
        if (!insightsByDate.containsKey(dateKey)) {
          insightsByDate[dateKey] = [];
        }
        
        Map<String, dynamic> insightData = {
          'id': doc.id,
          'generatedInsight': data['generatedInsight'] ?? 'No insight available.',
          'timestamp': timestamp,
          'type': data['type'] ?? 'general',
          'source': data['source'] ?? '',
          'sourceCollection': data['sourceCollection'] ?? '',
        };
        
        // Add source data based on the collection type
        if (data['sourceData'] != null) {
          if (data['sourceCollection'] == 'activity') {
            insightData['active_minutes'] = data['sourceData']['active_minutes'] ?? 0;
            insightData['calories'] = data['sourceData']['calories'] ?? 0;
            insightData['distance'] = data['sourceData']['distance'] ?? 0;
            insightData['steps'] = data['sourceData']['steps'] ?? 0;
          } else if (data['sourceCollection'] == 'temperature') {
            insightData['temperature'] = data['sourceData']['temperature'] ?? 0;
            insightData['heart_rate'] = data['sourceData']['heart_rate'] ?? 0;
          } else if (data['sourceCollection'] == 'vital_signs') {
            insightData['systolic_BP'] = data['sourceData']['systolic_BP'] ?? 0;
            insightData['diastolic'] = data['sourceData']['diastolic'] ?? 0;
            insightData['pulse'] = data['sourceData']['pulse'] ?? 0;
          } else if (data['sourceCollection'] == 'weight') {
            insightData['weight'] = data['sourceData']['weight'] ?? 0;
            insightData['bmi'] = data['sourceData']['bmi'] ?? 0;
          }
        } else {
          // Handle legacy format or insights without sourceData
          if (data['active_minutes'] != null) insightData['active_minutes'] = data['active_minutes'];
          if (data['calories'] != null) insightData['calories'] = data['calories'];
          if (data['distance'] != null) insightData['distance'] = data['distance'];
          if (data['steps'] != null) insightData['steps'] = data['steps'];
        }
        
        insightsByDate[dateKey]!.add(insightData);
      }
      
      if (mounted) {
        setState(() {
          _insightsByDate = insightsByDate;
        });
      }
    } catch (e) {
      print('Error loading insights for date range: $e');
      throw e;
    }
  }
  
  void _loadMockData() {
    if (mounted) {
      setState(() {
        // Activity insight
        final activityInsight = {
          'generatedInsight': "ACTIVITY STATUS: LOW INTENSITY. Current level appropriate. Gentle, consistent activity supports circulation. Report any new symptoms promptly. Avoid long periods of inactivity.",
          'active_minutes': '13',
          'calories': '0',
          'distance': '0',
          'steps': '1',
          'timestamp': DateTime.now().subtract(const Duration(minutes: 30)),
          'type': 'clinical',
          'sourceCollection': 'activity',
        };
        
        // Temperature insight
        final temperatureInsight = {
          'generatedInsight': "TEMPERATURE STATUS: BELOW NORMAL (0°C). Continue monitoring. Report if accompanied by other symptoms. Maintain adequate warming.",
          'temperature': '0',
          'heart_rate': '0',
          'timestamp': DateTime.now().subtract(const Duration(hours: 1)),
          'type': 'clinical',
          'sourceCollection': 'temperature',
        };
        
        // Generic insight for pregnancy
        final generalInsight = {
          'generatedInsight': "That's great that you're tracking your physical activity during pregnancy! Every step counts, no matter how small. Staying active is so important for your health and well-being during this special time. Keep up the good work, and remember that even gentle movement can have positive impacts on both you and your baby.",
          'timestamp': DateTime.now().subtract(const Duration(hours: 3)),
          'type': 'general',
          'sourceCollection': '',
        };
        
        _insightsList = [temperatureInsight, activityInsight, generalInsight];
        
        // Create some mock data for the calendar
        _insightsByDate = {
          DateTime.now(): _insightsList,
          DateTime.now().subtract(const Duration(days: 1)): [{
            'generatedInsight': "Your blood pressure readings are looking stable. Continue with your current routine and remember to take your measurements at consistent times.",
            'systolic_BP': '120',
            'diastolic': '80',
            'pulse': '72',
            'timestamp': DateTime.now().subtract(const Duration(days: 1)),
            'type': 'clinical',
            'sourceCollection': 'vital_signs',
          }],
          DateTime.now().subtract(const Duration(days: 2)): [{
            'generatedInsight': "I notice you've been consistently active this week. This is excellent for maintaining healthy blood pressure levels during pregnancy.",
            'active_minutes': '120',
            'calories': '350',
            'distance': '3.0',
            'steps': '5200',
            'timestamp': DateTime.now().subtract(const Duration(days: 2)),
            'type': 'clinical',
            'sourceCollection': 'activity',
          }],
        };
        
        _isLoading = false;
      });
    }
  }
  
  // Handle date selection in the calendar
  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDate, selectedDay)) {
      setState(() {
        _selectedDate = selectedDay;
        _focusedDay = focusedDay;
        _isLoading = true;
      });
      
      User? currentUser = _auth.currentUser;
      if (currentUser != null) {
        _loadInsightsForDate(currentUser.uid, selectedDay).then((_) {
          setState(() {
            _isLoading = false;
          });
        });
      } else {
        // Use mock data for selected day if not logged in
        setState(() {
          if (_insightsByDate.containsKey(selectedDay)) {
            _insightsList = _insightsByDate[selectedDay]!;
          } else {
            _insightsList = [{
              'generatedInsight': 'No insights available for this date.',
              'timestamp': selectedDay,
              'type': 'general',
            }];
          }
          _isLoading = false;
        });
      }
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
          'Daily Insights',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: () {
              _loadInsightData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Refreshing insights...'))
              );
            },
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
        : SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCalendar(),
                _buildDateHeader(),
                ..._buildInsightCards(),
              ],
            ),
          ),
      bottomNavigationBar: BottomNavBar(
        selectedIndex: _selectedNavIndex,
        onItemTapped: (index) {
          if (index == _selectedNavIndex) {
            return; // Already on Insights screen
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
  
  Widget _buildCalendar() {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: TableCalendar(
          firstDay: DateTime.now().subtract(const Duration(days: 365)),
          lastDay: DateTime.now(),
          focusedDay: _focusedDay,
          calendarFormat: _calendarFormat,
          selectedDayPredicate: (day) => isSameDay(_selectedDate, day),
          onDaySelected: _onDaySelected,
          onFormatChanged: (format) {
            setState(() {
              _calendarFormat = format;
            });
          },
          onPageChanged: (focusedDay) {
            _focusedDay = focusedDay;
          },
          calendarStyle: CalendarStyle(
            selectedDecoration: const BoxDecoration(
              color: Colors.indigo,
              shape: BoxShape.circle,
            ),
            todayDecoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            markerDecoration: const BoxDecoration(
              color: Colors.indigo,
              shape: BoxShape.circle,
            ),
          ),
          headerStyle: const HeaderStyle(
            formatButtonVisible: true,
            titleCentered: true,
            formatButtonShowsNext: false,
            formatButtonDecoration: BoxDecoration(
              color: Colors.indigo,
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            formatButtonTextStyle: TextStyle(color: Colors.white),
          ),
          eventLoader: (day) {
            DateTime dateKey = DateTime(day.year, day.month, day.day);
            return _insightsByDate[dateKey] ?? [];
          },
        ),
      ),
    );
  }
  
  Widget _buildDateHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.indigo,
        ),
      ),
    );
  }
  
  List<Widget> _buildInsightCards() {
    List<Widget> cards = [];
    
    if (_insightsList.isEmpty) {
      cards.add(
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: Text('No insights available for this date.'),
            ),
          ),
        )
      );
      return cards;
    }
    
    // Build a card for each insight
    for (var insight in _insightsList) {
      cards.add(_buildInsightCard(insight));
      
      // For activity insights, add activity summary card
      if (insight['sourceCollection'] == 'activity') {
        cards.add(_buildActivitySummary(insight));
      }
      // For vital signs insights, add blood pressure summary card
      else if (insight['sourceCollection'] == 'vital_signs') {
        cards.add(_buildVitalSignsSummary(insight));
      }
      // For temperature insights, add temperature summary card
      else if (insight['sourceCollection'] == 'temperature') {
        cards.add(_buildTemperatureSummary(insight));
      }
      // For weight insights, add weight summary card
      else if (insight['sourceCollection'] == 'weight') {
        cards.add(_buildWeightSummary(insight));
      }
    }
    
    return cards;
  }
  
  Widget _buildInsightCard(Map<String, dynamic> insight) {
    // Determine icon and color based on insight type
    IconData icon;
    Color color;
    String title;
    
    switch (insight['sourceCollection']) {
      case 'activity':
        icon = Icons.directions_run;
        color = Colors.green;
        title = 'Activity Insight';
        break;
      case 'temperature':
        icon = Icons.thermostat;
        color = Colors.red;
        title = 'Temperature Insight';
        break;
      case 'vital_signs':
        icon = Icons.favorite;
        color = Colors.red;
        title = 'Blood Pressure Insight';
        break;
      case 'weight':
        icon = Icons.monitor_weight;
        color = Colors.blue;
        title = 'Weight Insight';
        break;
      default:
        icon = Icons.lightbulb_outline;
        color = Colors.indigo;
        title = 'Daily Insight';
    }
    
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
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              insight['generatedInsight'],
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[800],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            if (insight['timestamp'] != null)
              Text(
                'Generated on: ${DateFormat('h:mm a').format(insight['timestamp'])}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildActivitySummary(Map<String, dynamic> insight) {
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
              'Activity Summary',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricItem(
                  icon: Icons.directions_walk,
                  value: insight['steps'] ?? '0',
                  label: 'Steps',
                  color: Colors.blue,
                ),
                _buildMetricItem(
                  icon: Icons.access_time,
                  value: insight['active_minutes'] ?? '0',
                  label: 'Active Min',
                  color: Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricItem(
                  icon: Icons.local_fire_department,
                  value: insight['calories'] ?? 0,
                  label: 'Calories',
                  color: Colors.orange,
                ),
                _buildMetricItem(
                  icon: Icons.straighten,
                  value: insight['distance'] ?? 0,
                  label: 'Distance (km)',
                  color: Colors.purple,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildVitalSignsSummary(Map<String, dynamic> insight) {
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
              'Blood Pressure Summary',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricItem(
                  icon: Icons.arrow_upward,
                  value: insight['systolic_BP'] ?? 0,
                  label: 'Systolic',
                  color: Colors.red,
                ),
                _buildMetricItem(
                  icon: Icons.arrow_downward,
                  value: insight['diastolic'] ?? 0,
                  label: 'Diastolic',
                  color: Colors.blue,
                ),
                _buildMetricItem(
                  icon: Icons.favorite,
                  value: insight['pulse'] ?? 0,
                  label: 'Pulse',
                  color: Colors.purple,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTemperatureSummary(Map<String, dynamic> insight) {
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
              'Temperature Summary',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricItem(
                  icon: Icons.thermostat,
                  value: '${insight['temperature'] ?? '0'} °C',
                  label: 'Temperature',
                  color: Colors.red,
                ),
                _buildMetricItem(
                  icon: Icons.favorite,
                  value: insight['heart_rate'] ?? '0',
                  label: 'Heart Rate',
                  color: Colors.purple,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildWeightSummary(Map<String, dynamic> insight) {
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
              'Weight Summary',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricItem(
                  icon: Icons.monitor_weight,
                  value: '${insight['weight'] ?? '0'} kg',
                  label: 'Weight',
                  color: Colors.blue,
                ),
                _buildMetricItem(
                  icon: Icons.calculate,
                  value: insight['bmi'] ?? '0',
                  label: 'BMI',
                  color: Colors.green,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMetricItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: color,
            size: 28,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}