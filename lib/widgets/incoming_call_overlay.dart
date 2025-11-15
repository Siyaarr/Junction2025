import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/call_info.dart';
import 'animated_protection_badge.dart';

class IncomingCallOverlay extends StatefulWidget {
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
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay>
    with TickerProviderStateMixin {
  late AnimationController _entryController;
  late AnimationController _rippleController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _avatarScaleAnimation;
  late Animation<double> _rippleAnimation;

  @override
  void initState() {
    super.initState();

    // Controller for entry animations (runs once)
    _entryController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // Controller for continuous ripple effect
    _rippleController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic),
        );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOut));

    _avatarScaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.elasticOut),
    );

    // Ripple animation for avatar (continuous)
    _rippleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_rippleController);

    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([_entryController, _rippleController]),
          builder: (context, child) {
            return Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: widget.isScam
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFF4444), Color(0xFFCC0000)],
                      )
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0B1020), Color(0xFF0E1A2F), Color(0xFF0B2345)],
                      ),
              ),
              child: Stack(
                children: [
                  // Subtle decorative radial glows (only for non-scam state)
                  if (!widget.isScam) ...[
                    Positioned(
                      top: -60,
                      left: -40,
                      child: Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.blueAccent.withOpacity(0.25),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 1.0],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -80,
                      right: -50,
                      child: Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.tealAccent.withOpacity(0.20),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 1.0],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 180,
                      right: -70,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.indigoAccent.withOpacity(0.18),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ],

                  SlideTransition(
                    position: _slideAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Spacer(flex: 2),

                          // Scam warning banner with animation
                          if (widget.isScam)
                            ScaleTransition(
                              scale: _fadeAnimation,
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red.withOpacity(0.5),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(
                                      Icons.warning,
                                      color: Colors.white,
                                      size: 24,
                                    ),
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
                            ),

                          // Animated caller avatar with ripple effect
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              // Ripple circles
                              if (!widget.isScam)
                                ...List.generate(2, (index) {
                                  final delay = index * 0.5;
                                  final animationValue =
                                      ((_rippleAnimation.value * 2 + delay) % 1.0);
                                  final opacity = (1.0 - animationValue) * 0.2;
                                  final scale = 1.0 + (animationValue * 0.5);

                                  return Transform.scale(
                                    scale: scale,
                                    child: Container(
                                      width: 120,
                                      height: 120,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.blue.withOpacity(opacity),
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              // Avatar with scale animation
                              ScaleTransition(
                                scale: _avatarScaleAnimation,
                                child: CircleAvatar(
                                  radius: 60,
                                  backgroundColor: widget.isScam
                                      ? Colors.red.shade300
                                      : Colors.blue.shade300,
                                  child: const Icon(
                                    Icons.person,
                                    size: 56,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Caller info with fade animation (phone number as primary display)
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: Text(
                              widget.callInfo.phoneNumber.isNotEmpty
                                  ? widget.callInfo.phoneNumber
                                  : (widget.callInfo.contactName ?? 'Loading...'),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          // Animated protection indicator (only for non-scam calls)
                          if (!widget.isScam) ...[
                            const SizedBox(height: 16),
                            FadeTransition(
                              opacity: _fadeAnimation,
                              child: const AnimatedProtectionBadge(),
                            ),
                          ],

                          const Spacer(flex: 3),

                          // Action buttons with slide animation
                          SlideTransition(
                            position:
                                Tween<Offset>(
                                  begin: const Offset(0, 0.5),
                                  end: Offset.zero,
                                ).animate(
                                  CurvedAnimation(
                                    parent: _entryController,
                                    curve: const Interval(
                                      0.3,
                                      1.0,
                                      curve: Curves.easeOut,
                                    ),
                                  ),
                                ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // Decline button
                                _CallActionButton(
                                  icon: Icons.call_end,
                                  label: 'Decline',
                                  color: Colors.red,
                                  onTap: () {
                                    HapticFeedback.mediumImpact();
                                    widget.onDecline();
                                  },
                                ),

                                // Answer button
                                _CallActionButton(
                                  icon: Icons.call,
                                  label: 'Answer',
                                  color: Colors.green,
                                  onTap: () {
                                    HapticFeedback.mediumImpact();
                                    widget.onAnswer();
                                  },
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CallActionButton extends StatefulWidget {
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
  State<_CallActionButton> createState() => _CallActionButtonState();
}

class _CallActionButtonState extends State<_CallActionButton>
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
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withOpacity(0.4),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(widget.icon, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 8),
            Text(
              widget.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
