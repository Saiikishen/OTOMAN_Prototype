import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Creates the appropriate MQTT client for web platforms.
/// Uses WebSocket transport via MqttBrowserClient.
MqttServerClient createMqttClient(String server, String clientId) {
  final client = MqttBrowserClient(
    'ws://$server:8000/mqtt',
    clientId,
  );
  return client as MqttServerClient;
}
