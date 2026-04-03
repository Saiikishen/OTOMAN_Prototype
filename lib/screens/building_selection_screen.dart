import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:ui';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'provisioning_screen.dart';
import '../services/storage_service.dart';

class BuildingSelectionScreen extends StatefulWidget {
  const BuildingSelectionScreen({super.key});

  @override
  State<BuildingSelectionScreen> createState() =>
      _BuildingSelectionScreenState();
}

class _BuildingSelectionScreenState extends State<BuildingSelectionScreen> {
  final List<Map<String, dynamic>> buildings = [
    {
      'name': 'Kannur Heights',
      'location': 'Kannur City',
      'icon': Icons.apartment_rounded,
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedNames();
  }

  Future<void> _loadSavedNames() async {
    final names = await StorageService.loadBuildingNames();
    final locs = await StorageService.loadBuildingLocations();
    if (!mounted) return;
    setState(() {
      for (int i = 0; i < buildings.length; i++) {
        final key = 'building_$i';
        if (names.containsKey(key)) buildings[i]['name'] = names[key];
        if (locs.containsKey(key)) buildings[i]['location'] = locs[key];
      }
    });
  }

  Future<void> _editBuilding(int index) async {
    final nameCtrl = TextEditingController(
      text: buildings[index]['name'] as String,
    );
    final locCtrl = TextEditingController(
      text: buildings[index]['location'] as String,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Edit Building',
          style: TextStyle(
            color: AppColors.textMain,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _EditField(controller: nameCtrl, label: 'Name'),
            const SizedBox(height: 12),
            _EditField(controller: locCtrl, label: 'Location'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Save',
              style: TextStyle(
                color: AppColors.accentGold,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        buildings[index]['name'] = nameCtrl.text.trim().isEmpty
            ? buildings[index]['name']
            : nameCtrl.text.trim();
        buildings[index]['location'] = locCtrl.text.trim().isEmpty
            ? buildings[index]['location']
            : locCtrl.text.trim();
      });
      // persist
      final names = {
        for (int i = 0; i < buildings.length; i++)
          'building_$i': buildings[i]['name'] as String,
      };
      final locs = {
        for (int i = 0; i < buildings.length; i++)
          'building_$i': buildings[i]['location'] as String,
      };
      StorageService.saveBuildingNames(names);
      StorageService.saveBuildingLocations(locs);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.backgroundNavy, AppColors.surfaceNavy],
              ),
            ),
          ),
          Positioned(
            top: -100,
            left: -100,
            child:
                Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accentGold.withOpacity(0.05),
                      ),
                    )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(
                      begin: const Offset(1, 1),
                      end: const Offset(1.3, 1.3),
                      duration: 6.seconds,
                    ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'WELCOME BACK,',
                            style: TextStyle(
                              color: AppColors.accentGold.withOpacity(0.6),
                              letterSpacing: 3,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ).animate().fadeIn().slideX(begin: -0.2, end: 0),
                          const SizedBox(height: 4),
                          Text(
                                'Select Home',
                                style: Theme.of(context).textTheme.displayLarge
                                    ?.copyWith(
                                      fontSize: 34,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -1,
                                    ),
                              )
                              .animate()
                              .fadeIn(delay: 200.ms)
                              .slideX(begin: -0.1, end: 0),
                        ],
                      ),
                      PopupMenuButton<String>(
                        icon: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceNavy,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white10),
                          ),
                          child: const Icon(
                            Icons.settings_outlined,
                            color: AppColors.accentGold,
                            size: 20,
                          ),
                        ),
                        color: AppColors.surfaceNavy,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: Colors.white.withOpacity(0.08),
                          ),
                        ),
                        onSelected: (value) {
                          if (value == 'configure_wifi') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ProvisioningScreen(),
                              ),
                            );
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'configure_wifi',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.wifi_tethering,
                                  color: AppColors.accentGold,
                                  size: 18,
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Configure ESP32 WiFi',
                                  style: TextStyle(
                                    color: AppColors.textMain,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ).animate().fadeIn(delay: 400.ms).scale(),
                    ],
                  ),
                  const SizedBox(height: 40),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 20),
                      itemCount: buildings.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 20),
                      itemBuilder: (context, index) {
                        final building = buildings[index];
                        return _BuildingCard(
                              name: building['name'] as String,
                              location: building['location'] as String,
                              icon: building['icon'] as IconData,
                              onTap: () => Navigator.push(
                                context,
                                PageRouteBuilder(
                                  pageBuilder: (context, animation, _) =>
                                      DashboardScreen(
                                        buildingName:
                                            building['name'] as String,
                                      ),
                                  transitionsBuilder:
                                      (context, animation, _, child) {
                                        var tween =
                                            Tween(
                                              begin: const Offset(1.0, 0.0),
                                              end: Offset.zero,
                                            ).chain(
                                              CurveTween(
                                                curve: Curves.easeOutQuart,
                                              ),
                                            );
                                        return SlideTransition(
                                          position: animation.drive(tween),
                                          child: child,
                                        );
                                      },
                                  transitionDuration: 600.ms,
                                ),
                              ),
                              onLongPress: () => _editBuilding(index),
                            )
                            .animate()
                            .fadeIn(delay: (400 + (index * 100)).ms)
                            .slideY(begin: 0.1, end: 0);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const _EditField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: AppColors.textMain),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accentGold),
        ),
      ),
    );
  }
}

class _BuildingCard extends StatelessWidget {
  final String name;
  final String location;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _BuildingCard({
    required this.name,
    required this.location,
    required this.icon,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
            spreadRadius: -5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: AppColors.surfaceNavy.withOpacity(0.4),
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundNavy,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accentGold.withOpacity(0.1),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Icon(icon, color: AppColors.accentGold, size: 26),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: AppColors.textMain,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                color: AppColors.accentGold.withOpacity(0.5),
                                size: 12,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                location.toUpperCase(),
                                style: TextStyle(
                                  color: AppColors.textSecondary.withOpacity(
                                    0.7,
                                  ),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: AppColors.accentGold.withOpacity(0.4),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
