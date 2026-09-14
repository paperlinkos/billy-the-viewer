import 'package:flutter/material.dart';
import 'package:billy_the_viewer/app/theme.dart';

/// An understated, elegant scanning indicator.
/// Follows Billy's minimal black + white + lines design system.
/// Features a subtle pulsating sweep line and "LOOKING..." typography.
class MinimalLookingIndicator extends StatefulWidget {
  const MinimalLookingIndicator({super.key});

  @override
  State<MinimalLookingIndicator> createState() => _MinimalLookingIndicatorState();
}

class _MinimalLookingIndicatorState extends State<MinimalLookingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'LOOKING...',
              style: TextStyle(
                fontSize: 11.0,
                fontWeight: FontWeight.w800,
                letterSpacing: 3.0,
                color: BillyTheme.black,
              ),
            ),
            AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                return Opacity(
                  opacity: 0.3 + (_animation.value * 0.7),
                  child: Container(
                    width: 6.0,
                    height: 6.0,
                    decoration: const BoxDecoration(
                      color: BillyTheme.black,
                      shape: BoxShape.rectangle,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: BillyTheme.space8),
        // Subtle progress track line
        SizedBox(
          height: BillyTheme.borderWidthMedium,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = constraints.maxWidth;
              const indicatorWidth = 40.0;
              final maxTravel = trackWidth - indicatorWidth;

              return Stack(
                children: [
                  // Base background line
                  Container(
                    width: double.infinity,
                    height: BillyTheme.borderWidthMedium,
                    color: BillyTheme.grayLight,
                  ),
                  // Animated sweep segment
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      final leftPosition = _animation.value * maxTravel;
                      return Positioned(
                        left: leftPosition.clamp(0.0, maxTravel),
                        top: 0,
                        bottom: 0,
                        width: indicatorWidth,
                        child: Container(
                          color: BillyTheme.black,
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
