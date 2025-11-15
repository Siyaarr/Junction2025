import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/call_info.dart';

class OngoingCallOverlay extends StatefulWidget {
  final CallInfo callInfo;
  final VoidCallback onHangup;
  final VoidCallback? onMute;
  final VoidCallback? onSpeaker;
  final bool isMuted;
  final bool isSpeakerOn;

  const OngoingCallOverlay({
    super.key,
    required this.callInfo,
    required this.onHangup,
    this.onMute,
    this.onSpeaker,
    this.isMuted = false,
    this.isSpeakerOn = false,
  });

  @override
  State<OngoingCallOverlay> createState() => _OngoingCallOverlayState();
}

class _OngoingCallOverlayState extends State<OngoingCallOverlay> {
  DateTime? _callStartTime;
  Timer? _durationTimer;
  Duration _callDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _callStartTime = widget.callInfo.timestamp;
    _startDurationTimer();
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_callStartTime != null && mounted) {
        setState(() {
          _callDuration = DateTime.now().difference(_callStartTime!);
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: widget.callInfo.isScam == true
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFF4444), Color(0xFFCC0000)],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0B1020), Color(0xFF0E1A2F)],
                  ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Scam warning banner
              if (widget.callInfo.isScam == true)
                Container(
                  margin: const EdgeInsets.only(bottom: 40),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red[900],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning, color: Colors.white, size: 24),
                      SizedBox(width: 12),
                      Text(
                        'SCAM DETECTED',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

              // Caller avatar/icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.person,
                  size: 60,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),

              const SizedBox(height: 24),

              // Caller name
              Text(
                widget.callInfo.contactName ?? 'Unknown',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              // Phone number
              Text(
                widget.callInfo.phoneNumber,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 24),

              // Call duration
              Text(
                _formatDuration(_callDuration),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),

              const Spacer(),

              // Call controls
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 40,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Mute button
                    if (widget.onMute != null)
                      _CallControlButton(
                        icon: widget.isMuted ? Icons.mic_off : Icons.mic,
                        label: 'Mute',
                        color: widget.isMuted ? Colors.red : Colors.grey[700]!,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          widget.onMute?.call();
                        },
                      ),

                    // Speaker button
                    if (widget.onSpeaker != null)
                      _CallControlButton(
                        icon: widget.isSpeakerOn
                            ? Icons.volume_up
                            : Icons.volume_down,
                        label: 'Speaker',
                        color: widget.isSpeakerOn
                            ? Colors.green
                            : Colors.grey[700]!,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          widget.onSpeaker?.call();
                        },
                      ),

                    // Hangup button
                    _CallControlButton(
                      icon: Icons.call_end,
                      label: 'Hang Up',
                      color: Colors.red,
                      onTap: () {
                        HapticFeedback.heavyImpact();
                        widget.onHangup();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallControlButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_CallControlButton> createState() => _CallControlButtonState();
}

class _CallControlButtonState extends State<_CallControlButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withOpacity(0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(widget.icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              widget.label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
