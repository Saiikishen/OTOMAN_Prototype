import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/schedule_entry.dart';

/// Persists device names, building names, and schedules across app restarts.
class StorageService {
  static const _keyDeviceNames = 'device_names';
  static const _keyBuildingNames = 'building_names';
  static const _keyBuildingLocs = 'building_locations';
  static const _keySchedules = 'schedules';

  // ── Device names ────────────────────────────────────────────

  static Future<Map<String, String>> loadDeviceNames() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyDeviceNames);
    if (raw == null) return {};
    return Map<String, String>.from(jsonDecode(raw));
  }

  static Future<void> saveDeviceNames(Map<String, String> names) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDeviceNames, jsonEncode(names));
  }

  // ── Building names & locations ───────────────────────────────

  static Future<Map<String, String>> loadBuildingNames() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyBuildingNames);
    if (raw == null) return {};
    return Map<String, String>.from(jsonDecode(raw));
  }

  static Future<void> saveBuildingNames(Map<String, String> names) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBuildingNames, jsonEncode(names));
  }

  static Future<Map<String, String>> loadBuildingLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyBuildingLocs);
    if (raw == null) return {};
    return Map<String, String>.from(jsonDecode(raw));
  }

  static Future<void> saveBuildingLocations(Map<String, String> locs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBuildingLocs, jsonEncode(locs));
  }

  // ── Schedules ────────────────────────────────────────────────

  /// Serialises all DeviceSchedules to JSON and saves them.
  static Future<void> saveSchedules(
    Map<String, DeviceSchedule> schedules,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = schedules.map(
      (deviceId, schedule) => MapEntry(
        deviceId,
        schedule.slots
            .map(
              (s) => {
                'id': s.id,
                'enabled': s.enabled,
                'hour': s.hour,
                'minute': s.minute,
                'action': s.action.name, // 'turnOn' | 'turnOff'
              },
            )
            .toList(),
      ),
    );
    await prefs.setString(_keySchedules, jsonEncode(encoded));
  }

  /// Loads and deserialises all DeviceSchedules.
  static Future<Map<String, DeviceSchedule>> loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keySchedules);
    if (raw == null) return {};

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((deviceId, slotsJson) {
      final slots = (slotsJson as List)
          .map(
            (s) => ScheduleSlot(
              id: s['id'] as String,
              enabled: s['enabled'] as bool,
              hour: s['hour'] as int,
              minute: s['minute'] as int,
              action: ScheduleAction.values.byName(s['action'] as String),
            ),
          )
          .toList();
      return MapEntry(
        deviceId,
        DeviceSchedule(deviceId: deviceId, slots: slots),
      );
    });
  }
}
