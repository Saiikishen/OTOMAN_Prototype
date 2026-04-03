import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:uuid/uuid.dart';
import '../models/schedule_entry.dart';
import 'scheduler_service.dart';

class Esp32Service {
  static MqttServerClient _client = _createClient();

  static MqttServerClient _createClient() {
    final clientId = 'flutter-app-${Uuid().v4().substring(0, 8)}';
    if (kIsWeb) {
      final client = MqttBrowserClient(
        'ws://broker.hivemq.com:8000/mqtt',
        clientId,
      );
      return client as MqttServerClient;
    }
    return MqttServerClient('broker.hivemq.com', clientId);
  }

  static StreamController<Map<String, bool>> _statusController =
      StreamController<Map<String, bool>>.broadcast();

  static Stream<Map<String, bool>> get statusStream => _statusController.stream;

  // ESP32 online status — updated from esp32/online topic
  static final _onlineController = StreamController<bool>.broadcast();
  static Stream<bool> get onlineStream => _onlineController.stream;
  static bool _esp32Online = false;
  static bool get esp32Online => _esp32Online;

  static bool get isConnected =>
      _client.connectionStatus?.state == MqttConnectionState.connected;

  static bool _listenerAttached = false; // ✅ prevent duplicate listeners

  static Future<void> connect() async {
    if (isConnected) return;

    _client.port = 1883;
    _client.keepAlivePeriod = 20;
    _client.onDisconnected = _onDisconnected;
    _client.logging(on: false);

    try {
      await _client.connect();
    } catch (e) {
      _client.disconnect();
      return;
    }

    if (!isConnected) return;

    _client.subscribe('esp32/status', MqttQos.atLeastOnce);
    _client.subscribe('esp32/online', MqttQos.atLeastOnce);

    // ✅ only attach the listener once
    if (!_listenerAttached) {
      _listenerAttached = true;
      _client.updates!.listen((
        List<MqttReceivedMessage<MqttMessage>> messages,
      ) {
        final msg = messages[0].payload as MqttPublishMessage;
        final topic = messages[0].topic;
        final payload = MqttPublishPayload.bytesToStringAsString(
          msg.payload.message,
        );

        if (topic == 'esp32/online') {
          final online = payload.trim() == 'true';
          _esp32Online = online;
          _onlineController.add(online);
          // Re-publish schedules when ESP32 comes back online
          if (online) {
            SchedulerService.republishSchedules();
          }
          return;
        }

        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          _statusController.add({
            'motor1': data['motor1'] == true,
            'motor2': data['motor2'] == true,
          });
        } catch (_) {}
      });
    }
  }

  static void _onDisconnected() {
    _listenerAttached = false; // ✅ reset so listener re-attaches on reconnect
    Future.delayed(const Duration(seconds: 5), () async {
      await connect(); // ✅ auto-reconnect
    });
  }

  static Future<Map<String, bool>> fetchStatus() async {
    // ✅ listen BEFORE connecting to catch the retained message
    final future = statusStream.first.timeout(const Duration(seconds: 3));
    await connect();
    try {
      return await future;
    } catch (_) {
      return {'motor1': false, 'motor2': false};
    }
  }

  static Future<bool> toggleMotor1(bool targetState) async {
    return _sendCommandAndVerify(1, targetState);
  }

  static Future<bool> toggleMotor2(bool targetState) async {
    return _sendCommandAndVerify(2, targetState);
  }

  static Future<bool> _sendCommandAndVerify(int motor, bool targetState) async {
    await connect();
    if (!isConnected) return false;

    final command = targetState ? 'ON' : 'OFF';
    final motorKey = 'motor$motor';
    final topic = 'esp32/motor$motor/control';

    // Publish the command first
    final builder = MqttClientPayloadBuilder()..addString(command);
    _client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);

    // Now wait up to 10s for the ESP32 to echo back the new state.
    // We use a Completer so we can cancel cleanly on timeout.
    final completer = Completer<bool>();
    late StreamSubscription sub;

    final timer = Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        sub.cancel();
        completer.complete(false);
      }
    });

    sub = statusStream.listen((status) {
      if (status[motorKey] == targetState && !completer.isCompleted) {
        timer.cancel();
        sub.cancel();
        completer.complete(true);
      }
    });

    return completer.future;
  }

  /// Generic publish — used by other services (e.g. WifiProvisionService)
  static void publishRaw(String topic, MqttClientPayloadBuilder builder) {
    if (!isConnected) return;
    _client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  /// Publishes the full schedule list to the ESP32 as a retained message.
  /// The ESP32 saves this to NVS and runs it independently of the app.
  static Future<void> publishSchedules(
    Map<String, DeviceSchedule> schedules,
  ) async {
    await connect();
    if (!isConnected) return;

    final slots = <Map<String, dynamic>>[];
    for (final schedule in schedules.values) {
      final motorNum = int.tryParse(schedule.deviceId.replaceAll('motor', ''));
      if (motorNum == null) continue;
      for (final slot in schedule.slots) {
        slots.add({
          'motor': motorNum,
          'hour': slot.hour,
          'minute': slot.minute,
          'action': slot.action == ScheduleAction.turnOn ? 'ON' : 'OFF',
          'enabled': slot.enabled,
        });
      }
    }

    final payload = jsonEncode(slots);

    // Guard: NVS string limit on ESP32 is ~4000 bytes
    if (payload.length > 3800) {
      debugPrint(
        '[Esp32Service] Schedule payload too large (${payload.length} bytes) — not published',
      );
      return;
    }

    final builder = MqttClientPayloadBuilder()..addString(payload);
    // QoS 1 + retain: ESP32 gets it on reconnect even if offline when published
    _client.publishMessage(
      'esp32/schedules',
      MqttQos.atLeastOnce,
      builder.payload!,
      retain: true,
    );
  }

  static void dispose() {
    _statusController.close();
    _statusController = StreamController<Map<String, bool>>.broadcast();
    _listenerAttached = false;
    _client.disconnect();
    _client = _createClient();
  }
}
