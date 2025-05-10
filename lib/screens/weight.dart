import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import '../screens/manual_reading_weight.dart';
import '../screens/insight_screen.dart';
import '../widgets/bottom_nav_bar.dart'; // Adjust path
import 'reports_screen.dart';
import 'settings_screen.dart';

class WeightScreen extends StatefulWidget {
  const WeightScreen({super.key});

  @override
  State<WeightScreen> createState() => _WeightScreenState();
}

class _WeightScreenState extends State<WeightScreen> {
  // Weight data
  Map<String, dynamic> _currentWeight = {
    'weight': 0.0,
    'bmi': 0.0,
    'goal': 70.0,
    'unit': 'kg',
    'date': DateTime.now(),
  };

  // Monthly weight data
  List<Map<String, dynamic>> _monthlyWeights = [];

  // Loading state
  bool _isLoading = true;

  // Firestore instance
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Firebase Auth instance
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Navigation index
  int _selectedNavIndex = 1; // Default to Reports

  @override
  void initState() {
    super.initState();
    _fetchWeightData();
  }

  // Fetch weight data from Firebase
  Future<void> _fetchWeightData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not logged in');
      }
      String userId = currentUser.uid;

      // Get the latest weight entry
      var latestWeightDoc = await _firestore
          .collection('user')
          .doc(userId)
          .collection('weight')
          .orderBy('date', descending: false)
          .limit(1)
          .get();

      if (latestWeightDoc.docs.isNotEmpty) {
        var data = latestWeightDoc.docs.first.data();
        setState(() {
          _currentWeight = {
            'weight': data['weight'] ?? 0.0,
            'bmi': data['bmi'] ?? 0.0,
            'goal': data['goal'] ?? 70.0,
            'unit': data['unit'] ?? 'kg',
            'date': (data['date'] as Timestamp).toDate(),
          };
        });
      }

      // Get last 30 days of weight entries
      var monthlyData = await _firestore
          .collection('user')
          .doc(userId)
          .collection('weight')
          .orderBy('date')
          .where('date',
              isGreaterThan: DateTime.now().subtract(const Duration(days: 30)))
          .get();

      List<Map<String, dynamic>> weights = [];
      for (var doc in monthlyData.docs) {
        var data = doc.data();
        weights.add({
          'weight': data['weight'] ?? 0.0,
          'date': (data['date'] as Timestamp).toDate(),
          'id': doc.id,
        });
      }

      setState(() {
        _monthlyWeights = weights;
        _isLoading = false;
      });
    } catch (e) {
      print('Error fetching weight data: $e');
      setState(() {
        _currentWeight = {
          'weight': 75.5,
          'bmi': 24.2,
          'goal': 70.0,
          'unit': 'kg',
          'date': DateTime.now(),
        };
        _monthlyWeights = List.generate(30, (index) {
          return {
            'weight': 75.5 - (index * 0.1),
            'date': DateTime.now().subtract(Duration(days: 29 - index)),
            'id': 'mock_$index',
          };
        });
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e.toString().contains('User not logged in')
                ? 'Please log in to view your weight data'
                : 'Error loading data: $e')),
      );
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
          'Weight Tracking',
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
              _fetchWeightData();
                        })
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
          : _buildWeightContent(),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.indigo,
        onPressed: () => _navigateToAddWeightScreen(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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

  Widget _buildWeightContent() {
    return RefreshIndicator(
      onRefresh: _fetchWeightData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCurrentWeightCard(),
            _buildWeightTrendChart(),
            _buildBMICard(),
            _buildGoalProgressCard(),
            _buildRecentEntriesCard(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentWeightCard() {
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
                  'Current Weight',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                Text(
                  'Last updated: ${DateFormat('MMM d, yyyy').format(_currentWeight['date'])}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    _currentWeight['weight'].toString(),
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _currentWeight['unit'],
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_monthlyWeights.length >= 2)
              Center(
                child: _buildWeightChangeIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeightChangeIndicator() {
    double latestWeight = _monthlyWeights.last['weight'];
    double previousWeight = _monthlyWeights[_monthlyWeights.length - 2]['weight'];
    double change = latestWeight - previousWeight;
    bool isPositive = change > 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isPositive ? Icons.arrow_upward : Icons.arrow_downward,
          color: isPositive ? Colors.red : Colors.green,
          size: 16,
        ),
        const SizedBox(width: 4),
        Text(
          '${change.abs().toStringAsFixed(1)} ${_currentWeight['unit']}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isPositive ? Colors.red : Colors.green,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          'since last entry',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildWeightTrendChart() {
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
                  'Weight Trend',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.calendar_month, size: 16),
                  label: const Text('Last 30 Days'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _monthlyWeights.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Text('No weight data available'),
                    ),
                  )
                : Container(
                    height: 200,
                    padding: const EdgeInsets.only(right: 16, top: 16),
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          horizontalInterval: 5,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (value) {
                            return FlLine(
                              color: Colors.grey[300],
                              strokeWidth: 1,
                            );
                          },
                        ),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              getTitlesWidget: (value, meta) {
                                if (value.toInt() % 5 == 0 &&
                                    value.toInt() < _monthlyWeights.length &&
                                    value.toInt() >= 0) {
                                  final date =
                                      _monthlyWeights[value.toInt()]['date']
                                          as DateTime;
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      DateFormat('d MMM').format(date),
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 10,
                                      ),
                                    ),
                                  );
                                }
                                return const Text('');
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  value.toInt().toString(),
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 10,
                                  ),
                                );
                              },
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
                          LineChartBarData(
                            spots: List.generate(_monthlyWeights.length, (index) {
                              return FlSpot(
                                index.toDouble(),
                                _monthlyWeights[index]['weight'],
                              );
                            }),
                            isCurved: true,
                            color: Colors.indigo,
                            barWidth: 3,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: Colors.indigo.withOpacity(0.2),
                            ),
                          ),
                          LineChartBarData(
                            spots: List.generate(_monthlyWeights.length, (index) {
                              return FlSpot(
                                index.toDouble(),
                                _currentWeight['goal'],
                              );
                            }),
                            isCurved: false,
                            color: Colors.amber,
                            barWidth: 2,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            dashArray: [5, 5],
                          ),
                        ],
                        minY: _calculateMinY(),
                        maxY: _calculateMaxY(),
                      ),
                    ),
                  ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('Weight', Colors.indigo),
                const SizedBox(width: 20),
                _buildLegendItem('Goal', Colors.amber),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _calculateMinY() {
    if (_monthlyWeights.isEmpty) return 50.0;
    double minWeight = _monthlyWeights
        .map((entry) => entry['weight'] as double)
        .reduce((min, weight) => weight < min ? weight : min);
    double goal = _currentWeight['goal'];
    return (minWeight < goal ? minWeight : goal) - 5;
  }

  double _calculateMaxY() {
    if (_monthlyWeights.isEmpty) return 100.0;
    double maxWeight = _monthlyWeights
        .map((entry) => entry['weight'] as double)
        .reduce((max, weight) => weight > max ? weight : max);
    double goal = _currentWeight['goal'];
    return (maxWeight > goal ? maxWeight : goal) + 5;
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

  Widget _buildBMICard() {
    String bmiCategory;
    Color bmiColor;
    if (_currentWeight['bmi'] < 18.5) {
      bmiCategory = 'Underweight';
      bmiColor = Colors.blue;
    } else if (_currentWeight['bmi'] < 25) {
      bmiCategory = 'Normal';
      bmiColor = Colors.green;
    } else if (_currentWeight['bmi'] < 30) {
      bmiCategory = 'Overweight';
      bmiColor = Colors.orange;
    } else {
      bmiCategory = 'Obese';
      bmiColor = Colors.red;
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
            const Text(
              'BMI',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _currentWeight['bmi'].toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'kg/m²',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: bmiColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        bmiCategory,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CustomPaint(
                    painter: BMIGaugePainter(
                      bmi: _currentWeight['bmi'],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'BMI Categories:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildBMICategoryLabel('Underweight', Colors.blue, '< 18.5'),
                _buildBMICategoryLabel('Normal', Colors.green, '18.5-24.9'),
                _buildBMICategoryLabel('Overweight', Colors.orange, '25-29.9'),
                _buildBMICategoryLabel('Obese', Colors.red, '≥ 30'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBMICategoryLabel(String label, Color color, String range) {
    return Column(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          range,
          style: TextStyle(
            fontSize: 9,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildGoalProgressCard() {
    final double progressPercentage =
        (_currentWeight['goal'] / _currentWeight['weight']).clamp(0.0, 1.0);
    final bool isReached = _currentWeight['weight'] <= _currentWeight['goal'];

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
                TextButton.icon(
                  onPressed: () {
                    _showEditGoalDialog();
                  },
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.indigo,
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
                    widthFactor: isReached ? 1.0 : progressPercentage,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isReached ? Colors.green : Colors.indigo,
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
                  'Current: ${_currentWeight['weight']} ${_currentWeight['unit']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Goal: ${_currentWeight['goal']} ${_currentWeight['unit']}',
                  style: TextStyle(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isReached
                  ? 'Congratulations! You have reached your goal weight!'
                  : 'Need to lose ${(_currentWeight['weight'] - _currentWeight['goal']).toStringAsFixed(1)} ${_currentWeight['unit']} to reach your goal',
              style: TextStyle(
                color: isReached ? Colors.green : Colors.grey[600],
                fontSize: 14,
                fontWeight: isReached ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditGoalDialog() {
    final TextEditingController goalController = TextEditingController(
      text: _currentWeight['goal'].toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Weight Goal'),
        content: TextField(
          controller: goalController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Goal Weight (${_currentWeight['unit']})',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                _currentWeight['goal'] =
                    double.tryParse(goalController.text) ?? _currentWeight['goal'];
              });
              _updateGoalInFirebase();
              Navigator.pop(context);
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

  Future<void> _updateGoalInFirebase() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) return;

      await _firestore
          .collection('user')
          .doc(currentUser.uid)
          .set({
            'weightGoal': _currentWeight['goal'],
          }, SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weight goal updated successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating weight goal: $e')),
      );
    }
  }

  Widget _buildRecentEntriesCard() {
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
                  'Recent Entries',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.list, size: 16),
                  label: const Text('View All'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _monthlyWeights.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No recent entries'),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount:
                        _monthlyWeights.length > 5 ? 5 : _monthlyWeights.length,
                    itemBuilder: (context, index) {
                      final entryIndex = _monthlyWeights.length - 1 - index;
                      final entry = _monthlyWeights[entryIndex];
                      final entryDate = entry['date'] as DateTime;

                      double? change;
                      if (entryIndex > 0) {
                        change = entry['weight'] -
                            _monthlyWeights[entryIndex - 1]['weight'];
                      }

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${entry['weight']} ${_currentWeight['unit']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          DateFormat('EEEE, MMM d, yyyy').format(entryDate),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        trailing: change != null
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    change > 0
                                        ? Icons.arrow_upward
                                        : Icons.arrow_downward,
                                    color: change > 0 ? Colors.red : Colors.green,
                                    size: 16,
                                  ),
                                  Text(
                                    '${change.abs().toStringAsFixed(1)} ${_currentWeight['unit']}',
                                    style: TextStyle(
                                      color:
                                          change > 0 ? Colors.red : Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              )
                            : const Text('First Entry'),
                        onTap: () {
                          _showEntryDetailsDialog(entry);
                        },
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  void _showEntryDetailsDialog(Map<String, dynamic> entry) {
    final DateTime entryDate = entry['date'] as DateTime;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Entry on ${DateFormat('MMM d, yyyy').format(entryDate)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Weight: ${entry['weight']} ${_currentWeight['unit']}'),
            const SizedBox(height: 8),
            Text('Date: ${DateFormat('EEEE, MMM d, yyyy').format(entryDate)}'),
            const SizedBox(height: 8),
            Text('Time: ${DateFormat('h:mm a').format(entryDate)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteWeightEntry(entry['id']);
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteWeightEntry(String entryId) async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) return;

      await _firestore
          .collection('user') // Fixed from 'users' to 'user'
          .doc(currentUser.uid)
          .collection('weight')
          .doc(entryId)
          .delete();

      _fetchWeightData();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weight entry deleted successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting entry: $e')),
      );
    }
  }

 
  void _navigateToAddWeightScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ManualWeightScreen(),
      ),
    );

    if (result == true && mounted) {
      _fetchWeightData();
    }
  }
}

class BMIGaugePainter extends CustomPainter {
  final double bmi;

  BMIGaugePainter({required this.bmi});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final paintBackground = Paint()
      ..color = Colors.grey[200]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 5),
      -3 * pi / 4,
      6 * pi / 4,
      false,
      paintBackground,
    );

    final bmiProgress = (bmi / 40).clamp(0.0, 1.0);
    final sweepAngle = bmiProgress * 6 * pi / 4;

    Color gaugeColor;
    if (bmi < 18.5) {
      gaugeColor = Colors.blue;
    } else if (bmi < 25) {
      gaugeColor = Colors.green;
    } else if (bmi < 30) {
      gaugeColor = Colors.orange;
    } else {
      gaugeColor = Colors.red;
    }

    final paintProgress = Paint()
      ..color = gaugeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 5),
      -3 * pi / 4,
      sweepAngle,
      false,
      paintProgress,
    );

    final needleLength = radius - 20;
    final needleAngle = -3 * pi / 4 + sweepAngle;
    final needleStart = center;
    final needleEnd = Offset(
      center.dx + needleLength * cos(needleAngle),
      center.dy + needleLength * sin(needleAngle),
    );

    final paintNeedle = Paint()
      ..color = Colors.grey[800]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawLine(needleStart, needleEnd, paintNeedle);

    final paintCenter = Paint()
      ..color = Colors.grey[800]!
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 5, paintCenter);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}