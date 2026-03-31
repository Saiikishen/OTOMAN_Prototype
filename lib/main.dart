import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const OtomanApp());
}

class OtomanApp extends StatelessWidget {
  const OtomanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OTOMAN - Intelligent Living',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}
