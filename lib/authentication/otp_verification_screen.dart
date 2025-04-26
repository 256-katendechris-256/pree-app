import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import '../screens/dashboard.dart';
import 'user_profile_setup.dart';

class OTPVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;
  final bool isNewUser;

  const OTPVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    required this.isNewUser,
  });

  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  final FirebaseAuth _auth = FirebaseAuth.instance;
  int _resendSeconds = 30;
  Timer? _timer;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    _focusNodes[0].requestFocus();
  }

  void _startResendTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendSeconds > 0) {
        setState(() => _resendSeconds--);
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _verifyOTP() async {
    if (_isVerifying) return;
    setState(() => _isVerifying = true);

    try {
      final otp = _controllers.fold('', (prev, c) => prev + c.text);
      if (otp.length != 6) throw 'Please enter complete OTP';

      final credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: otp,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      
      if (userCredential.user == null) throw 'Authentication failed';

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => userCredential.additionalUserInfo?.isNewUser ?? false
              ? const UserProfileSetupScreen()
              : const DashboardScreen(),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Text(
                'Verify your phone number',
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Enter the OTP sent to ${widget.phoneNumber}',
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (index) => SizedBox(
                  width: 50,
                  child: TextField(
                    controller: _controllers[index],
                    focusNode: _focusNodes[index],
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    maxLength: 1,
                    onChanged: (value) {
                      if (value.length == 1 && index < 5) {
                        _focusNodes[index + 1].requestFocus();
                      }
                      if (value.isEmpty && index > 0) {
                        _focusNodes[index - 1].requestFocus();
                      }
                    },
                    decoration: InputDecoration(
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                )),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _verifyOTP,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isVerifying
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Verify OTP',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: _resendSeconds > 0
                    ? Text(
                        'Resend OTP in $_resendSeconds seconds',
                        style: const TextStyle(color: Colors.grey),
                      )
                    : GestureDetector(
                        onTap: () {
                          setState(() => _resendSeconds = 30);
                          _startResendTimer();
                        },
                        child: Text(
                          'Resend OTP',
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}