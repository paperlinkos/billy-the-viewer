import 'package:flutter/material.dart';
import 'package:billy_the_viewer/app/theme.dart';
import 'package:billy_the_viewer/screens/splash_screen.dart';

/// BillyApp is the root widget of the application.
class BillyApp extends StatelessWidget {
  final Widget? home;

  const BillyApp({super.key, this.home});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Billy the Viewer',
      debugShowCheckedModeBanner: false,
      theme: BillyTheme.lightTheme,
      home: home ?? const SplashScreen(),
    );
  }
}
