import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'services/scheduler_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SchedulerService.init();
  runApp(const OtomanApp());
}

class OtomanApp extends StatelessWidget {
  const OtomanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Otoman',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}
