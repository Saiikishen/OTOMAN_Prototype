import 'dart:async';
import '../models/schedule_entry.dart';
import 'esp32_service.dart';
import 'storage_service.dart';

class SchedulerService {
  static Timer? _timer;
  static final Map<String, DeviceSchedule> _schedules = {};

  static void Function(String deviceId, bool state)? onScheduledToggle;

  static Future<void> init() async {
    final saved = await StorageService.loadSchedules();
    _schedules.addAll(saved);
  }

  static void upsertSchedule(DeviceSchedule schedule) {
    _schedules[schedule.deviceId] = schedule;
    StorageService.saveSchedules(_schedules); // persist immediately
  }

  static DeviceSchedule getOrCreate(String deviceId) {
    return _schedules.putIfAbsent(
      deviceId,
      () => DeviceSchedule(deviceId: deviceId),
    );
  }

  static void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static void _check() {
    final now = DateTime.now();

    for (final schedule in _schedules.values) {
      for (final slot in schedule.activeSlots) {
        if (slot.hour == now.hour && slot.minute == now.minute) {
          final state = slot.action == ScheduleAction.turnOn;
          _trigger(schedule.deviceId, state);
        }
      }
    }
  }

  static void _trigger(String deviceId, bool state) {
    if (deviceId == 'motor1') Esp32Service.toggleMotor1(state);
    if (deviceId == 'motor2') Esp32Service.toggleMotor2(state);
    onScheduledToggle?.call(deviceId, state);
  }
}
