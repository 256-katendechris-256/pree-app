import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HealthOverviewScreen extends StatefulWidget {
  const HealthOverviewScreen({super.key});

  @override
  State<HealthOverviewScreen> createState() => _HealthOverviewScreenState();
}

class _HealthOverviewScreenState extends State<HealthOverviewScreen> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late TabController _tabController;
  bool _isLoading = true;
  
  // Data containers
  final Map<String, dynamic> _healthData = {
    'bloodPressure': {
      'morningAvgSys': 0,
      'morningAvgDia': 0,
      'eveningAvgSys': 0,
      'eveningAvgDia': 0,
      'status': 'Loading'
    },
    'activity': {
      'steps': 0,
      'distance': 0,
      'calories': 0,
      'activeMinutes': 0
    },
    'weight': {
      'current': 0,
      'change': 0,
      'bmi': 0,
      'status': 'Loading'
    }
  };

  // Weekly trends
  List<Map<String, dynamic>> _weeklyStats = [];
  
  // Reference to Firestore
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _userId = FirebaseAuth.instance.currentUser?.uid ?? 'defaultUserId';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
    
    // Load data from Firebase
    _loadUserHealthData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _loadUserHealthData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Load most recent vital signs (blood pressure)
      await _loadBloodPressureData();
      
      // Load activity data
      await _loadActivityData();
      
      // Load weight data
      await _loadWeightData();
      
      // Load weekly trends
      await _loadWeeklyTrends();
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading health data: $e');
      setState(() {
        _isLoading = false;
      });
      
      // Show error to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load health data: $e'))
      );
    }
  }
  
  Future<void> _loadBloodPressureData() async {
    // Query vital_signs collection sorted by timestamp
    final QuerySnapshot vitalSignsSnapshot = await _firestore
        .collection('vital_signs')
        .where('user_id', isEqualTo: _userId)
        .orderBy('timestamp', descending: true)
        .limit(10)
        .get();
    
    if (vitalSignsSnapshot.docs.isEmpty) {
      return;
    }
    
    // Process vitals to determine morning and evening readings
    List<Map<String, dynamic>> morningReadings = [];
    List<Map<String, dynamic>> eveningReadings = [];
    
    for (var doc in vitalSignsSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final timeStr = data['time'] as String? ?? '';
      
      // Parse time to determine if morning or evening
      if (timeStr.contains('AM') || (timeStr.isNotEmpty && (int.tryParse(timeStr.split(':')[0]) ?? 0) < 12)) {
        morningReadings.add(data);
      } else {
        eveningReadings.add(data);
      }
    }
    
    // Calculate averages
    int morningAvgSys = 0;
    int morningAvgDia = 0;
    int eveningAvgSys = 0;
    int eveningAvgDia = 0;
    
    if (morningReadings.isNotEmpty) {
      morningAvgSys = morningReadings.map((e) => e['systolic_BP'] as int? ?? 0).reduce((a, b) => a + b) ~/ morningReadings.length;
      morningAvgDia = morningReadings.map((e) => e['diastolic'] as int? ?? 0).reduce((a, b) => a + b) ~/ morningReadings.length;
    }
    
    if (eveningReadings.isNotEmpty) {
      eveningAvgSys = eveningReadings.map((e) => e['systolic_BP'] as int? ?? 0).reduce((a, b) => a + b) ~/ eveningReadings.length;
      eveningAvgDia = eveningReadings.map((e) => e['diastolic'] as int? ?? 0).reduce((a, b) => a + b) ~/ eveningReadings.length;
    }
    
    // Determine BP status
    String bpStatus = 'Normal';
    final avgSys = (morningAvgSys + eveningAvgSys) ~/ (morningAvgSys > 0 && eveningAvgSys > 0 ? 2 : 1);
    final avgDia = (morningAvgDia + eveningAvgDia) ~/ (morningAvgDia > 0 && eveningAvgDia > 0 ? 2 : 1);
    
    if (avgSys < 120 && avgDia < 80) {
      bpStatus = 'Optimal';
    } else if ((avgSys >= 120 && avgSys <= 129) && avgDia < 80) {
      bpStatus = 'Elevated';
    } else if ((avgSys >= 130 && avgSys <= 139) || (avgDia >= 80 && avgDia <= 89)) {
      bpStatus = 'Stage 1';
    } else if (avgSys >= 140 || avgDia >= 90) {
      bpStatus = 'Stage 2';
    }
    
    // Update health data
    setState(() {
      _healthData['bloodPressure'] = {
        'morningAvgSys': morningAvgSys > 0 ? morningAvgSys : vitalSignsSnapshot.docs.first['systolic_BP'] ?? 0,
        'morningAvgDia': morningAvgDia > 0 ? morningAvgDia : vitalSignsSnapshot.docs.first['diastolic'] ?? 0,
        'eveningAvgSys': eveningAvgSys > 0 ? eveningAvgSys : vitalSignsSnapshot.docs.first['systolic_BP'] ?? 0,
        'eveningAvgDia': eveningAvgDia > 0 ? eveningAvgDia : vitalSignsSnapshot.docs.first['diastolic'] ?? 0,
        'status': bpStatus,
      };
    });
  }
  
  Future<void> _loadActivityData() async {
    // Get the latest activity data
    final QuerySnapshot activitySnapshot = await _firestore
        .collection('activity')
        .where('user_id', isEqualTo: _userId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();
    
    if (activitySnapshot.docs.isEmpty) {
      return;
    }
    
    final activityData = activitySnapshot.docs.first.data() as Map<String, dynamic>;
    
    // Update activity data
    setState(() {
      _healthData['activity'] = {
        'steps': int.tryParse(activityData['steps'] ?? '0') ?? 0,
        'distance': double.tryParse(activityData['distance'] ?? '0') ?? 0,
        'calories': int.tryParse(activityData['calories'] ?? '0') ?? 0,
        'activeMinutes': int.tryParse(activityData['active_minutes'] ?? '0') ?? 0,
      };
    });
  }
  
  Future<void> _loadWeightData() async {
    // Get the latest weight data
    final QuerySnapshot weightSnapshot = await _firestore
        .collection('weight')
        .where('user_id', isEqualTo: _userId)
        .orderBy('timestamp', descending: true)
        .limit(2) // Get current and previous for change calculation
        .get();
    
    if (weightSnapshot.docs.isEmpty) {
      return;
    }
    
    final currentWeightData = weightSnapshot.docs.first.data() as Map<String, dynamic>;
    double currentWeight = double.tryParse(currentWeightData['current'] ?? '0') ?? 0;
    double bmi = double.tryParse(currentWeightData['bmi'] ?? '0') ?? 0;
    
    // Calculate change if we have previous data
    double change = 0;
    if (weightSnapshot.docs.length > 1) {
      final previousWeightData = weightSnapshot.docs[1].data() as Map<String, dynamic>;
      double previousWeight = double.tryParse(previousWeightData['current'] ?? '0') ?? 0;
      if (previousWeight > 0) {
        change = currentWeight - previousWeight;
      }
    }
    
    // Determine weight status based on BMI
    String weightStatus = 'Normal';
    if (bmi < 18.5) {
      weightStatus = 'Underweight';
    } else if (bmi >= 18.5 && bmi < 25) {
      weightStatus = 'Normal';
    } else if (bmi >= 25 && bmi < 30) {
      weightStatus = 'Overweight';
    } else if (bmi >= 30) {
      weightStatus = 'Obese';
    }
    
    // Update weight data
    setState(() {
      _healthData['weight'] = {
        'current': currentWeight,
        'change': change,
        'bmi': bmi,
        'status': weightStatus,
      };
    });
  }
  
  Future<void> _loadWeeklyTrends() async {
  final DateTime now = DateTime.now();
  final DateTime sevenDaysAgo = now.subtract(const Duration(days: 7));

  // Query snapshots
  final vitalSignsSnapshot = await _firestore
      .collection('vital_signs')
      .where('user_id', isEqualTo: _userId)
      .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(sevenDaysAgo))
      .where('timestamp', isLessThan: Timestamp.fromDate(now))
      .orderBy('timestamp', descending: true)
      .get();

  final activitySnapshot = await _firestore
      .collection('activity')
      .where('user_id', isEqualTo: _userId)
      .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(sevenDaysAgo))
      .where('timestamp', isLessThan: Timestamp.fromDate(now))
      .orderBy('timestamp', descending: true)
      .get();

  final weightSnapshot = await _firestore
      .collection('weight')
      .where('user_id', isEqualTo: _userId)
      .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(sevenDaysAgo))
      .where('timestamp', isLessThan: Timestamp.fromDate(now))
      .orderBy('timestamp', descending: true)
      .get();

  // Create map for aggregation
  Map<String, Map<String, dynamic>> dailyData = {};
  List<String> dayOrder = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  for (int i = 0; i < 7; i++) {
    final date = now.subtract(Duration(days: 6 - i));
    final dayStr = DateFormat('E').format(date);

    dailyData[dayStr] = {
      'day': dayStr,
      'steps': 0,
      'weight': 0.0,
      'systolicSum': 0,
      'systolicCount': 0,
      'stepsSum': 0,
      'stepsCount': 0,
      'weightSum': 0.0,
      'weightCount': 0,
    };
  }

  // Process vitals
  for (var doc in vitalSignsSnapshot.docs) {
    final data = doc.data();
    final timestamp = data['timestamp'] as Timestamp?;
    final systolic = data['systolic_BP'] as int?;

    if (timestamp != null && systolic != null) {
      final dayStr = DateFormat('E').format(timestamp.toDate());
      if (dailyData.containsKey(dayStr)) {
        dailyData[dayStr]!['systolicSum'] += systolic;
        dailyData[dayStr]!['systolicCount'] += 1;
      }
    }
  }

  // Process activity
  for (var doc in activitySnapshot.docs) {
    final data = doc.data();
    final timestamp = data['timestamp'] as Timestamp?;
    final steps = data['steps'] as int?;

    if (timestamp != null && steps != null) {
      final dayStr = DateFormat('E').format(timestamp.toDate());
      if (dailyData.containsKey(dayStr)) {
        dailyData[dayStr]!['stepsSum'] += steps;
        dailyData[dayStr]!['stepsCount'] += 1;
      }
    }
  }

  // Process weight
  for (var doc in weightSnapshot.docs) {
    final data = doc.data();
    final timestamp = data['timestamp'] as Timestamp?;
    final current = (data['current'] as num?)?.toDouble();

    if (timestamp != null && current != null) {
      final dayStr = DateFormat('E').format(timestamp.toDate());
      if (dailyData.containsKey(dayStr)) {
        dailyData[dayStr]!['weightSum'] += current;
        dailyData[dayStr]!['weightCount'] += 1;
      }
    }
  }

  // Finalize daily stats
  List<Map<String, dynamic>> weeklyStats = dailyData.values.map((dayData) {
    return {
      'day': dayData['day'],
      'systolic': dayData['systolicCount'] > 0
          ? (dayData['systolicSum'] / dayData['systolicCount']).round()
          : 0,
      'steps': dayData['stepsCount'] > 0
          ? (dayData['stepsSum'] / dayData['stepsCount']).round()
          : 0,
      'weight': dayData['weightCount'] > 0
          ? (dayData['weightSum'] / dayData['weightCount']).toStringAsFixed(1)
          : '0.0',
    };
  }).toList();

  // Sort by day order
  weeklyStats.sort((a, b) =>
      dayOrder.indexOf(a['day']) - dayOrder.indexOf(b['day']));

  // Set state
  setState(() {
    _weeklyStats = weeklyStats;
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
          'Health Overview',
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
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Syncing data...'))
              );
              _loadUserHealthData();
            },
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : Column(
            children: [
              _buildCategoryTabs(),
              Expanded(
                // Use TabBarView to switch content based on selected tab
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewContent(),
                    _buildBloodPressureContent(),
                    _buildActivityContent(),
                    _buildWeightContent(),
                  ],
                ),
              ),
            ],
          ),
      bottomNavigationBar: _buildBottomNavBar(),
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
        tabs: const [
          Tab(
            icon: Icon(Icons.dashboard),
            text: 'Overview',
          ),
          Tab(
            icon: Icon(Icons.favorite),
            text: 'Blood Pressure',
          ),
          Tab(
            icon: Icon(Icons.directions_run),
            text: 'Activity',
          ),
          Tab(
            icon: Icon(Icons.monitor_weight),
            text: 'Weight',
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewContent() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverviewHeader(),
          _buildBloodPressureCard(),
          _buildActivityCard(),
          _buildWeightCard(),
          _buildWeeklyTrendsChart(),
          _buildHealthInsightsCard(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildBloodPressureContent() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverviewHeader(),
          _buildBloodPressureCard(),
          _buildWeeklyTrendsChart(),
          _buildHealthInsightsCard(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildActivityContent() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverviewHeader(),
          _buildActivityCard(),
          _buildWeeklyTrendsChart(),
          _buildHealthInsightsCard(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildWeightContent() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverviewHeader(),
          _buildWeightCard(),
          _buildWeeklyTrendsChart(),
          _buildHealthInsightsCard(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildOverviewHeader() {
    final today = DateTime.now();
    final formattedDate = DateFormat('EEEE, MMM d, yyyy').format(today);

    return Card(
      margin: const EdgeInsets.all(16),
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
                  'Today\'s Overview',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                Text(
                  formattedDate,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _getHealthSummary(),
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _getHealthSummary() {
    // Generate a dynamic health summary based on the data
    final bpStatus = _healthData['bloodPressure']['status'];
    final steps = _healthData['activity']['steps'];
    final weightStatus = _healthData['weight']['status'];
    
    if (bpStatus == 'Optimal' && steps >= 8000 && weightStatus == 'Normal') {
      return 'Your health metrics are looking great today! Keep it up!';
    } else if (bpStatus == 'Optimal' || steps >= 8000 || weightStatus == 'Normal') {
      return 'Your health metrics are looking good today with some room for improvement.';
    } else {
      return 'There are opportunities to improve your health metrics today.';
    }
  }

  Widget _buildBloodPressureCard() {
    final bpData = _healthData['bloodPressure'];
    final bpStatus = bpData['status'];
    
    // Set color based on BP status
    Color statusColor = Colors.green;
    if (bpStatus == 'Elevated') {
      statusColor = Colors.amber;
    } else if (bpStatus == 'Stage 1') {
      statusColor = Colors.orange;
    } else if (bpStatus == 'Stage 2') {
      statusColor = Colors.red;
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                        Icons.favorite,
                        color: Colors.indigo,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Blood Pressure',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    bpStatus,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildTimeOfDayReadings(
                  title: 'Morning',
                  systolic: bpData['morningAvgSys'],
                  diastolic: bpData['morningAvgDia'],
                ),
                Container(
                  height: 80,
                  width: 1,
                  color: Colors.grey[300],
                ),
                _buildTimeOfDayReadings(
                  title: 'Evening',
                  systolic: bpData['eveningAvgSys'],
                  diastolic: bpData['eveningAvgDia'],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: const Text('Add New Reading'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.indigo,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeOfDayReadings({
    required String title,
    required int systolic,
    required int diastolic,
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
        const SizedBox(height: 8),
        RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 16, color: Colors.black),
            children: [
              TextSpan(
                text: '$systolic',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              TextSpan(
                text: '/',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              TextSpan(
                text: '$diastolic',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'mmHg',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildActivityCard() {
    final activityData = _healthData['activity'];
    final steps = activityData['steps'];
    final distance = activityData['distance'].toDouble();
    final calories = activityData['calories'];
    final activeMinutes = activityData['activeMinutes'];
    
    // Calculate progress for active minutes (assuming 150 min/week goal = ~22 min/day)
    final activeMinutesProgress = (activeMinutes / 22).clamp(0.0, 1.0);
    
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
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.directions_run,
                    color: Colors.green,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Activity',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildActivityMetric(
                  icon: Icons.directions_walk,
                  value: steps.toString(),
                  label: 'Steps',
                  color: Colors.green,
                ),
                _buildActivityMetric(
                  icon: Icons.straighten,
                  value: '${distance.toStringAsFixed(1)} km',
                  label: 'Distance',
                  color: Colors.blue,
                ),
                _buildActivityMetric(
                  icon: Icons.local_fire_department,
                  value: calories.toString(),
                  label: 'Calories',
                  color: Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: LinearProgressIndicator(
                value: activeMinutesProgress,
                backgroundColor: const Color(0xFFE0E0E0),
                color: Colors.green,
                minHeight: 8,
                borderRadius: const BorderRadius.all(Radius.circular(4)),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '$activeMinutes active minutes today',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityMetric({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
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

  Widget _buildWeightCard() {
    final weightData = _healthData['weight'];
    final currentWeight = weightData['current'].toDouble();
    final change = weightData['change'].toDouble();
    final bmi = weightData['bmi'].toDouble();
    final status = weightData['status'];
    
    // Determine color for weight status
    Color statusColor = Colors.teal;
    if (status == 'Underweight') {
      statusColor = Colors.amber;
    } else if (status == 'Overweight') {
      statusColor = Colors.orange;
    } else if (status == 'Obese') {
      statusColor = Colors.red;
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.monitor_weight,
                        color: Colors.teal,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Weight',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildWeightMetric(
                  value: currentWeight.toStringAsFixed(1),
                  unit: 'kg',
                  label: 'Current Weight',
                ),
                _buildWeightMetric(
                  value: change.toStringAsFixed(1),
                  unit: 'kg',
                  label: 'Weekly Change',
                  isNegative: change < 0,
                ),
                _buildWeightMetric(
                  value: bmi.toStringAsFixed(1),
                  unit: '',
                  label: 'BMI',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: const Text('Add New Reading'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.teal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeightMetric({
    required String value,
    required String unit,
    required String label,
    bool isNegative = false,
  }) {
    Color valueColor = Colors.teal;
    if (label == 'Weekly Change') {
      valueColor = isNegative ? Colors.green : Colors.red;
      value = isNegative ? value : '+$value';
    }

    return Column(
      children: [
        RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 16, color: Colors.black),
            children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                ),
              ),
              TextSpan(
                text: unit,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
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

  Widget _buildWeeklyTrendsChart() {
    // Check if we have data for the chart
    if (_weeklyStats.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text('No weekly trend data available'),
          ),
        ),
      );
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
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < _weeklyStats.length) {
                            return Text(
                              _weeklyStats[value.toInt()]['day'],
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
                    // BP line
                    LineChartBarData(
                      spots: List.generate(_weeklyStats.length, (index) {
                        return FlSpot(index.toDouble(), _weeklyStats[index]['systolic'].toDouble());
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
                    // Steps line (scaled down)
                    LineChartBarData(
                      spots: List.generate(_weeklyStats.length, (index) {
                        // Scale steps to fit on same chart
                        return FlSpot(index.toDouble(), _weeklyStats[index]['steps'] / 100);
                      }),
                      isCurved: true,
                      color: Colors.green,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.green.withOpacity(0.1),
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
                _buildLegendItem('Blood Pressure', Colors.indigo),
                const SizedBox(width: 20),
                _buildLegendItem('Activity', Colors.green),
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

  Widget _buildHealthInsightsCard() {
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
            const Row(
              children: [
                Icon(Icons.lightbulb_outline, color: Colors.amber),
                SizedBox(width: 8),
                Text(
                  'Health Insights',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInsightItem(
              icon: _getInsightIconForBP(),
              text: _getInsightTextForBP(),
              color: _getInsightColorForBP(),
            ),
            const SizedBox(height: 12),
            _buildInsightItem(
              icon: _getInsightIconForActivity(),
              text: _getInsightTextForActivity(),
              color: _getInsightColorForActivity(),
            ),
            const SizedBox(height: 12),
            _buildInsightItem(
              icon: _getInsightIconForWeight(),
              text: _getInsightTextForWeight(),
              color: _getInsightColorForWeight(),
            ),
          ],
        ),
      ),
    );
  }

  // Dynamic insight generators for blood pressure
  IconData _getInsightIconForBP() {
    final bpStatus = _healthData['bloodPressure']['status'];
    if (bpStatus == 'Optimal') {
      return Icons.check_circle_outline;
    } else if (bpStatus == 'Elevated') {
      return Icons.info_outline;
    } else {
      return Icons.warning_amber_outlined;
    }
  }

  String _getInsightTextForBP() {
    final bpStatus = _healthData['bloodPressure']['status'];
    final systolic = _healthData['bloodPressure']['morningAvgSys'];
    final diastolic = _healthData['bloodPressure']['morningAvgDia'];
    
    if (bpStatus == 'Optimal') {
      return 'Your blood pressure readings are in the optimal range.';
    } else if (bpStatus == 'Elevated') {
      return 'Your blood pressure is slightly elevated. Consider reducing salt intake.';
    } else if (bpStatus == 'Stage 1') {
      return 'Your blood pressure is in Stage 1 hypertension. Consider lifestyle changes.';
    } else {
      return 'Your blood pressure is elevated. Please consult with your healthcare provider.';
    }
  }

  Color _getInsightColorForBP() {
    final bpStatus = _healthData['bloodPressure']['status'];
    if (bpStatus == 'Optimal') {
      return Colors.green;
    } else if (bpStatus == 'Elevated') {
      return Colors.amber;
    } else if (bpStatus == 'Stage 1') {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  // Dynamic insight generators for activity
  IconData _getInsightIconForActivity() {
    final steps = _healthData['activity']['steps'];
    if (steps >= 10000) {
      return Icons.check_circle_outline;
    } else if (steps >= 7000) {
      return Icons.info_outline;
    } else {
      return Icons.directions_walk;
    }
  }

  String _getInsightTextForActivity() {
    final steps = _healthData['activity']['steps'];
    final activeMinutes = _healthData['activity']['activeMinutes'];
    
    if (steps >= 10000) {
      return 'Great job! You\'ve reached your step goal of 10,000 steps.';
    } else if (steps >= 7000) {
      return 'You\'re making good progress. Try to reach 10,000 steps daily for better heart health.';
    } else {
      return 'Try to increase your daily steps to at least 7,000-10,000 for better health.';
    }
  }

  Color _getInsightColorForActivity() {
    final steps = _healthData['activity']['steps'];
    if (steps >= 10000) {
      return Colors.green;
    } else if (steps >= 7000) {
      return Colors.blue;
    } else {
      return Colors.orange;
    }
  }

  // Dynamic insight generators for weight
  IconData _getInsightIconForWeight() {
    final weightStatus = _healthData['weight']['status'];
    final change = _healthData['weight']['change'];
    
    if (weightStatus == 'Normal' || (weightStatus != 'Normal' && change < 0)) {
      return Icons.trending_down;
    } else if (weightStatus == 'Underweight') {
      return Icons.trending_up;
    } else {
      return Icons.info_outline;
    }
  }

  String _getInsightTextForWeight() {
    final weightStatus = _healthData['weight']['status'];
    final change = _healthData['weight']['change'];
    final bmi = _healthData['weight']['bmi'];
    
    if (weightStatus == 'Normal') {
      if (change < 0) {
        return 'Your weight has decreased by ${change.abs().toStringAsFixed(1)}kg - maintaining a healthy BMI!';
      } else if (change > 0) {
        return 'Your weight has increased by ${change.toStringAsFixed(1)}kg, but your BMI is still in the healthy range.';
      } else {
        return 'Your weight is stable and your BMI is in the healthy range.';
      }
    } else if (weightStatus == 'Underweight') {
      return 'Your BMI is ${bmi.toStringAsFixed(1)}, which is considered underweight. Consider consulting a healthcare provider.';
    } else if (weightStatus == 'Overweight') {
      if (change < 0) {
        return 'Good progress! Your weight has decreased by ${change.abs().toStringAsFixed(1)}kg. Keep working toward a healthier BMI.';
      } else {
        return 'Your BMI is ${bmi.toStringAsFixed(1)}, which is in the overweight range. Consider increasing activity.';
      }
    } else {
      if (change < 0) {
        return 'Good progress! Your weight has decreased by ${change.abs().toStringAsFixed(1)}kg. Continue working with your healthcare provider.';
      } else {
        return 'Your BMI is ${bmi.toStringAsFixed(1)}, which is in the obese range. Please consult with your healthcare provider.';
      }
    }
  }

  Color _getInsightColorForWeight() {
    final weightStatus = _healthData['weight']['status'];
    final change = _healthData['weight']['change'];
    
    if (weightStatus == 'Normal') {
      return Colors.green;
    } else if (weightStatus == 'Underweight') {
      return Colors.amber;
    } else if (change < 0) {
      return Colors.green; // Weight loss if overweight/obese is positive
    } else {
      return Colors.orange;
    }
  }

  Widget _buildInsightItem({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNavBar() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      selectedItemColor: Colors.indigo,
      unselectedItemColor: Colors.grey,
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.insert_chart),
          label: 'Reports',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.calendar_today),
          label: 'Calendar',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
      onTap: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
    );
  }
}