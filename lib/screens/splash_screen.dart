import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import 'building_selection_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToHome();
  }

  Future<void> _navigateToHome() async {
    await Future.delayed(const Duration(milliseconds: 3500));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const BuildingSelectionScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: 1.seconds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.backgroundNavy, AppColors.surfaceNavy],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Shimmering Hexagon Logo Background
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.accentGold.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                      )
                      .animate(onPlay: (controller) => controller.repeat())
                      .scale(
                        begin: const Offset(1, 1),
                        end: const Offset(1.2, 1.2),
                        duration: 2.seconds,
                        curve: Curves.easeInOut,
                      )
                      .fadeOut(),

                  Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accentGold.withOpacity(0.2),
                              blurRadius: 40,
                              spreadRadius: 5,
                            ),
                          ],
                          gradient: const LinearGradient(
                            colors: [AppColors.accentGold, AppColors.lightGold],
                          ),
                        ),
                        child: const Icon(
                          Icons.home_work_rounded,
                          size: 60,
                          color: AppColors.backgroundNavy,
                        ),
                      )
                      .animate()
                      .fadeIn(duration: 800.ms)
                      .scale(curve: Curves.elasticOut, duration: 1.seconds),
                ],
              ),
              const SizedBox(height: 48),
              Text(
                    'OTOMAN',
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: AppColors.textMain,
                      letterSpacing: 12,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                  .animate()
                  .fadeIn(delay: 600.ms, duration: 1.seconds)
                  .shimmer(
                    delay: 2.seconds,
                    duration: 1500.ms,
                    color: AppColors.accentGold.withOpacity(0.5),
                  ),
              const SizedBox(height: 12),
              Text(
                    'INTELLIGENT LIVING',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 6,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                  .animate()
                  .fadeIn(delay: 1200.ms, duration: 1.seconds)
                  .slideY(begin: 0.5, end: 0),
            ],
          ),
        ),
      ),
    );
  }
}
