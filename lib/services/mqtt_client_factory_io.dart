import 'package:mqtt_client/mqtt_server_client.dart';

/// Creates the appropriate MQTT client for non-web (mobile/desktop) platforms.
MqttServerClient createMqttClient(String server, String clientId) {
  return MqttServerClient(server, clientId);
}
