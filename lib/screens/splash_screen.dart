import 'dart:async';
import 'package:flutter/material.dart';
import 'package:billy_the_viewer/app/theme.dart';
import 'package:billy_the_viewer/screens/home_screen.dart';

/// Minimalist brutalist splash screen for Billy The Viewer.
///
/// Displays the Option 8 Infinity Viewfinder monogram on pure black,
/// with technical Swiss sub-branding, then cleanly transitions to [HomeScreen].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _controller.forward();

    // Smooth, calibrated hold before transitioning into the viewfinder
    _navigationTimer = Timer(const Duration(milliseconds: 1600), _proceedToHome);
  }

  void _proceedToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BillyTheme.black,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 3),

                  // --- Central Glyph ---
                  Image.asset(
                    'assets/branding/logo_transparent_white.png',
                    width: 104,
                    height: 104,
                    fit: BoxFit.contain,
                  ),

                  const SizedBox(height: BillyTheme.space24),

                  // --- Wordmark ---
                  const Text(
                    'BILLY',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 34.0,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 10.0,
                      color: BillyTheme.white,
                    ),
                  ),

                  const SizedBox(height: BillyTheme.space8),

                  // --- Editorial Technical Moniker ---
                  const Text(
                    'COMPUTER VISION // AD DISCOVERY',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 9.0,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3.0,
                      color: BillyTheme.textSecondary,
                    ),
                  ),

                  const Spacer(flex: 3),

                  // --- Footer System Status ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 5.0,
                        height: 5.0,
                        decoration: const BoxDecoration(
                          color: BillyTheme.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: BillyTheme.space8),
                      const Text(
                        'ON-DEVICE ENGINE INITIALIZED',
                        style: TextStyle(
                          fontSize: 9.0,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2.0,
                          color: BillyTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: BillyTheme.space32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
