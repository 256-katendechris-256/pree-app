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
  int _selectedNavIndex = 0; // Keep only this declaration
  
  // Insight data
  Map<String, dynamic> _insightData = {
    'generatedInsight': 'No insights available for this date.',
    'active_minutes': '0',
    'calories': '0',
    'distance': '0',
    'steps': '0',
    'timestamp': DateTime.now(),
  };
  
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
          .collection('Insite')
          .where('user_id', isEqualTo: userId)
          .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
          .where('timestamp', isLessThanOrEqualTo: endOfDay)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();
      
      if (insightDocs.docs.isNotEmpty) {
        var data = insightDocs.docs.first.data();
        
        if (mounted) {
          setState(() {
            _insightData = {
              'generatedInsight': data['generatedInsight'] ?? 'No insights available.',
              'active_minutes': data['active_minutes'] ?? '0',
              'calories': data['calories'] ?? '0',
              'distance': data['distance'] ?? '0',
              'steps': data['steps'] ?? '0',
              'timestamp': data['timestamp'] != null ? (data['timestamp'] as Timestamp).toDate() : DateTime.now(),
            };
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _insightData = {
              'generatedInsight': 'No insights available for this date.',
              'active_minutes': '0',
              'calories': '0',
              'distance': '0',
              'steps': '0',
              'timestamp': date,
            };
          });
        }
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
          .collection('Insite')
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
        
        insightsByDate[dateKey]!.add({
          'generatedInsight': data['generatedInsight'] ?? 'No insights available.',
          'active_minutes': data['active_minutes'] ?? '0',
          'calories': data['calories'] ?? '0',
          'distance': data['distance'] ?? '0',
          'steps': data['steps'] ?? '0',
          'timestamp': timestamp,
          'id': doc.id,
        });
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
        _insightData = {
          'generatedInsight': "That's great that you're tracking your physical activity during pregnancy! Every step counts, no matter how small. Staying active is so important for your health and well-being during this special time. Keep up the good work, and remember that even gentle movement can have positive impacts on both you and your baby.",
          'active_minutes': '101',
          'calories': '320',
          'distance': '2.5',
          'steps': '4500',
          'timestamp': DateTime.now(),
        };
        
        // Create some mock data for the calendar
        _insightsByDate = {
          DateTime.now(): [_insightData],
          DateTime.now().subtract(const Duration(days: 1)): [{
            'generatedInsight': "Your blood pressure readings are looking stable. Continue with your current routine and remember to take your measurements at consistent times.",
            'active_minutes': '85',
            'calories': '280',
            'distance': '2.1',
            'steps': '3800',
            'timestamp': DateTime.now().subtract(const Duration(days: 1)),
          }],
          DateTime.now().subtract(const Duration(days: 2)): [{
            'generatedInsight': "I notice you've been consistently active this week. This is excellent for maintaining healthy blood pressure levels during pregnancy.",
            'active_minutes': '120',
            'calories': '350',
            'distance': '3.0',
            'steps': '5200',
            'timestamp': DateTime.now().subtract(const Duration(days: 2)),
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
            _insightData = _insightsByDate[selectedDay]![0];
          } else {
            _insightData = {
              'generatedInsight': 'No insights available for this date.',
              'active_minutes': '0',
              'calories': '0',
              'distance': '0',
              'steps': '0',
              'timestamp': selectedDay,
            };
          }
          _isLoading = false;
        });
      }
    }
  }
  
  // Removed duplicate _selectedNavIndex declaration

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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
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
                _buildInsightCard(),
                _buildActivitySummary(),
              ],
            ),
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
              break;
            case 3: // Settings
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
              break;
          }
        },
      ),
    ); // Added missing closing bracket here
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
  
  Widget _buildInsightCard() {
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
                    color: Colors.indigo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.lightbulb_outline,
                    color: Colors.indigo,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Daily Insight',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _insightData['generatedInsight'],
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[800],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            if (_insightData['timestamp'] != null)
              Text(
                'Generated on: ${DateFormat('h:mm a').format(_insightData['timestamp'])}',
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
  
  Widget _buildActivitySummary() {
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
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricItem(
                  icon: Icons.directions_walk,
                  value: _insightData['steps'],
                  label: 'Steps',
                  color: Colors.blue,
                ),
                _buildMetricItem(
                  icon: Icons.access_time,
                  value: _insightData['active_minutes'],
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
                  value: _insightData['calories'],
                  label: 'Calories',
                  color: Colors.orange,
                ),
                _buildMetricItem(
                  icon: Icons.straighten,
                  value: _insightData['distance'],
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