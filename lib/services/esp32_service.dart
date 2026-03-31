import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';

class Esp32Service {
  static MqttServerClient _client = _createClient();

  static MqttServerClient _createClient() {
    return MqttServerClient(
      'broker.hivemq.com',
      'flutter-app-${const Uuid().v4().substring(0, 8)}',
    );
  }

  static StreamController<Map<String, bool>> _statusController =
      StreamController<Map<String, bool>>.broadcast();

  static Stream<Map<String, bool>> get statusStream => _statusController.stream;

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

    // ✅ only attach the listener once
    if (!_listenerAttached) {
      _listenerAttached = true;
      _client.updates!.listen((
        List<MqttReceivedMessage<MqttMessage>> messages,
      ) {
        final msg = messages[0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(
          msg.payload.message,
        );
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

    // Listen for the ESP32's status echo BEFORE sending the command
    final verified = statusStream
        .where((s) => s[motorKey] == targetState)
        .first
        .timeout(const Duration(seconds: 5), onTimeout: () => {});

    final topic = 'esp32/motor$motor/control';
    final builder = MqttClientPayloadBuilder()..addString(command);
    _client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);

    try {
      final result = await verified;
      return result.isNotEmpty; // empty map = timeout = no echo received
    } catch (_) {
      return false;
    }
  }

  /// Generic publish — used by other services (e.g. WifiProvisionService)
  static void publishRaw(String topic, MqttClientPayloadBuilder builder) {
    if (!isConnected) return;
    _client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  static void dispose() {
    _statusController.close();
    _statusController = StreamController<Map<String, bool>>.broadcast();
    _listenerAttached = false;
    _client.disconnect();
    _client = _createClient();
  }
}
