import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:ui';
import '../theme/app_theme.dart';
import '../widgets/device_control_sheets.dart';
import '../services/esp32_service.dart';
import '../services/scheduler_service.dart';
import '../services/storage_service.dart';
import '../models/schedule_entry.dart';

class DashboardScreen extends StatefulWidget {
  final String buildingName;
  const DashboardScreen({super.key, required this.buildingName});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final List<Map<String, dynamic>> devices = [
    {
      'id': 'motor1',
      'name': 'DOL Motor',
      'type': 'Motor',
      'icon': FontAwesomeIcons.powerOff,
      'isActive': false,
    },
    {
      'id': 'motor2',
      'name': 'Normal Motor',
      'type': 'Motor',
      'icon': FontAwesomeIcons.bolt,
      'isActive': false,
    },
  ];

  bool _esp32Online = false;
  StreamSubscription<bool>? _onlineSub;

  @override
  void initState() {
    super.initState();
    _loadSavedNames();
    _fetchInitialState();
    _esp32Online = Esp32Service.esp32Online;
    _onlineSub = Esp32Service.onlineStream.listen((online) {
      if (mounted) setState(() => _esp32Online = online);
    });
    SchedulerService.onScheduledToggle = (deviceId, state) {
      if (!mounted) return;
      setState(() {
        final idx = devices.indexWhere((d) => d['id'] == deviceId);
        if (idx != -1) devices[idx]['isActive'] = state;
      });
    };
    SchedulerService.start();
  }

  Future<void> _loadSavedNames() async {
    final saved = await StorageService.loadDeviceNames();
    if (!mounted) return;
    setState(() {
      for (final device in devices) {
        final id = device['id'] as String;
        if (saved.containsKey(id)) device['name'] = saved[id];
      }
    });
  }

  @override
  void dispose() {
    _onlineSub?.cancel();
    SchedulerService.onScheduledToggle = null;
    super.dispose();
  }

  Future<void> _fetchInitialState() async {
    final status = await Esp32Service.fetchStatus();
    if (mounted) {
      setState(() {
        // Find index correctly in case order changes
        final motor1Idx = devices.indexWhere((d) => d['id'] == 'motor1');
        final motor2Idx = devices.indexWhere((d) => d['id'] == 'motor2');
        if (motor1Idx != -1)
          devices[motor1Idx]['isActive'] = status['motor1'] ?? false;
        if (motor2Idx != -1)
          devices[motor2Idx]['isActive'] = status['motor2'] ?? false;
      });
    }
  }

  Future<void> _toggleDeviceState(int index, bool targetState) async {
    // Optimistic UI update
    setState(() {
      devices[index]['isActive'] = targetState;
    });

    bool success = false;
    final deviceId = devices[index]['id'];

    if (deviceId == 'motor1') {
      success = await Esp32Service.toggleMotor1(targetState);
    } else if (deviceId == 'motor2') {
      success = await Esp32Service.toggleMotor2(targetState);
    }

    // Revert if API failed
    if (!success && mounted) {
      setState(() {
        devices[index]['isActive'] = !targetState; // Revert
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to communicate with ESP32.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _deviceSubtitle(Map<String, dynamic> device) {
    if (!device['isActive']) return 'Offline';
    switch (device['type']) {
      case 'Fan':
        return 'Speed ${device['speed']}';
      case 'AC':
        return '${(device['temperature'] as double).toStringAsFixed(1)}°C · ${device['mode']}';
      default:
        return 'Active';
    }
  }

  Future<void> _showScheduleSheet(int index) async {
    final deviceId = devices[index]['id'] as String;
    final schedule = SchedulerService.getOrCreate(deviceId);
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ScheduleSheet(
        deviceName: devices[index]['name'] as String,
        schedule: schedule,
        onSave: (updated) {
          SchedulerService.upsertSchedule(updated);
          setState(() {});
        },
      ),
    );
  }

  Future<void> _editDevice(int index) async {
    final ctrl = TextEditingController(text: devices[index]['name'] as String);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Edit Device Name',
          style: TextStyle(
            color: AppColors.textMain,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: AppColors.textMain),
          decoration: InputDecoration(
            labelText: 'Name',
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
    if (confirmed == true && mounted && ctrl.text.trim().isNotEmpty) {
      final newName = ctrl.text.trim();
      setState(() => devices[index]['name'] = newName);
      // persist
      final allNames = {
        for (final d in devices) d['id'] as String: d['name'] as String,
      };
      allNames[devices[index]['id'] as String] = newName;
      StorageService.saveDeviceNames(allNames);
    }
  }

  void _onCardTap(int index) {
    final device = devices[index];

    if (device['type'] == 'Fan' || device['type'] == 'AC') {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: device['type'] == 'Fan'
              ? FanControlSheet(
                  isActive: device['isActive'] as bool,
                  speed: device['speed'] as int,
                  onActiveChanged: (val) =>
                      setState(() => devices[index]['isActive'] = val),
                  onSpeedChanged: (val) =>
                      setState(() => devices[index]['speed'] = val),
                )
              : AcControlSheet(
                  isActive: device['isActive'] as bool,
                  temperature: device['temperature'] as double,
                  mode: device['mode'] as String,
                  onActiveChanged: (val) =>
                      setState(() => devices[index]['isActive'] = val),
                  onTemperatureChanged: (val) =>
                      setState(() => devices[index]['temperature'] = val),
                  onModeChanged: (val) =>
                      setState(() => devices[index]['mode'] = val),
                ),
        ),
      );
    } else {
      _toggleDeviceState(index, !(device['isActive'] as bool));
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = devices.where((d) => d['isActive'] as bool).length;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          widget.buildingName.toUpperCase(),
          style: const TextStyle(
            letterSpacing: 2,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.accentGold,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.notifications_none_rounded,
              color: AppColors.accentGold,
              size: 24,
            ),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Background Gradient — matches building_selection_screen
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.backgroundNavy, AppColors.surfaceNavy],
              ),
            ),
          ),
          // Subtle radial glow for atmosphere
          Positioned(
            top: 40,
            right: -50,
            child:
                Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accentGold.withOpacity(0.03),
                      ),
                    )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(
                      begin: const Offset(1, 1),
                      end: const Offset(1.5, 1.5),
                      duration: 4.seconds,
                    ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    height: 10,
                  ), // Extra space to clear Appbar better
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Smart Controls',
                            style: Theme.of(context).textTheme.displayLarge
                                ?.copyWith(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accentGold.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.accentGold.withOpacity(0.2),
                              ),
                            ),
                            child: Text(
                              '$activeCount DEVICES ACTIVE',
                              style: const TextStyle(
                                color: AppColors.accentGold,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 400),
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _esp32Online
                                      ? const Color(0xFF4CAF50)
                                      : Colors.redAccent,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          (_esp32Online
                                                  ? const Color(0xFF4CAF50)
                                                  : Colors.redAccent)
                                              .withOpacity(0.5),
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _esp32Online ? 'ESP32 ONLINE' : 'ESP32 OFFLINE',
                                style: TextStyle(
                                  color: _esp32Online
                                      ? const Color(0xFF4CAF50)
                                      : Colors.redAccent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 18,
                          mainAxisSpacing: 18,
                          childAspectRatio: 0.82,
                        ),
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      final bool isActive = device['isActive'] as bool;
                      final bool hasDetail =
                          device['type'] == 'Fan' || device['type'] == 'AC';

                      return _DeviceCard(
                            device: device,
                            isActive: isActive,
                            hasDetail: hasDetail,
                            subtitle: _deviceSubtitle(device),
                            onTap: () => _onCardTap(index),
                            onLongPress: () async {
                              final choice = await showModalBottomSheet<String>(
                                context: context,
                                backgroundColor: Colors.transparent,
                                builder: (_) => Container(
                                  margin: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceNavy,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(height: 8),
                                      Container(
                                        width: 40,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: Colors.white24,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ListTile(
                                        leading: const Icon(
                                          Icons.edit_outlined,
                                          color: AppColors.accentGold,
                                        ),
                                        title: const Text(
                                          'Edit Name',
                                          style: TextStyle(
                                            color: AppColors.textMain,
                                          ),
                                        ),
                                        onTap: () =>
                                            Navigator.pop(context, 'edit'),
                                      ),
                                      ListTile(
                                        leading: const Icon(
                                          Icons.schedule_rounded,
                                          color: AppColors.accentGold,
                                        ),
                                        title: const Text(
                                          'Set Schedule',
                                          style: TextStyle(
                                            color: AppColors.textMain,
                                          ),
                                        ),
                                        onTap: () =>
                                            Navigator.pop(context, 'schedule'),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                  ),
                                ),
                              );
                              if (choice == 'edit') _editDevice(index);
                              if (choice == 'schedule')
                                _showScheduleSheet(index);
                            },
                            onToggle: (val) => _toggleDeviceState(index, val),
                          )
                          .animate()
                          .fadeIn(delay: (index * 80).ms)
                          .slideY(
                            begin: 0.1,
                            end: 0,
                            curve: Curves.easeOutBack,
                          );
                    },
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

class _DeviceCard extends StatelessWidget {
  final Map<String, dynamic> device;
  final bool isActive;
  final bool hasDetail;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<bool> onToggle;

  const _DeviceCard({
    required this.device,
    required this.isActive,
    required this.hasDetail,
    required this.subtitle,
    required this.onTap,
    required this.onLongPress,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.accentGold
            : AppColors.surfaceNavy.withOpacity(0.8),
        borderRadius: BorderRadius.circular(24),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: AppColors.accentGold.withOpacity(0.4),
                  blurRadius: 25,
                  offset: const Offset(0, 8),
                  spreadRadius: -5,
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white.withOpacity(0.25)
                            : AppColors.backgroundNavy.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        device['icon'] as IconData,
                        color: isActive
                            ? AppColors.backgroundNavy
                            : AppColors.accentGold,
                        size: 20,
                      ),
                    ),
                    if (!hasDetail)
                      Transform.scale(
                        scale: 0.75,
                        child: Switch(
                          value: isActive,
                          onChanged: onToggle,
                          activeThumbColor: AppColors.backgroundNavy,
                          activeTrackColor: Colors.white54,
                          inactiveThumbColor: AppColors.textSecondary,
                          inactiveTrackColor: AppColors.backgroundNavy,
                        ),
                      )
                    else
                      Icon(
                        Icons.more_vert_rounded,
                        color: isActive
                            ? AppColors.backgroundNavy.withOpacity(0.6)
                            : AppColors.textSecondary.withOpacity(0.4),
                        size: 20,
                      ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device['name'] as String,
                      style: TextStyle(
                        color: isActive
                            ? AppColors.backgroundNavy
                            : AppColors.textMain,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle.toUpperCase(),
                      style: TextStyle(
                        color: isActive
                            ? AppColors.backgroundNavy.withOpacity(0.6)
                            : AppColors.textSecondary,
                        fontSize: 9,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Schedule Sheet ────────────────────────────────────────────────────────────

class _ScheduleSheet extends StatefulWidget {
  final String deviceName;
  final DeviceSchedule schedule;
  final ValueChanged<DeviceSchedule> onSave;

  const _ScheduleSheet({
    required this.deviceName,
    required this.schedule,
    required this.onSave,
  });

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  late List<ScheduleSlot> _slots;

  @override
  void initState() {
    super.initState();
    // deep copy so edits don't mutate until saved
    _slots = widget.schedule.slots
        .map(
          (s) => ScheduleSlot(
            id: s.id,
            enabled: s.enabled,
            hour: s.hour,
            minute: s.minute,
            action: s.action,
          ),
        )
        .toList();
  }

  Future<void> _addSlot() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.accentGold,
            surface: AppColors.surfaceNavy,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _slots.add(
        ScheduleSlot(
          hour: picked.hour,
          minute: picked.minute,
          action: ScheduleAction.turnOn,
        ),
      );
    });
  }

  Future<void> _editSlotTime(int index) async {
    final slot = _slots[index];
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: slot.hour, minute: slot.minute),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.accentGold,
            surface: AppColors.surfaceNavy,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _slots[index].hour = picked.hour;
        _slots[index].minute = picked.minute;
      });
    }
  }

  void _save() {
    final updated = DeviceSchedule(
      deviceId: widget.schedule.deviceId,
      slots: _slots,
    );
    widget.onSave(updated);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceNavy,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.deviceName,
                    style: const TextStyle(
                      color: AppColors.textMain,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addSlot,
                    icon: const Icon(
                      Icons.add,
                      color: AppColors.accentGold,
                      size: 18,
                    ),
                    label: const Text(
                      'Add',
                      style: TextStyle(
                        color: AppColors.accentGold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _slots.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            color: AppColors.textSecondary.withOpacity(0.4),
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No schedules yet',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tap Add to create one',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: _slots.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _SlotTile(
                        slot: _slots[i],
                        onToggle: (v) => setState(() => _slots[i].enabled = v),
                        onActionChanged: (v) =>
                            setState(() => _slots[i].action = v),
                        onTimeTap: () => _editSlotTime(i),
                        onDelete: () => setState(() => _slots.removeAt(i)),
                      ),
                    ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentGold,
                    foregroundColor: AppColors.backgroundNavy,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _save,
                  child: const Text(
                    'Save Schedules',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  final ScheduleSlot slot;
  final ValueChanged<bool> onToggle;
  final ValueChanged<ScheduleAction> onActionChanged;
  final VoidCallback onTimeTap;
  final VoidCallback onDelete;

  const _SlotTile({
    required this.slot,
    required this.onToggle,
    required this.onActionChanged,
    required this.onTimeTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isOn = slot.action == ScheduleAction.turnOn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.backgroundNavy,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: slot.enabled
              ? AppColors.accentGold.withOpacity(0.25)
              : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          // Time tap
          GestureDetector(
            onTap: onTimeTap,
            child: Text(
              slot.timeLabel,
              style: TextStyle(
                color: slot.enabled
                    ? AppColors.textMain
                    : AppColors.textSecondary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Action toggle chip
          GestureDetector(
            onTap: () => onActionChanged(
              isOn ? ScheduleAction.turnOff : ScheduleAction.turnOn,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isOn
                    ? AppColors.accentGold.withOpacity(0.15)
                    : Colors.redAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isOn
                      ? AppColors.accentGold.withOpacity(0.4)
                      : Colors.redAccent.withOpacity(0.4),
                ),
              ),
              child: Text(
                isOn ? 'TURN ON' : 'TURN OFF',
                style: TextStyle(
                  color: isOn ? AppColors.accentGold : Colors.redAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          const Spacer(),
          Switch(
            value: slot.enabled,
            onChanged: onToggle,
            activeColor: AppColors.accentGold,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDelete,
            child: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}
