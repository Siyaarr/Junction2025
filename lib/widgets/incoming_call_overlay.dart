import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/call_info.dart';

class IncomingCallOverlay extends StatelessWidget {
  final CallInfo callInfo;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;
  final bool isScam;

  const IncomingCallOverlay({
    super.key,
    required this.callInfo,
    required this.onAnswer,
    required this.onDecline,
    this.isScam = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: isScam
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFF4444), Color(0xFFCC0000)],
                  )
                : const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF1E1E1E), Color(0xFF000000)],
                  ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // Scam warning banner
              if (isScam)
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.warning, color: Colors.white, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'POTENTIAL SCAM DETECTED!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

              // Caller info
              CircleAvatar(
                radius: 60,
                backgroundColor: isScam
                    ? Colors.red.shade300
                    : Colors.blue.shade300,
                child: Text(
                  callInfo.contactName?.substring(0, 1).toUpperCase() ??
                      callInfo.phoneNumber.substring(0, 1),
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                callInfo.contactName ?? 'Unknown',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                callInfo.phoneNumber,
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),

              const Spacer(flex: 3),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline button
                  _CallActionButton(
                    icon: Icons.call_end,
                    label: 'Decline',
                    color: Colors.red,
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      onDecline();
                    },
                  ),

                  // Answer button
                  _CallActionButton(
                    icon: Icons.call,
                    label: 'Answer',
                    color: Colors.green,
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      onAnswer();
                    },
                  ),
                ],
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
