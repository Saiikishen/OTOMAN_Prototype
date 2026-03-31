import 'package:uuid/uuid.dart';

enum ScheduleAction { turnOn, turnOff }

class ScheduleSlot {
  final String id;
  bool enabled;
  int hour;
  int minute;
  ScheduleAction action;

  ScheduleSlot({
    String? id,
    this.enabled = true,
    required this.hour,
    required this.minute,
    required this.action,
  }) : id = id ?? const Uuid().v4();

  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

class DeviceSchedule {
  final String deviceId;
  final List<ScheduleSlot> slots;

  DeviceSchedule({required this.deviceId, List<ScheduleSlot>? slots})
    : slots = slots ?? [];

  void addSlot(ScheduleSlot slot) => slots.add(slot);

  void removeSlot(String id) => slots.removeWhere((s) => s.id == id);

  List<ScheduleSlot> get activeSlots => slots.where((s) => s.enabled).toList();
}
