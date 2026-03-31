import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'esp32_service.dart';

/// Talks to the ESP32 while it is in AP (hotspot) mode.
/// The phone must be connected to the "ESP32-Setup" hotspot before calling these.
class WifiProvisionService {
  static const String _esp32Ip = '192.168.4.1';
  static const Duration _timeout = Duration(
    seconds: 30,
  ); // longer — ESP32 tests the creds

  /// Returns true if the ESP32 is reachable in provisioning mode.
  static Future<bool> isReachable() async {
    try {
      final res = await http
          .get(Uri.parse('http://$_esp32Ip/status'))
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Sends WiFi credentials to the ESP32.
  ///
  /// Returns a [ProvisionResult] with success/failure and an optional message.
  /// On success the ESP32 restarts — the app should then guide the user to:
  ///   1. Reconnect their phone to normal WiFi
  ///   2. The MQTT connection takes over automatically
  static Future<ProvisionResult> configure({
    required String ssid,
    required String password,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('http://$_esp32Ip/configure'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'ssid': ssid, 'password': password}),
          )
          .timeout(_timeout);

      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200 && body['success'] == true) {
        return ProvisionResult.success(body['message'] as String? ?? 'Saved!');
      } else {
        return ProvisionResult.failure(
          body['error'] as String? ?? 'Unknown error (${res.statusCode})',
        );
      }
    } on Exception catch (e) {
      return ProvisionResult.failure('Could not reach ESP32: $e');
    }
  }

  /// Sends a WiFi reset command via MQTT so the ESP32 restarts into AP mode.
  /// Call this when the device is already connected on the same network.
  static Future<void> resetWifi() async {
    await Esp32Service.connect();
    if (!Esp32Service.isConnected) return;
    final builder = MqttClientPayloadBuilder()..addString('RESET');
    Esp32Service.publishRaw('esp32/system/wifi', builder);
  }
}

class ProvisionResult {
  final bool success;
  final String message;
  const ProvisionResult._({required this.success, required this.message});

  factory ProvisionResult.success(String msg) =>
      ProvisionResult._(success: true, message: msg);
  factory ProvisionResult.failure(String msg) =>
      ProvisionResult._(success: false, message: msg);
}
