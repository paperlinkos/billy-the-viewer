import 'package:flutter/material.dart';
import 'package:billy_the_viewer/app/theme.dart';
import 'package:billy_the_viewer/screens/home_screen.dart';

/// BillyApp is the root widget of the application.
class BillyApp extends StatelessWidget {
  const BillyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Billy the Viewer',
      debugShowCheckedModeBanner: false,
      theme: BillyTheme.lightTheme,
      home: const HomeScreen(),
    );
  }
}
