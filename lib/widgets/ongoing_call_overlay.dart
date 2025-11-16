import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/call_info.dart';

// Scam flow stage: none → aiSpeaking (10s) → choice (10s auto-end countdown)
enum ScamFlowStage { none, aiSpeaking, choice }

class OngoingCallOverlay extends StatefulWidget {
  // Public hook to simulate scam alert from elsewhere (e.g., dev tools).
  static void Function()? simulateScam;

  final CallInfo callInfo;
  final VoidCallback onHangup;
  final VoidCallback? onMute;
  final VoidCallback? onSpeaker;
  final VoidCallback? onHold;
  final VoidCallback? onResume;
  final VoidCallback? onCallSafetyContact;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isOnHold;

  const OngoingCallOverlay({
    super.key,
    required this.callInfo,
    required this.onHangup,
    this.onMute,
    this.onSpeaker,
    this.onHold,
    this.onResume,
    this.onCallSafetyContact,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.isOnHold = false,
  });

  @override
  State<OngoingCallOverlay> createState() => _OngoingCallOverlayState();
}

class _OngoingCallOverlayState extends State<OngoingCallOverlay>
    with TickerProviderStateMixin {
  DateTime? _callStartTime;
  Timer? _durationTimer;
  Duration _callDuration = Duration.zero;
  late bool _isMuted;
  late bool _isSpeakerOn;
  late bool _isOnHold;
  late bool _scamPauseActive;
  late final AnimationController _panelController;
  late final Animation<Offset> _panelSlide;
  late final AnimationController _aiSpeakingController;
  AnimationController? _endCountdownController; // created when entering choice
  ScamFlowStage _scamStage = ScamFlowStage.none;
  bool _securityContactAdded =
      false; // Track if security contact has been added

  @override
  void initState() {
    super.initState();
    _callStartTime = widget.callInfo.timestamp;
    _isMuted = widget.isMuted;
    _isSpeakerOn = widget.isSpeakerOn;
    // Auto-pause when scam is detected
    _scamPauseActive = widget.callInfo.isScam == true;
    _isOnHold = widget.isOnHold || _scamPauseActive;

    _panelController = AnimationController(
      duration: const Duration(milliseconds: 380),
      vsync: this,
    );
    _panelSlide = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _panelController, curve: Curves.easeOutCubic),
        );

    _aiSpeakingController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();

    // If already starting with scam active+hold, show panel in place.
    if (_scamPauseActive && _isOnHold) {
      _panelController.value = 1.0;
      _enterAiSpeaking();
    }

    // Expose a public trigger for dev simulation
    OngoingCallOverlay.simulateScam = _simulateScamAlert;
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

  @override
  void didUpdateWidget(covariant OngoingCallOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If scam flag just turned on during the call, auto-activate pause UI and animate panel.
    final wasScam = oldWidget.callInfo.isScam == true;
    final isNowScam = widget.callInfo.isScam == true;
    if (!wasScam && isNowScam) {
      _simulateScamAlert();
    } else if (wasScam && !isNowScam) {
      _simulateNormal();
    }
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
    _panelController.dispose();
    _aiSpeakingController.dispose();
    _endCountdownController?.dispose();
    // Remove public hook on dispose
    if (identical(OngoingCallOverlay.simulateScam, _simulateScamAlert)) {
      OngoingCallOverlay.simulateScam = null;
    }
    super.dispose();
  }

  void _simulateScamAlert() {
    if (!mounted) return;
    setState(() {
      _scamPauseActive = true;
      _isOnHold = true;
    });
    _panelController.forward();
    _enterAiSpeaking();
  }

  void _simulateNormal() {
    if (!mounted) return;
    setState(() {
      _scamPauseActive = false;
      _isOnHold = false;
      _scamStage = ScamFlowStage.none;
    });
    _panelController.reverse();
    _endCountdownController?.stop();
    _endCountdownController?.dispose();
    _endCountdownController = null;
  }

  void _enterAiSpeaking() {
    // Begin AI speaking stage for ~10s, then transition to choice stage
    setState(() {
      _scamStage = ScamFlowStage.aiSpeaking;
    });
    Future.delayed(const Duration(seconds: 10), () {
      if (!mounted ||
          !_scamPauseActive ||
          _scamStage != ScamFlowStage.aiSpeaking)
        return;
      _enterChoiceStage();
    });
  }

  void _enterChoiceStage() {
    setState(() {
      _scamStage = ScamFlowStage.choice;
    });
    // 10s auto-end countdown with smooth left-to-right animation on End button
    _endCountdownController?.dispose();
    _endCountdownController =
        AnimationController(vsync: this, duration: const Duration(seconds: 10))
          ..addListener(() {
            if (mounted) setState(() {});
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              // Only auto-hangup if security contact hasn't been added
              if (!_securityContactAdded) {
                widget.onHangup();
              }
            }
          });
    _endCountdownController!.forward();
  }

  void _onSecurityContactAdded() {
    setState(() {
      _securityContactAdded = true;
    });
    // Stop and dispose the countdown controller
    _endCountdownController?.stop();
    _endCountdownController?.dispose();
    _endCountdownController = null;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Stack(
          children: [
            // Main gradient background
            AnimatedContainer(
              width: double.infinity,
              height: double.infinity,
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeInOutCubic,
              decoration: BoxDecoration(
                gradient: (widget.callInfo.isScam == true || _scamPauseActive)
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
            ),

            // Content with top padding
            Padding(
              padding: const EdgeInsets.only(top: 120.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  // Warning banner
                  if (widget.callInfo.isScam == true || _scamPauseActive)
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

                  // Caller info (phone number as primary display)
                  Text(
                    widget.callInfo.phoneNumber.isNotEmpty
                        ? widget.callInfo.phoneNumber
                        : (widget.callInfo.contactName ?? 'Loading...'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Participant count indicator (shown when security contact is added)
                  if (_securityContactAdded)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green[700]?.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.green[500]!,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.people,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '3 on call',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.95),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 8),

                  // Call duration or Paused badge
                  _isOnHold
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange[800],
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            'Paused',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : Text(
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
                      horizontal: 24,
                      vertical: 28,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Mute button
                            _CallControlButton(
                              icon: _isMuted ? Icons.mic_off : Icons.mic,
                              label: 'Mute',
                              color: _isMuted ? Colors.red : Colors.grey[700]!,
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                setState(() => _isMuted = !_isMuted);
                                widget.onMute?.call();
                              },
                            ),

                            // Speaker button
                            _CallControlButton(
                              icon: _isSpeakerOn
                                  ? Icons.volume_up
                                  : Icons.volume_down,
                              label: 'Speaker',
                              color: _isSpeakerOn
                                  ? Colors.green
                                  : Colors.grey[700]!,
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                setState(() => _isSpeakerOn = !_isSpeakerOn);
                                widget.onSpeaker?.call();
                              },
                            ),

                            // Hold/Resume button
                            _CallControlButton(
                              icon: _isOnHold ? Icons.play_arrow : Icons.pause,
                              label: _isOnHold ? 'Resume' : 'Hold',
                              color: _isOnHold
                                  ? Colors.blueAccent
                                  : Colors.grey[700]!,
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                setState(() {
                                  _isOnHold = !_isOnHold;
                                  if (_isOnHold) {
                                    _scamPauseActive =
                                        _scamPauseActive ||
                                        widget.callInfo.isScam == true;
                                    widget.onHold?.call();
                                  } else {
                                    widget.onResume?.call();
                                  }
                                });
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Hangup button (separate row below)
                        Align(
                          alignment: Alignment.center,
                          child: _CallControlButton(
                            icon: Icons.call_end,
                            label: 'Hang Up',
                            color: Colors.red,
                            onTap: () {
                              HapticFeedback.heavyImpact();
                              widget.onHangup();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Scam side panel / pause assistant
            IgnorePointer(
              ignoring: !(_scamPauseActive && _isOnHold),
              child: SlideTransition(
                position: _panelSlide,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 320,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E0F0F).withOpacity(0.96),
                      border: const Border(
                        left: BorderSide(color: Color(0xFFFF6B6B), width: 2),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 16,
                          offset: Offset(-4, 0),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.shield, color: Colors.white),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Protection Active',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange[800],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Paused',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Stage content
                        if (_scamStage == ScamFlowStage.aiSpeaking) ...[
                          const Text(
                            'Our AI assistant detected a likely scam and is speaking now:',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          const SizedBox(height: 12),
                          _SpeakingBars(controller: _aiSpeakingController),
                          const SizedBox(height: 12),
                          Text(
                            '“This call appears suspicious due to requests for sensitive information and urgent payment. '
                            'Please do not share personal or banking details.”',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 13,
                              height: 1.3,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Preparing options...',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 12,
                            ),
                          ),
                        ] else if (_scamStage == ScamFlowStage.choice) ...[
                          if (!_securityContactAdded) ...[
                            const Text(
                              'Do you want to add your security contact to this call?',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  _onSecurityContactAdded();
                                  widget.onCallSafetyContact?.call();
                                },
                                icon: const Icon(Icons.person_add),
                                label: const Text('Add Security Contact'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue[700],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // End call with left→right progress fill (DISABLED after clicking Add)
                            SizedBox(
                              width: double.infinity,
                              child: _EndButtonWithProgress(
                                onPressed: widget.onHangup,
                                controller: _endCountdownController,
                              ),
                            ),
                          ] else ...[
                            // DIFFERENT LAYOUT: Show that security contact has been added
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.green[900]?.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.green[600]!,
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.green[700],
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Security Contact Added',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              'Your trusted person is now on the call',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  // Participants indicator
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.people,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '3 people on call',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(
                                              0.9,
                                            ),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Manual end call button (NO COUNTDOWN ANIMATION)
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: widget.onHangup,
                                icon: const Icon(
                                  Icons.call_end,
                                  color: Colors.white,
                                ),
                                label: const Text('End Call'),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.red[700],
                                  foregroundColor: Colors.white,
                                  side: BorderSide(color: Colors.red[900]!),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                        ] else ...[
                          const Text(
                            'Scam suspected. We paused the call.',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          const Spacer(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Dev-only toggles overlay (top-left) to simulate mode changes
            // Disabled for now
            // if (const bool.fromEnvironment('dart.vm.product') == false)
            //   Align(
            //     alignment: Alignment.topLeft,
            //     child: Padding(
            //       padding: const EdgeInsets.all(8.0),
            //       child: Row(
            //         mainAxisSize: MainAxisSize.min,
            //         children: [
            //           OutlinedButton(
            //             onPressed: _simulateScamAlert,
            //             style: OutlinedButton.styleFrom(
            //               foregroundColor: Colors.red[300],
            //               side: BorderSide(color: Colors.red[700]!),
            //               padding: const EdgeInsets.symmetric(
            //                 horizontal: 10,
            //                 vertical: 6,
            //               ),
            //             ),
            //             child: const Text('Simulate Scam'),
            //           ),
            //           const SizedBox(width: 8),
            //           OutlinedButton(
            //             onPressed: _simulateNormal,
            //             style: OutlinedButton.styleFrom(
            //               foregroundColor: Colors.green[300],
            //               side: BorderSide(color: Colors.green[700]!),
            //               padding: const EdgeInsets.symmetric(
            //                 horizontal: 10,
            //                 vertical: 6,
            //               ),
            //             ),
            //             child: const Text('Simulate Normal'),
            //           ),
            //         ],
            //       ),
            //     ),
            //   ),
          ],
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

// (Removed unused _StepTile)

/// Animated "speaking" bars to indicate AI speech.
class _SpeakingBars extends StatelessWidget {
  final AnimationController controller;
  const _SpeakingBars({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          // Generate 10 bars with varying heights
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(10, (i) {
              final t = (controller.value + i * 0.1) % 1.0;
              final h = 10 + (t * 26); // 10..36
              return Container(
                width: 6,
                height: h,
                decoration: BoxDecoration(
                  color: Colors.lightBlueAccent.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

/// End button with left→right progress fill, auto-pressing at completion.
class _EndButtonWithProgress extends StatelessWidget {
  final VoidCallback onPressed;
  final AnimationController? controller;

  const _EndButtonWithProgress({
    required this.onPressed,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(10);
    if (controller == null) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.call_end, color: Colors.white),
        label: const Text('End Call'),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.red[700],
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.red[900]!),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
        ),
      );
    }
    return AnimatedBuilder(
      animation: controller!,
      builder: (context, _) {
        final progress = controller!.value.clamp(0.0, 1.0);
        return Stack(
          children: [
            // Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.call_end, color: Colors.white),
                label: const Text('End Call'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.red[900]!),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: borderRadius),
                ),
              ),
            ),
            // Progress overlay clipped to button radius
            Positioned.fill(
              child: ClipRRect(
                borderRadius: borderRadius,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(color: Colors.white.withOpacity(0.12)),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
