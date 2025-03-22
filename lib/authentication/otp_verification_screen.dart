import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'user_profile_setup.dart';

class OTPVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final bool isNewUser;

  const OTPVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.isNewUser,
  });

  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  // Create controllers for each OTP field
  final TextEditingController _field1 = TextEditingController();
  final TextEditingController _field2 = TextEditingController();
  final TextEditingController _field3 = TextEditingController();
  final TextEditingController _field4 = TextEditingController();

  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());

  int _resendSeconds = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  void _startResendTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendSeconds > 0) {
        setState(() {
          _resendSeconds--;
        });
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _field1.dispose();
    _field2.dispose();
    _field3.dispose();
    _field4.dispose();
    for (var node in _focusNodes) {
      node.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }

  void _verifyOTP() {
    // Combine the OTP fields
    String enteredOTP = _field1.text + _field2.text + _field3.text + _field4.text;

    // Check if OTP is valid (in a real app, you'd verify with backend)
    if (enteredOTP.length == 4) {
      // For demo, we're assuming "1234" is the valid OTP
      if (enteredOTP == "1234") {
        // Navigate to appropriate next screen
        if (widget.isNewUser) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => const UserProfileSetupScreen(),
            ),
                (route) => false,
          );
        } else {
          // Navigate to dashboard for existing users
          Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
        }
      } else {
        // Show error for invalid OTP
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid OTP. Please try again.')),
        );
      }
    } else {
      // Show error for incomplete OTP
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter all digits of the OTP.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Verify Phone',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Verification Code',
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'We have sent a verification code to ${widget.phoneNumber}',
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildOTPField(0, _field1),
                  _buildOTPField(1, _field2),
                  _buildOTPField(2, _field3),
                  _buildOTPField(3, _field4),
                ],
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _verifyOTP,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Verify',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Didn\'t receive the code? ',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 14,
                    ),
                  ),
                  TextButton(
                    onPressed: _resendSeconds == 0
                        ? () {
                      // Reset the timer and request new OTP
                      setState(() {
                        _resendSeconds = 30;
                      });
                      _startResendTimer();

                      // Show confirmation
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('New OTP sent!')),
                      );
                    }
                        : null,
                    child: Text(
                      _resendSeconds > 0
                          ? 'Resend in $_resendSeconds s'
                          : 'Resend',
                      style: TextStyle(
                        color: _resendSeconds > 0
                            ? Colors.grey
                            : Theme.of(context).primaryColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOTPField(int index, TextEditingController controller) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: controller,
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(fontSize: 24),
        decoration: const InputDecoration(
          counterText: '',
          border: InputBorder.none,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        onChanged: (value) {
          if (value.isNotEmpty) {
            // Move to next field
            if (index < 3) {
              _focusNodes[index + 1].requestFocus();
            } else {
              // On last field, hide keyboard
              FocusManager.instance.primaryFocus?.unfocus();
            }
          } else if (value.isEmpty && index > 0) {
            // Move to previous field on backspace
            _focusNodes[index - 1].requestFocus();
          }
        },
      ),
    );
  }
}