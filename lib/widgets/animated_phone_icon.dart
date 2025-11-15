import 'package:flutter/material.dart';

/// Animated phone icon with pulsing waves
class AnimatedPhoneIcon extends StatefulWidget {
  final double size;
  final Color color;
  final bool isActive;

  const AnimatedPhoneIcon({
    super.key,
    this.size = 64,
    this.color = Colors.blue,
    this.isActive = true,
  });

  @override
  State<AnimatedPhoneIcon> createState() => _AnimatedPhoneIconState();
}

class _AnimatedPhoneIconState extends State<AnimatedPhoneIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _waveAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return Icon(
        Icons.phone_in_talk,
        size: widget.size,
        color: widget.color,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Ripple waves
            ...List.generate(3, (index) {
              final delay = index * 0.3;
              final animationValue = (_waveAnimation.value + delay) % 1.0;
              final opacity = (1.0 - animationValue) * 0.3;
              final scale = 1.0 + (animationValue * 0.8);

              return Transform.scale(
                scale: scale,
                child: Container(
                  width: widget.size * 1.5,
                  height: widget.size * 1.5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.color.withOpacity(opacity),
                      width: 2,
                    ),
                  ),
                ),
              );
            }),
            // Phone icon with pulse
            Transform.scale(
              scale: _pulseAnimation.value,
              child: Icon(
                Icons.phone_in_talk,
                size: widget.size,
                color: widget.color,
              ),
            ),
          ],
        );
      },
    );
  }
}

