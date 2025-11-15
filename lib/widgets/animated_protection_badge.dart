import 'package:flutter/material.dart';

/// Animated protection badge with subtle glow effect
class AnimatedProtectionBadge extends StatefulWidget {
  const AnimatedProtectionBadge({super.key});

  @override
  State<AnimatedProtectionBadge> createState() =>
      _AnimatedProtectionBadgeState();
}

class _AnimatedProtectionBadgeState extends State<AnimatedProtectionBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
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
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.blue.withOpacity(_glowAnimation.value),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(_glowAnimation.value * 0.3),
                blurRadius: 8,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield, size: 16, color: Colors.blue[300]),
              const SizedBox(width: 6),
              Text(
                'Protected by Hello AI',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blue[300],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

