import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

import '../screens/dashboard.dart';
import '../screens/insight_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/weight.dart';
import '../screens/activity.dart';
import '../widgets/bottom_nav_bar.dart'; // Adjust the path based on your file structure
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with TickerProviderStateMixin {
  // Firebase instances
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  
  // Selected index for bottom navigation
  int _selectedNavIndex = 1; // Set to 1 for Reports tab
  
  // Loading state
  bool _isLoading = true;
  bool _isGeneratingReport = false;
  
  // Selected date range
  String _selectedDateRange = 'Last 7 Days';
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();
  
  // Tab controller
  late TabController _tabController;
  
  // Report data
  Map<String, dynamic> _reportData = {
    'blood_pressure': [],
    'weight': [],
    'activity': [],
    'health_summary': {},
  };
  
  // Metrics for summary cards
  Map<String, dynamic> _summaryMetrics = {
    'bp_highest': {'systolic': 0, 'diastolic': 0, 'date': DateTime.now()},
    'bp_lowest': {'systolic': 999, 'diastolic': 999, 'date': DateTime.now()},
    'bp_average': {'systolic': 0, 'diastolic': 0},
    'weight_highest': {'value': 0.0, 'date': DateTime.now()},
    'weight_lowest': {'value': 999.0, 'date': DateTime.now()},
    'weight_average': 0.0,
    'steps_highest': {'value': 0, 'date': DateTime.now()},
    'steps_average': 0,
    'total_activity_minutes': 0,
  };

  @override
void initState() {
  super.initState();
  
  // Initialize tab controller
  _tabController = TabController(length: 3, vsync: this);
  _tabController.addListener(_handleTabSelection);
  
  // Load report data with timeout
  _loadReportDataWithTimeout();
}

void _loadReportDataWithTimeout() {
  _loadReportData();
  
  // Add a 15-second timeout
  Future.delayed(const Duration(seconds: 15), () {
    if (_isLoading && mounted) {
      print('Loading timed out - resetting loading state');
      setState(() {
        _isLoading = false;
      });
      
      // Add fallback data for UI rendering
      if (_reportData['blood_pressure'].isEmpty && 
          _reportData['weight'].isEmpty && 
          _reportData['activity'].isEmpty) {
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to load data. Please check your connection and try again.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  });
}
  
  void _handleTabSelection() {
    if (_tabController.indexIsChanging) {
      return;
    }
    // Could add specific behavior when tabs change
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _loadReportData() async {
  setState(() {
    _isLoading = true;
  });
  
  try {
    // Get current user
    User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      // Handle not logged in state
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to view your reports')),
      );
      
      setState(() {
        _isLoading = false;
      });
      return;
    }
    
    String userId = currentUser.uid;
    print('Current user ID: $userId');
    
    // If you're testing with a specific user ID, you can override here
    // Comment this out in production!
    // userId = "n1IPNNKArRNz4LQre6FKNkNOH3z1";
    
    // Load blood pressure data
    await _loadBloodPressureData(userId);
    
    // Load weight data
    await _loadWeightData(userId);
    
    // Load activity data
    await _loadActivityData(userId);
    
    // Calculate summary metrics
    _calculateSummaryMetrics();
    
    print('All data loaded successfully');
    
    setState(() {
      _isLoading = false;
    });
  } catch (e) {
    print('Error loading report data: $e');
    
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
  
  Future<void> _loadBloodPressureData(String userId) async {
  try {
    print('Loading blood pressure data for user: $userId');
    
    // Query blood pressure readings within date range
    var bpDocs = await _firestore
        .collection('vital_signs')
        .where('user_id', isEqualTo: userId)
        .where('timestamp', isGreaterThanOrEqualTo: _startDate)
        .where('timestamp', isLessThanOrEqualTo: _endDate)
        .orderBy('timestamp', descending: false)
        .get();
    
    print('Found ${bpDocs.docs.length} blood pressure readings');
    
    List<Map<String, dynamic>> bpReadings = [];
    
    if (bpDocs.docs.isNotEmpty) {
      for (var doc in bpDocs.docs) {
        var data = doc.data();
        print('Raw BP data: $data'); // Debug print
        
        // Safer parsing
        int systolic = 0;
        int diastolic = 0;
        int pulse = 0;
        
        // Handle systolic BP
        if (data.containsKey('systolic_BP')) {
          var systolicValue = data['systolic_BP'];
          if (systolicValue != null) {
            if (systolicValue is int) {
              systolic = systolicValue;
            } else if (systolicValue is String) {
              systolic = int.tryParse(systolicValue) ?? 0;
            }
          }
        }
        
        // Handle diastolic
        if (data.containsKey('diastolic')) {
          var diastolicValue = data['diastolic'];
          if (diastolicValue != null) {
            if (diastolicValue is int) {
              diastolic = diastolicValue;
            } else if (diastolicValue is String) {
              diastolic = int.tryParse(diastolicValue) ?? 0;
            }
          }
        }
        
        // Handle pulse
        if (data.containsKey('pulse')) {
          var pulseValue = data['pulse'];
          if (pulseValue != null) {
            if (pulseValue is int) {
              pulse = pulseValue;
            } else if (pulseValue is String) {
              pulse = int.tryParse(pulseValue) ?? 0;
            }
          }
        }
        
        bpReadings.add({
          'systolic_BP': systolic,
          'systolic': systolic, // Add this for compatibility
          'diastolic': diastolic,
          'pulse': pulse,
          'timestamp': data['timestamp'],
          'date': (data['timestamp'] as Timestamp).toDate(),
          'id': doc.id,
        });
      }
    }
    
    setState(() {
      _reportData['blood_pressure'] = bpReadings;
    });
  } catch (e) {
    print('Error loading blood pressure data: $e');
    rethrow;
  }
}

Future<void> _loadWeightData(String userId) async {
  try {
    print('Loading weight data for user: $userId');
    
    // Query weight readings within date range
    var weightDocs = await _firestore
        .collection('weight')
        .where('user_id', isEqualTo: userId)
        .where('timestamp', isGreaterThanOrEqualTo: _startDate)
        .where('timestamp', isLessThanOrEqualTo: _endDate)
        .orderBy('timestamp', descending: false)
        .get();
    
    print('Found ${weightDocs.docs.length} weight readings');
    
    List<Map<String, dynamic>> weightReadings = [];
    
    if (weightDocs.docs.isNotEmpty) {
      for (var doc in weightDocs.docs) {
        var data = doc.data();
        print('Raw weight data: $data'); // Debug print
        
        // More careful parsing to avoid null errors
        double weight = 0.0;
        double bmi = 0.0;
        
        // Handle weight - using safer parsing approach
        if (data.containsKey('current')) {
          var currentValue = data['current'];
          if (currentValue != null) {
            if (currentValue is double) {
              weight = currentValue;
            } else if (currentValue is int) {
              weight = currentValue.toDouble();
            } else if (currentValue is String) {
              weight = double.tryParse(currentValue) ?? 0.0;
            }
          }
        }
        
        // Handle BMI - using safer parsing approach
        if (data.containsKey('bmi')) {
          var bmiValue = data['bmi'];
          if (bmiValue != null) {
            if (bmiValue is double) {
              bmi = bmiValue;
            } else if (bmiValue is int) {
              bmi = bmiValue.toDouble();
            } else if (bmiValue is String) {
              bmi = double.tryParse(bmiValue) ?? 0.0;
            }
          }
        }
        
        weightReadings.add({
          'weight': weight,
          'bmi': bmi,
          'timestamp': data['timestamp'],
          'date': (data['timestamp'] as Timestamp).toDate(),
          'id': doc.id,
          'current': weight, // Add this for compatibility with other methods
        });
      }
    }
    
    setState(() {
      _reportData['weight'] = weightReadings;
    });
  } catch (e) {
    print('Error loading weight data: $e');
    rethrow;
  }
}

Future<void> _loadActivityData(String userId) async {
  try {
    print('Loading activity data for user: $userId');
    
    // Query activity data within date range
    var activityDocs = await _firestore
        .collection('activity')
        .where('user_id', isEqualTo: userId)
        .where('timestamp', isGreaterThanOrEqualTo: _startDate)
        .where('timestamp', isLessThanOrEqualTo: _endDate)
        .orderBy('timestamp', descending: false)
        .get();
    
    print('Found ${activityDocs.docs.length} activity records');
    
    List<Map<String, dynamic>> activityReadings = [];
    
    if (activityDocs.docs.isNotEmpty) {
      for (var doc in activityDocs.docs) {
        var data = doc.data();
        print('Raw activity data: $data'); // Debug print
        
        // Safer parsing of string values
        int steps = 0;
        int calories = 0;
        double distance = 0.0;
        int activeMinutes = 0;
        
        // Parse steps
        if (data.containsKey('steps')) {
          var stepsValue = data['steps'];
          if (stepsValue != null) {
            if (stepsValue is int) {
              steps = stepsValue;
            } else if (stepsValue is String) {
              steps = int.tryParse(stepsValue) ?? 0;
            }
          }
        }
        
        // Parse calories
        if (data.containsKey('calories')) {
          var caloriesValue = data['calories'];
          if (caloriesValue != null) {
            if (caloriesValue is int) {
              calories = caloriesValue;
            } else if (caloriesValue is String) {
              calories = int.tryParse(caloriesValue) ?? 0;
            }
          }
        }
        
        // Parse distance
        if (data.containsKey('distance')) {
          var distanceValue = data['distance'];
          if (distanceValue != null) {
            if (distanceValue is double) {
              distance = distanceValue;
            } else if (distanceValue is int) {
              distance = distanceValue.toDouble();
            } else if (distanceValue is String) {
              distance = double.tryParse(distanceValue) ?? 0.0;
            }
          }
        }
        
        // Parse active_minutes
        if (data.containsKey('active_minutes')) {
          var activeValue = data['active_minutes'];
          if (activeValue != null) {
            if (activeValue is int) {
              activeMinutes = activeValue;
            } else if (activeValue is String) {
              activeMinutes = int.tryParse(activeValue) ?? 0;
            }
          }
        }
        
        activityReadings.add({
          'steps': steps,
          'calories': calories,
          'distance': distance,
          'active_minutes': activeMinutes,
          'timestamp': data['timestamp'],
          'date': (data['timestamp'] as Timestamp).toDate(),
          'id': doc.id,
        });
      }
    }
    
    setState(() {
      _reportData['activity'] = activityReadings;
    });
  } catch (e) {
    print('Error loading activity data: $e');
    rethrow;
  }
}
  
  void _calculateSummaryMetrics() {
  try {
    // Reset summary metrics
    _summaryMetrics = {
      'bp_highest': {'systolic': 0, 'diastolic': 0, 'date': DateTime.now()},
      'bp_lowest': {'systolic': 999, 'diastolic': 999, 'date': DateTime.now()},
      'bp_average': {'systolic': 0, 'diastolic': 0},
      'weight_highest': {'value': 0.0, 'date': DateTime.now()},
      'weight_lowest': {'value': 999.0, 'date': DateTime.now()},
      'weight_average': 0.0,
      'steps_highest': {'value': 0, 'date': DateTime.now()},
      'steps_average': 0,
      'total_activity_minutes': 0,
    };

    // Process blood pressure data
    final bpList = _reportData['blood_pressure'] as List;
    if (bpList.isNotEmpty) {
      int systolicSum = 0;
      int diastolicSum = 0;
      
      for (var reading in bpList) {
        // Use systolic_BP field name
        if (reading.containsKey('systolic_BP') && reading['systolic_BP'] != null) {
          int systolicBP = reading['systolic_BP'] as int;
          int diastolic = reading['diastolic'] as int;
          
          if (systolicBP > _summaryMetrics['bp_highest']['systolic']) {
            _summaryMetrics['bp_highest'] = {
              'systolic': systolicBP,
              'diastolic': diastolic,
              'date': reading['date'],
            };
          }
          
          if (systolicBP < _summaryMetrics['bp_lowest']['systolic']) {
            _summaryMetrics['bp_lowest'] = {
              'systolic': systolicBP,
              'diastolic': diastolic,
              'date': reading['date'],
            };
          }
          
          systolicSum += systolicBP;
          diastolicSum += diastolic;
        }
      }
      
      if (bpList.length > 0) {
        _summaryMetrics['bp_average'] = {
          'systolic': (systolicSum / bpList.length).round(),
          'diastolic': (diastolicSum / bpList.length).round(),
        };
      }
    }

    // Process weight data
    final weightList = _reportData['weight'] as List;
    if (weightList.isNotEmpty) {
      double weightSum = 0.0;
      
      for (var reading in weightList) {
        if (reading.containsKey('weight') && reading['weight'] != null) {
          // Safely handle weight value
          double weightValue = 0.0;
          
          if (reading['weight'] is int) {
            weightValue = (reading['weight'] as int).toDouble();
          } else if (reading['weight'] is double) {
            weightValue = reading['weight'] as double;
          }
          
          if (weightValue > _summaryMetrics['weight_highest']['value']) {
            _summaryMetrics['weight_highest'] = {
              'value': weightValue,
              'date': reading['date'],
            };
          }
          
          if (weightValue < _summaryMetrics['weight_lowest']['value']) {
            _summaryMetrics['weight_lowest'] = {
              'value': weightValue,
              'date': reading['date'],
            };
          }
          
          weightSum += weightValue;
        }
      }
      
      if (weightList.length > 0) {
        _summaryMetrics['weight_average'] =
            double.parse((weightSum / weightList.length).toStringAsFixed(1));
      }
    }

    // Process activity data
    final activityList = _reportData['activity'] as List;
    if (activityList.isNotEmpty) {
      int stepsSum = 0;
      int totalActiveMinutes = 0;
      
      for (var reading in activityList) {
        if (reading.containsKey('steps') && reading['steps'] != null) {
          // Safely handle steps value
          int stepsValue = reading['steps'] as int;
          
          if (stepsValue > _summaryMetrics['steps_highest']['value']) {
            _summaryMetrics['steps_highest'] = {
              'value': stepsValue,
              'date': reading['date'],
            };
          }
          
          stepsSum += stepsValue;
        }
        
        if (reading.containsKey('active_minutes') && reading['active_minutes'] != null) {
          totalActiveMinutes += reading['active_minutes'] as int;
        }
      }
      
      if (activityList.length > 0) {
        _summaryMetrics['steps_average'] = (stepsSum / activityList.length).round();
        _summaryMetrics['total_activity_minutes'] = totalActiveMinutes;
      }
    }
  } catch (e) {
    print('Error calculating summary metrics: $e');
    // Fallback to ensure the app doesn't crash
    _summaryMetrics = {
      'bp_highest': {'systolic': 0, 'diastolic': 0, 'date': DateTime.now()},
      'bp_lowest': {'systolic': 0, 'diastolic': 0, 'date': DateTime.now()},
      'bp_average': {'systolic': 0, 'diastolic': 0},
      'weight_highest': {'value': 0.0, 'date': DateTime.now()},
      'weight_lowest': {'value': 0.0, 'date': DateTime.now()},
      'weight_average': 0.0,
      'steps_highest': {'value': 0, 'date': DateTime.now()},
      'steps_average': 0,
      'total_activity_minutes': 0,
    };
  }
}
  
  void _loadMockData() {
    final DateTime now = DateTime.now();
    final random = Random();
    
    // Generate mock blood pressure readings
    List<Map<String, dynamic>> mockBp = List.generate(
      7,
      (index) => {
        'systolic': 110 + random.nextInt(30),
        'diastolic': 70 + random.nextInt(20),
        'pulse': 65 + random.nextInt(25),
        'date': now.subtract(Duration(days: 6 - index)),
        'timestamp': Timestamp.fromDate(now.subtract(Duration(days: 6 - index))),
      },
    );
    
    // Generate mock weight readings
    List<Map<String, dynamic>> mockWeight = List.generate(
      7,
      (index) => {
        'weight': 70.0 + random.nextDouble() * 3,
        'bmi': 22.0 + random.nextDouble() * 2,
        'date': now.subtract(Duration(days: 6 - index)),
        'timestamp': Timestamp.fromDate(now.subtract(Duration(days: 6 - index))),
      },
    );
    
    // Generate mock activity readings
    List<Map<String, dynamic>> mockActivity = List.generate(
      7,
      (index) => {
        'steps': 5000 + random.nextInt(5000),
        'calories': 200 + random.nextInt(300),
        'distance': 3.0 + random.nextDouble() * 3,
        'active_minutes': 20 + random.nextInt(40),
        'date': now.subtract(Duration(days: 6 - index)),
        'timestamp': Timestamp.fromDate(now.subtract(Duration(days: 6 - index))),
      },
    );
    
    setState(() {
      _reportData = {
        'blood_pressure': mockBp,
        'weight': mockWeight,
        'activity': mockActivity,
      };
    });
    
    // Calculate summary metrics
    _calculateSummaryMetrics();
  }
  
  Future<void> _changeDateRange(String range) async {
    DateTime newStartDate;
    final DateTime now = DateTime.now();
    
    switch (range) {
      case 'Last 7 Days':
        newStartDate = now.subtract(const Duration(days: 7));
        break;
      case 'Last 30 Days':
        newStartDate = now.subtract(const Duration(days: 30));
        break;
      case 'Last 90 Days':
        newStartDate = now.subtract(const Duration(days: 90));
        break;
      default:
        newStartDate = now.subtract(const Duration(days: 7));
    }
    
    setState(() {
      _selectedDateRange = range;
      _startDate = newStartDate;
      _endDate = now;
      _isLoading = true;
    });
    
    // Reload report data with new date range
    await _loadReportData();
  }
  
 // Replace with
Future<void> _generateFullReport() async {
  setState(() {
    _isGeneratingReport = true;
  });
  
  try {
    // Request storage permission for Android
    if (Platform.isAndroid) {
      var status = await Permission.storage.request();
      if (!status.isGranted) {
        throw Exception('Storage permission denied');
      }
    }
    
    // Create PDF document
    final pdf = pw.Document();
    
    // Add title page
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  'Health Report',
                  style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Generated on ${DateFormat('MMMM d, yyyy').format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 16),
                ),
                pw.SizedBox(height: 40),
                pw.Text(
                  'Report Period:',
                  style: const pw.TextStyle(fontSize: 14),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  '${DateFormat('MMM d, yyyy').format(_startDate)} - ${DateFormat('MMM d, yyyy').format(_endDate)}',
                  style: const pw.TextStyle(fontSize: 16),
                ),
              ],
            ),
          );
        },
      ),
    );
    
    // Add summary page
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Health Summary',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 20),
              
              // Overall stats
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Overall Statistics',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                      children: [
                        pw.Column(
                          children: [
                            pw.Text(
                              'BP Average',
                              style: const pw.TextStyle(fontSize: 12),
                            ),
                            pw.SizedBox(height: 5),
                            pw.Text(
                              '${_summaryMetrics['bp_average']['systolic']}/${_summaryMetrics['bp_average']['diastolic']}',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        pw.Column(
                          children: [
                            pw.Text(
                              'Weight Average',
                              style: const pw.TextStyle(fontSize: 12),
                            ),
                            pw.SizedBox(height: 5),
                            pw.Text(
                              '${_summaryMetrics['weight_average']} kg',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        pw.Column(
                          children: [
                            pw.Text(
                              'Average Steps',
                              style: const pw.TextStyle(fontSize: 12),
                            ),
                            pw.SizedBox(height: 5),
                            pw.Text(
                              '${_summaryMetrics['steps_average']}',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              pw.SizedBox(height: 20),
              
              // Blood pressure section
              if (_reportData['blood_pressure'].isNotEmpty) ...[
                pw.Text(
                  'Blood Pressure',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _buildPdfMetricBox(
                      'Highest',
                      '${_summaryMetrics['bp_highest']['systolic']}/${_summaryMetrics['bp_highest']['diastolic']}',
                      'Date: ${DateFormat('MM/dd').format(_summaryMetrics['bp_highest']['date'])}'
                    ),
                    _buildPdfMetricBox(
                      'Lowest',
                      '${_summaryMetrics['bp_lowest']['systolic']}/${_summaryMetrics['bp_lowest']['diastolic']}',
                      'Date: ${DateFormat('MM/dd').format(_summaryMetrics['bp_lowest']['date'])}'
                    ),
                    _buildPdfMetricBox(
                      'Average',
                      '${_summaryMetrics['bp_average']['systolic']}/${_summaryMetrics['bp_average']['diastolic']}',
                      ''
                    ),
                  ],
                ),
              ],
              
              pw.SizedBox(height: 20),
              
              // Weight section
              if (_reportData['weight'].isNotEmpty) ...[
                pw.Text(
                  'Weight',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _buildPdfMetricBox(
                      'Highest',
                      '${_summaryMetrics['weight_highest']['value'].toStringAsFixed(1)} kg',
                      'Date: ${DateFormat('MM/dd').format(_summaryMetrics['weight_highest']['date'])}'
                    ),
                    _buildPdfMetricBox(
                      'Lowest',
                      '${_summaryMetrics['weight_lowest']['value'].toStringAsFixed(1)} kg',
                      'Date: ${DateFormat('MM/dd').format(_summaryMetrics['weight_lowest']['date'])}'
                    ),
                    _buildPdfMetricBox(
                      'Average',
                      '${_summaryMetrics['weight_average']} kg',
                      ''
                    ),
                  ],
                ),
              ],
              
              pw.SizedBox(height: 20),
              
              // Activity section
              if (_reportData['activity'].isNotEmpty) ...[
                pw.Text(
                  'Activity',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _buildPdfMetricBox(
                      'Highest Steps',
                      '${_summaryMetrics['steps_highest']['value']}',
                      'Date: ${DateFormat('MM/dd').format(_summaryMetrics['steps_highest']['date'])}'
                    ),
                    _buildPdfMetricBox(
                      'Average Steps',
                      '${_summaryMetrics['steps_average']}',
                      ''
                    ),
                    _buildPdfMetricBox(
                      'Active Minutes',
                      '${_summaryMetrics['total_activity_minutes']}',
                      'Total'
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
    
    // Add detailed pages for each category
    if (_reportData['blood_pressure'].isNotEmpty) {
      pdf.addPage(_createBloodPressureDetailPage());
    }
    
    if (_reportData['weight'].isNotEmpty) {
      pdf.addPage(_createWeightDetailPage());
    }
    
    if (_reportData['activity'].isNotEmpty) {
      pdf.addPage(_createActivityDetailPage());
    }
    
    // Save the PDF file
    final String dir;
    final String fileName = 'health_report_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
    
    if (Platform.isAndroid) {
      dir = (await getExternalStorageDirectory())!.path;
    } else if (Platform.isIOS) {
      dir = (await getApplicationDocumentsDirectory()).path;
    } else {
      dir = (await getDownloadsDirectory())!.path;
    }
    
    final file = File('$dir/$fileName');
    await file.writeAsBytes(await pdf.save());
    
    // Share or open the file
    if (Platform.isIOS || Platform.isAndroid) {
      await Share.shareFiles([file.path], text: 'Your Health Report');
    } else {
      await OpenFile.open(file.path);
    }
    
    if (mounted) {
      setState(() {
        _isGeneratingReport = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Health report saved to $fileName'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () async {
              await OpenFile.open(file.path);
            },
          ),
        ),
      );
    }
    
  } catch (e) {
    print('Error generating report: $e');
    if (mounted) {
      setState(() {
        _isGeneratingReport = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating report: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
}

// Helper method to create a metric box for the PDF
pw.Widget _buildPdfMetricBox(String title, String value, String subtitle) {
  return pw.Container(
    width: 120,
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300),
      borderRadius: pw.BorderRadius.circular(5),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          title,
          style: const pw.TextStyle(
            fontSize: 12,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            subtitle,
            style: const pw.TextStyle(
              fontSize: 10,
            ),
          ),
        ],
      ],
    ),
  );
}

// Create a detail page for blood pressure readings
pw.Page _createBloodPressureDetailPage() {
  // Sort readings by date
  final sortedReadings = List<Map<String, dynamic>>.from(_reportData['blood_pressure'])
    ..sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
  
  return pw.Page(
    build: (pw.Context context) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Blood Pressure Readings',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Period: ${DateFormat('MMM d, yyyy').format(_startDate)} - ${DateFormat('MMM d, yyyy').format(_endDate)}',
            style: const pw.TextStyle(fontSize: 12),
          ),
          pw.SizedBox(height: 20),
          
          // Table header
          pw.Container(
            color: PdfColors.grey200,
            padding: const pw.EdgeInsets.all(5),
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: 3,
                  child: pw.Text(
                    'Date',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    'Systolic',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    'Diastolic',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    'Pulse',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    'Status',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          
          // Table rows
          pw.ListView.builder(
            itemCount: sortedReadings.length,
            itemBuilder: (context, index) {
              final reading = sortedReadings[index];
              final date = reading['date'] as DateTime;
              final category = _getBPCategory(reading['systolic'], reading['diastolic']);
              
              return pw.Container(
                color: index % 2 == 0 ? PdfColors.grey100 : PdfColors.white,
                padding: const pw.EdgeInsets.all(5),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 3,
                      child: pw.Text(DateFormat('MM/dd/yyyy HH:mm').format(date)),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text('${reading['systolic']}'),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text('${reading['diastolic']}'),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text('${reading['pulse']}'),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text(category),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      );
    },
  );
}

// Create a detail page for weight readings
pw.Page _createWeightDetailPage() {
  // Sort readings by date
  final sortedReadings = List<Map<String, dynamic>>.from(_reportData['weight'])
    ..sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
  
  return pw.Page(
    build: (pw.Context context) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Weight Readings',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Period: ${DateFormat('MMM d, yyyy').format(_startDate)} - ${DateFormat('MMM d, yyyy').format(_endDate)}',
            style: const pw.TextStyle(fontSize: 12),
          ),
          pw.SizedBox(height: 20),
          
          // Table header
          pw.Container(
            color: PdfColors.grey200,
            padding: const pw.EdgeInsets.all(5),
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: 3,
                  child: pw.Text(
                    'Date',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    'Weight (kg)',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    'BMI',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          
          // Table rows
          pw.ListView.builder(
            itemCount: sortedReadings.length,
            itemBuilder: (context, index) {
              final reading = sortedReadings[index];
              final date = reading['date'] as DateTime;
              
              return pw.Container(
                color: index % 2 == 0 ? PdfColors.grey100 : PdfColors.white,
                padding: const pw.EdgeInsets.all(5),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 3,
                      child: pw.Text(DateFormat('MM/dd/yyyy HH:mm').format(date)),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text('${reading['weight'].toStringAsFixed(1)}'),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text('${reading['bmi'].toStringAsFixed(1)}'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      );
    },
  );
}

// Create a detail page for activity readings
pw.Page _createActivityDetailPage() {
  // Sort readings by date
  final sortedReadings = List<Map<String, dynamic>>.from(_reportData['activity'])
    ..sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
  
  return pw.Page(
    build: (pw.Context context) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Activity Records',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Period: ${DateFormat('MMM d, yyyy').format(_startDate)} - ${DateFormat('MMM d, yyyy').format(_endDate)}',
            style: const pw.TextStyle(fontSize: 12),
          ),
          pw.SizedBox(height: 20),
          
          // Table header
          pw.Container(
            color: PdfColors.grey200,
            padding: const pw.EdgeInsets.all(5),
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: 3,
                  child: pw.Text(
                    'Date',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    'Steps',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    'Distance (km)',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    'Calories',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    'Active Min',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          
          // Table rows
          pw.ListView.builder(
            itemCount: sortedReadings.length,
            itemBuilder: (context, index) {
              final reading = sortedReadings[index];
              final date = reading['date'] as DateTime;
              
              return pw.Container(
                color: index % 2 == 0 ? PdfColors.grey100 : PdfColors.white,
                padding: const pw.EdgeInsets.all(5),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 3,
                      child: pw.Text(DateFormat('MM/dd/yyyy').format(date)),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text('${reading['steps']}'),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text('${reading['distance']}'),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text('${reading['calories']}'),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text('${reading['active_minutes']}'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      );
    },
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        elevation: 0,
        title: const Text(
          'Health Reports',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadReportData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Summary'),
            Tab(text: 'Charts'),
            Tab(text: 'Details'),
          ],
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
        : TabBarView(
            controller: _tabController,
            children: [
              _buildSummaryTab(),
              _buildChartsTab(),
              _buildDetailsTab(),
            ],
          ),
      bottomNavigationBar: BottomNavBar(
      selectedIndex: _selectedNavIndex,
      onItemTapped: (index) {
        if (index == _selectedNavIndex) {
          return; // Already on Reports screen
        }
        setState(() {
          _selectedNavIndex = index;
        });
        // Navigate to appropriate screen
        switch (index) {
          case 0: // Home
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const DashboardScreen()),
            );
            break;
          case 1: // Reports
            // Stay on this screen
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isGeneratingReport ? null : _generateFullReport,
        backgroundColor: Colors.indigo,
        icon: _isGeneratingReport 
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.download),
        label: Text(_isGeneratingReport ? 'Generating...' : 'Export Report'),
      ),
    );
  }
  
  Widget _buildSummaryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateRangeSelector(),
          const SizedBox(height: 16),
          _buildOverallSummaryCard(),
          const SizedBox(height: 16),
          _buildBloodPressureSummaryCard(),
          const SizedBox(height: 16),
          _buildWeightSummaryCard(),
          const SizedBox(height: 16),
          _buildActivitySummaryCard(),
          const SizedBox(height: 40), // Space for floating action button
        ],
      ),
    );
  }
  
  Widget _buildDateRangeSelector() {
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
              'Select Time Period',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildDateRangeChip('Last 7 Days'),
                  const SizedBox(width: 10),
                  _buildDateRangeChip('Last 30 Days'),
                  const SizedBox(width: 10),
                  _buildDateRangeChip('Last 90 Days'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'From: ${DateFormat('MMM d, yyyy').format(_startDate)} - To: ${DateFormat('MMM d, yyyy').format(_endDate)}',
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
  
  Widget _buildDateRangeChip(String label) {
    final bool isSelected = _selectedDateRange == label;
    
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          _changeDateRange(label);
        }
      },
      backgroundColor: Colors.grey[200],
      selectedColor: Colors.indigo[100],
      checkmarkColor: Colors.indigo,
      labelStyle: TextStyle(
        color: isSelected ? Colors.indigo : Colors.black,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
  
  Widget _buildOverallSummaryCard() {
    final int recordCount = _reportData['blood_pressure'].length + 
                          _reportData['weight'].length + 
                          _reportData['activity'].length;
                          
    // Calculate health score (mock calculation from 0-100)
    final Random random = Random();
    final int healthScore = 65 + random.nextInt(30); // Between 65-95
    
    // Determine health status from score
    String healthStatus;
    Color statusColor;
    
    if (healthScore >= 85) {
      healthStatus = 'Excellent';
      statusColor = Colors.green;
    } else if (healthScore >= 70) {
      healthStatus = 'Good';
      statusColor = Colors.blue;
    } else if (healthScore >= 60) {
      healthStatus = 'Fair';
      statusColor = Colors.orange;
    } else {
      healthStatus = 'Needs Attention';
      statusColor = Colors.red;
    }
    
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
            const Row(
              children: [
                Icon(
                  Icons.health_and_safety,
                  color: Colors.indigo,
                  size: 28,
                ),
                SizedBox(width: 12),
                Text(
                  'Overall Health Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Health Score',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          healthScore.toString(),
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '/ 100',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Status',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        healthStatus,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSummaryMetricColumn('Records', recordCount.toString(), Icons.checklist),
                _buildSummaryMetricColumn(
                  'BP Average', 
                  '${_summaryMetrics['bp_average']['systolic']}/${_summaryMetrics['bp_average']['diastolic']}',
                  Icons.favorite,
                ),
                _buildSummaryMetricColumn(
                  'Weight Avg', 
                  '${_summaryMetrics['weight_average']} kg',
                  Icons.monitor_weight,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSummaryMetricColumn(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          color: Colors.indigo[300],
          size: 22,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

     // Helper method to determine BP category
  String _getBPCategory(int systolic, int diastolic) {
  if (systolic >= 180 || diastolic >= 120) {
    return 'Crisis';
  } else if (systolic >= 140 || diastolic >= 90) {
    return 'High';
  } else if (systolic >= 130 || diastolic >= 80) {
    return 'Elevated';
  } else if (systolic < 130 && diastolic < 80) { // Combined Normal conditions
    return 'Normal';
  } else if (systolic < 90 || diastolic < 60) {
    return 'Low';
  } else {
    return 'Normal';
  }
}

 Widget _buildBPMetricBlock(String label, String value, String category, {DateTime? date}) {
    Color categoryColor;
    
    // Determine color based on category
    switch (category) {
      case 'Crisis':
        categoryColor = Colors.red[700]!;
        break;
      case 'High':
        categoryColor = Colors.red;
        break;
      case 'Elevated':
        categoryColor = Colors.orange;
        break;
      case 'Normal':
        categoryColor = Colors.green;
        break;
      case 'Low':
        categoryColor = Colors.blue;
        break;
      default:
        categoryColor = Colors.grey;
    }
    
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: categoryColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                category,
                style: TextStyle(
                  color: categoryColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (date != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  DateFormat('MM/dd').format(date),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[500],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildWeightSummaryCard() {
    final int readingsCount = _reportData['weight'].length;
    
    // Skip if no readings
    if (readingsCount == 0) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text('No weight data for selected period'),
          ),
        ),
      );
    }
    
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.monitor_weight,
                      color: Colors.indigo,
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Weight Summary',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.indigo[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$readingsCount Readings',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.indigo,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildWeightMetricBlock(
                  'Average',
                  '${_summaryMetrics['weight_average']} kg',
                ),
                _buildWeightMetricBlock(
                  'Highest',
                  '${_summaryMetrics['weight_highest']['value'].toStringAsFixed(1)} kg',
                  date: _summaryMetrics['weight_highest']['date'],
                ),
                _buildWeightMetricBlock(
                  'Lowest',
                  '${_summaryMetrics['weight_lowest']['value'].toStringAsFixed(1)} kg',
                  date: _summaryMetrics['weight_lowest']['date'],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_reportData['weight'].length >= 2)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Weight Change:',
                      style: TextStyle(
                        fontSize: 14,
                      ),
                    ),
                    _buildWeightChangeIndicator(),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                // Navigate to weight screen
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const WeightScreen()),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.indigo),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'View Weight Details',
                    style: TextStyle(
                      color: Colors.indigo,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildWeightMetricBlock(String label, String value, {DateTime? date}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (date != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  DateFormat('MM/dd').format(date),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[500],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildWeightChangeIndicator() {
    // Calculate weight change between first and last reading
    double firstWeight = _reportData['weight'].first['weight'];
    double lastWeight = _reportData['weight'].last['weight'];
    double change = lastWeight - firstWeight;
    bool isPositive = change > 0;
    
    return Row(
      children: [
        Icon(
          isPositive ? Icons.arrow_upward : Icons.arrow_downward,
          color: isPositive ? Colors.red : Colors.green,
          size: 16,
        ),
        const SizedBox(width: 4),
        Text(
          '${change.abs().toStringAsFixed(1)} kg',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isPositive ? Colors.red : Colors.green,
          ),
        ),
      ],
    );
  }
  
  Widget _buildActivitySummaryCard() {
    final int readingsCount = _reportData['activity'].length;
    
    // Skip if no readings
    if (readingsCount == 0) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text('No activity data for selected period'),
          ),
        ),
      );
    }
    
    // Calculate total steps
    int totalSteps = 0;
    for (var reading in _reportData['activity']) {
      totalSteps += reading['steps'] as int;
    }
    
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.directions_run,
                      color: Colors.green,
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Activity Summary',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.indigo[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$readingsCount Days',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.indigo,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildActivityMetricColumn(
                  'Total Steps',
                  totalSteps.toString(),
                  Icons.directions_walk,
                ),
                _buildActivityMetricColumn(
                  'Daily Average',
                  _summaryMetrics['steps_average'].toString(),
                  Icons.show_chart,
                ),
                _buildActivityMetricColumn(
                  'Active Minutes',
                  _summaryMetrics['total_activity_minutes'].toString(),
                  Icons.timer,
                ),
              ],
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                // Navigate to activity screen
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const ActivityScreen()),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.indigo),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'View Activity Details',
                    style: TextStyle(
                      color: Colors.indigo,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildActivityMetricColumn(String label, String value, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: Colors.green,
            size: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  Widget _buildChartsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateRangeSelector(),
          const SizedBox(height: 16),
          _buildBloodPressureChart(),
          const SizedBox(height: 16),
          _buildWeightChart(),
          const SizedBox(height: 16),
          _buildStepsChart(),
          const SizedBox(height: 40), // Space for floating action button
        ],
      ),
    );
  }
  
 Widget _buildBloodPressureChart() {
  if (_reportData['blood_pressure'].isEmpty) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text('No blood pressure data for selected period'),
        ),
      ),
    );
  }

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
          const Row(
            children: [
              Icon(
                Icons.favorite,
                color: Colors.red,
                size: 24,
              ),
              SizedBox(width: 8),
              Text(
                'Blood Pressure Trend',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 240,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 20,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.grey[300]!,
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
                        if (value.toInt() % 2 == 0 &&
                            value.toInt() >= 0 &&
                            value.toInt() < _reportData['blood_pressure'].length) {
                          final date = _reportData['blood_pressure'][value.toInt()]['date'] as DateTime;
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              DateFormat('MM/dd').format(date),
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
                        if (value % 20 == 0 && value >= 60 && value <= 180) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 10,
                            ),
                          );
                        }
                        return const Text('');
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
                    spots: List.generate(_reportData['blood_pressure'].length, (index) {
                      return FlSpot(
                        index.toDouble(),
                        _reportData['blood_pressure'][index]['systolic'].toDouble(),
                      );
                    }),
                    isCurved: true,
                    color: Colors.red,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 4,
                          color: Colors.red,
                          strokeWidth: 1,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                  ),
                  LineChartBarData(
                    spots: List.generate(_reportData['blood_pressure'].length, (index) {
                      return FlSpot(
                        index.toDouble(),
                        _reportData['blood_pressure'][index]['diastolic'].toDouble(),
                      );
                    }),
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 4,
                          color: Colors.blue,
                          strokeWidth: 1,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                  ),
                  LineChartBarData(
                    spots: List.generate(_reportData['blood_pressure'].length, (index) {
                      return FlSpot(
                        index.toDouble(),
                        140,
                      );
                    }),
                    isCurved: false,
                    color: const Color.fromRGBO(255, 0, 0, 0.5),
                    barWidth: 1,
                    isStrokeCapRound: false,
                    dotData: const FlDotData(show: false),
                    dashArray: [5, 5],
                  ),
                  LineChartBarData(
                    spots: List.generate(_reportData['blood_pressure'].length, (index) {
                      return FlSpot(
                        index.toDouble(),
                        120,
                      );
                    }),
                    isCurved: false,
                    color: const Color.fromRGBO(0, 128, 0, 0.5),
                    barWidth: 1,
                    isStrokeCapRound: false,
                    dotData: const FlDotData(show: false),
                    dashArray: [5, 5],
                  ),
                ],
                minY: 60,
                maxY: 180,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem('Systolic', Colors.red),
              const SizedBox(width: 20),
              _buildLegendItem('Diastolic', Colors.blue),
              const SizedBox(width: 20),
              _buildLegendItem('High Threshold', const Color.fromRGBO(255, 0, 0, 0.5)),
              const SizedBox(width: 20),
              _buildLegendItem('Normal', const Color.fromRGBO(0, 128, 0, 0.5)),
            ],
          ),
        ],
      ),
    ));
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
            fontSize: 10,
          ),
        ),
      ],
    );
  }
  
  Widget _buildWeightChart() {
    // Skip if no readings
    if (_reportData['weight'].isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text('No weight data for selected period'),
          ),
        ),
      );
    }
    
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
            const Row(
              children: [
                Icon(
                  Icons.monitor_weight,
                  color: Colors.indigo,
                  size: 24,
                ),
                SizedBox(width: 8),
                Text(
                  'Weight Trend',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 240,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 2,
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
                          if (value.toInt() % 2 == 0 &&
                              value.toInt() >= 0 &&
                              value.toInt() < _reportData['weight'].length) {
                            final date = _reportData['weight'][value.toInt()]['date'] as DateTime;
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                DateFormat('MM/dd').format(date),
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
                    // Weight line
                    LineChartBarData(
                      spots: List.generate(_reportData['weight'].length, (index) {
                        return FlSpot(
                          index.toDouble(),
                          _reportData['weight'][index]['weight'].toDouble(),
                        );
                      }),
                      isCurved: true,
                      color: Colors.indigo,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: Colors.indigo,
                            strokeWidth: 1,
                            strokeColor: Colors.white,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.indigo.withOpacity(0.1),
                      ),
                    ),
                  ],
                  minY: _calculateMinWeightY(),
                  maxY: _calculateMaxWeightY(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  double _calculateMinWeightY() {
    if (_reportData['weight'].isEmpty) return 50;
    
    double minWeight = double.maxFinite;
    for (var reading in _reportData['weight']) {
      if (reading['weight'] < minWeight) {
        minWeight = reading['weight'];
      }
    }
    
    return (minWeight - 5).clamp(0, double.maxFinite);
  }
  
  double _calculateMaxWeightY() {
    if (_reportData['weight'].isEmpty) return 100;
    
    double maxWeight = 0;
    for (var reading in _reportData['weight']) {
      if (reading['weight'] > maxWeight) {
        maxWeight = reading['weight'];
      }
    }
    
    return maxWeight + 5;
  }
  
  Widget _buildStepsChart() {
    // Skip if no readings
    if (_reportData['activity'].isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text('No activity data for selected period'),
          ),
        ),
      );
    }
    
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
            const Row(
              children: [
                Icon(
                  Icons.directions_walk,
                  color: Colors.green,
                  size: 24,
                ),
                SizedBox(width: 8),
                Text(
                  'Daily Steps',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 240,
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 2000,
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
                          if (value.toInt() >= 0 && value.toInt() < _reportData['activity'].length) {
                            final date = _reportData['activity'][value.toInt()]['date'] as DateTime;
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                DateFormat('MM/dd').format(date),
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
                  barGroups: List.generate(_reportData['activity'].length, (index) {
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: _reportData['activity'][index]['steps'].toDouble(),
                          color: Colors.green,
                          width: 16,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            topRight: Radius.circular(6),
                          ),
                        ),
                      ],
                    );
                  }),
                  minY: 0,
                  maxY: _calculateMaxStepsY(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('Steps', Colors.green),
                const SizedBox(width: 20),
                Text(
                  'Goal: 10,000 steps',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  double _calculateMaxStepsY() {
    if (_reportData['activity'].isEmpty) return 10000;
    
    int maxSteps = 0;
    for (var reading in _reportData['activity']) {
      if (reading['steps'] > maxSteps) {
        maxSteps = reading['steps'] as int;
      }
    }
    
    // Return max steps rounded up to nearest 2000, or 10000 if max is less
    return max(((maxSteps / 2000).ceil() * 2000).toDouble(), 10000);
  }
  
  Widget _buildDetailsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateRangeSelector(),
          const SizedBox(height: 16),
          _buildBloodPressureDetailsList(),
          const SizedBox(height: 16),
          _buildWeightDetailsList(),
          const SizedBox(height: 16),
          _buildActivityDetailsList(),
          const SizedBox(height: 40), // Space for floating action button
        ],
      ),
    );
  }
  
  Widget _buildBloodPressureDetailsList() {
    // Skip if no readings
    if (_reportData['blood_pressure'].isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text('No blood pressure readings for selected period'),
          ),
        ),
      );
    }
    
    // Sort by date, most recent first
    final sortedReadings = List<Map<String, dynamic>>.from(_reportData['blood_pressure'])
      ..sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    
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
            const Row(
              children: [
                Icon(
                  Icons.favorite,
                  color: Colors.red,
                  size: 24,
                ),
                SizedBox(width: 8),
                Text(
                  'Blood Pressure Readings',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sortedReadings.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final reading = sortedReadings[index];
                final date = reading['date'] as DateTime;
                final category = _getBPCategory(reading['systolic'], reading['diastolic']);
                
                // Determine color based on category
                Color categoryColor;
                switch (category) {
                  case 'Crisis':
                    categoryColor = Colors.red[700]!;
                    break;
                  case 'High':
                    categoryColor = Colors.red;
                    break;
                  case 'Elevated':
                    categoryColor = Colors.orange;
                    break;
                  case 'Normal':
                    categoryColor = Colors.green;
                    break;
                  case 'Low':
                    categoryColor = Colors.blue;
                    break;
                  default:
                    categoryColor = Colors.grey;
                }
                
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Text(
                        '${reading['systolic']}/${reading['diastolic']} mmHg',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: categoryColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          category,
                          style: TextStyle(
                            color: categoryColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    'Pulse: ${reading['pulse']} bpm • ${DateFormat('EEEE, MMM d, yyyy • h:mm a').format(date)}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () {
                      // Show options
                      _showReadingOptionsDialog('blood_pressure', reading);
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildWeightDetailsList() {
    // Skip if no readings
    if (_reportData['weight'].isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text('No weight readings for selected period'),
          ),
        ),
      );
    }
    
    // Sort by date, most recent first
    final sortedReadings = List<Map<String, dynamic>>.from(_reportData['weight'])
      ..sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    
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
            const Row(
              children: [
                Icon(
                  Icons.monitor_weight,
                  color: Colors.indigo,
                  size: 24,
                ),
                SizedBox(width: 8),
                Text(
                  'Weight Readings',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sortedReadings.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final reading = sortedReadings[index];
                final date = reading['date'] as DateTime;
                
                // Calculate change from previous reading
                String changeText = '';
                if (index < sortedReadings.length - 1) {
                  final prevReading = sortedReadings[index + 1];
                  final change = reading['weight'] - prevReading['weight'];
                  final isPositive = change > 0;
                  changeText = isPositive 
                      ? '+${change.toStringAsFixed(1)} kg' 
                      : '${change.toStringAsFixed(1)} kg';
                }
                
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Text(
                        '${reading['weight'].toStringAsFixed(1)} kg',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (changeText.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          changeText,
                          style: TextStyle(
                            color: changeText.startsWith('+') ? Colors.red : Colors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    'BMI: ${reading['bmi'].toStringAsFixed(1)} • ${DateFormat('EEEE, MMM d, yyyy • h:mm a').format(date)}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () {
                      // Show options
                      _showReadingOptionsDialog('weight', reading);
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildActivityDetailsList() {
    // Skip if no readings
    if (_reportData['activity'].isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text('No activity data for selected period'),
          ),
        ),
      );
    }
    
    // Sort by date, most recent first
    final sortedReadings = List<Map<String, dynamic>>.from(_reportData['activity'])
      ..sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    
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
            const Row(
              children: [
                Icon(
                  Icons.directions_run,
                  color: Colors.green,
                  size: 24,
                ),
                SizedBox(width: 8),
                Text(
                  'Activity Records',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sortedReadings.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final reading = sortedReadings[index];
                final date = reading['date'] as DateTime;
                
                // Calculate progress percentage towards 10,000 steps
                final progress = (reading['steps'] / 10000).clamp(0.0, 1.0);
                final isGoalReached = reading['steps'] >= 10000;
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat('EEEE, MMM d, yyyy').format(date),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_vert),
                          onPressed: () {
                            // Show options
                            _showReadingOptionsDialog('activity', reading);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildActivityDetailItem(
                          'Steps',
                          reading['steps'].toString(),
                          Icons.directions_walk,
                          Colors.green,
                        ),
                        _buildActivityDetailItem(
                          'Distance',
                          '${reading['distance']} km',
                          Icons.straighten,
                          Colors.blue,
                        ),
                        _buildActivityDetailItem(
                          'Calories',
                          '${reading['calories']} kcal',
                          Icons.local_fire_department,
                          Colors.orange,
                        ),
                        _buildActivityDetailItem(
                          'Active',
                          '${reading['active_minutes']} min',
                          Icons.timer,
                          Colors.purple,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Steps Goal: ${isGoalReached ? 'Reached' : 'In Progress'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isGoalReached ? Colors.green : Colors.grey[600],
                                fontWeight: isGoalReached ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            Text(
                              '${(progress * 100).toInt()}% (${reading['steps']}/10,000)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: FractionallySizedBox(
                            widthFactor: progress,
                            child: Container(
                              decoration: BoxDecoration(
                                color: isGoalReached ? Colors.green : Colors.amber,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildActivityDetailItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: color,
            size: 18,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
  
  void _showReadingOptionsDialog(String type, Map<String, dynamic> reading) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit Reading'),
                onTap: () {
                  Navigator.pop(context);
                  // Navigate to edit screen based on type
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Editing $type reading')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete Reading', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmationDialog(type, reading);
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_copy),
                title: const Text('Copy Data'),
                onTap: () {
                  Navigator.pop(context);
                  // Copy reading data (implementation depends on platform)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reading data copied to clipboard')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
  
  void _showDeleteConfirmationDialog(String type, Map<String, dynamic> reading) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Reading'),
        content: Text('Are you sure you want to delete this $type reading? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // Delete reading implementation
              _deleteReading(type, reading);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _deleteReading(String type, Map<String, dynamic> reading) async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }
      
      String collectionName;
      switch (type) {
        case 'blood_pressure':
          collectionName = 'blood_pressure';
          break;
        case 'weight':
          collectionName = 'weight';
          break;
        case 'activity':
          collectionName = 'activity';
          break;
        default:
          throw Exception('Invalid reading type: $type');
      }
      
      // Delete document
      await _firestore
          .collection(collectionName)
          .doc(reading['id'])
          .delete();
      
      // Refresh data
      await _loadReportData();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$type reading deleted successfully')),
      );
    } catch (e) {
      print('Error deleting reading: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting reading: $e')),
      );
    }
  }
  
  Widget _buildBloodPressureSummaryCard() {
    final int readingsCount = _reportData['blood_pressure'].length;
    
    // Skip if no readings
    if (readingsCount == 0) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text('No blood pressure data for selected period'),
          ),
        ),
      );
    }
    
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.favorite,
                      color: Colors.red,
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Blood Pressure Summary',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.indigo[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$readingsCount Readings',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.indigo,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildBPMetricBlock(
                  'Average',
                  '${_summaryMetrics['bp_average']['systolic']}/${_summaryMetrics['bp_average']['diastolic']}',
                  _getBPCategory(_summaryMetrics['bp_average']['systolic'], _summaryMetrics['bp_average']['diastolic']),
                ),
                _buildBPMetricBlock(
                  'Highest',
                  '${_summaryMetrics['bp_highest']['systolic']}/${_summaryMetrics['bp_highest']['diastolic']}',
                  _getBPCategory(_summaryMetrics['bp_highest']['systolic'], _summaryMetrics['bp_highest']['diastolic']),
                  date: _summaryMetrics['bp_highest']['date'],
                ),
                _buildBPMetricBlock(
                  'Lowest',
                  '${_summaryMetrics['bp_lowest']['systolic']}/${_summaryMetrics['bp_lowest']['diastolic']}',
                  _getBPCategory(_summaryMetrics['bp_lowest']['systolic'], _summaryMetrics['bp_lowest']['diastolic']),
                  date: _summaryMetrics['bp_lowest']['date'],
                ),
              ],
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                // Navigate to detailed blood pressure screen
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Navigating to Blood Pressure details')),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.indigo),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'View Blood Pressure Details',
                    style: TextStyle(
                      color: Colors.indigo,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
 
}
