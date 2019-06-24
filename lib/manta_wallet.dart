import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart' show Logger;
import 'package:meta/meta.dart' show required;
import 'package:mqtt_client/mqtt_client.dart' as mqtt;
import "package:pointycastle/export.dart" show RSAPublicKey;
import 'package:uuid/uuid.dart' show Uuid;

import "messages.dart";


String generate_session_id() {
  return Uuid().v4();
}

final Logger logger = new Logger('MantaWallet');

const RECONNECT_INTERVAL = 3;


class MantaWallet {
  String session_id;
  String host;
  int port;

  mqtt.MqttClient client;
  String certificate;

  static Match parseUrl(String url) {
    RegExp exp = new RegExp(r"^manta://((?:\w|\.)+)(?::(\d+))?/(.+)$");
    final matches = exp.allMatches(url);
    return matches.isEmpty ? null : matches.first;
  }

  MantaWallet._internal({this.session_id, this.host = "localhost",
      this.port = 1883, mqtt.MqttClient mqtt_client = null}) {
    client = (mqtt_client == null)
        ? mqtt.MqttClient.withPort(host, generate_session_id(), port)
        : mqtt_client;
    //client.logging(true);
    client.keepAlivePeriod = 20;
    client.onDisconnected = onDisconnected;
    client.onConnected = onConnected;
  }

  factory MantaWallet(String url, {mqtt.MqttClient mqtt_client = null}) {
    final match = MantaWallet.parseUrl(url);
    if (match != null) {
      final port = match.group(2) ?? 1883;
      return MantaWallet._internal(
          session_id: match.group(3),
          host: match.group(1),
          port: port,
          mqtt_client: mqtt_client);
    }
    return null;
  }

  Future<AckMessage> getAck({Duration timeout = Duration(seconds: 5)}) async {
    final msgs = await client.updates
        .where((List<mqtt.MqttReceivedMessage<mqtt.MqttMessage>> msgs) {
          final tokens = msgs[0].topic.split('/');
          return tokens[0] == "acks";
        })
        .timeout(timeout)
        .first;

    final mqtt.MqttPublishMessage recMess = msgs[0].payload as mqtt.MqttPublishMessage;
    final json_data =
        mqtt.MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

    return AckMessage.fromJson(json.decode(json_data));

  }

  void connect() async {
    if (client.connectionStatus.state == mqtt.MqttConnectionState.connected) return;
    if (client.connectionStatus.state == mqtt.MqttConnectionState.connecting) {
      await waitForConnection();
      return;
    }

    try {
      await client.connect();
    } catch (e) {
      logger.warning("Client exception - $e");
      await reconnect();
    }
  }

  void reconnect() async {
    logger.info('Waiting $RECONNECT_INTERVAL seconds');
    sleep(Duration(seconds: RECONNECT_INTERVAL));
    logger.info('Reconnecting');
    await connect();
  }

  void onConnected() {
    logger.info('Connected');
    client.subscribe('certificate', mqtt.MqttQos.atLeastOnce);
  }

  void onDisconnected() {
    logger.info("Client disconnection");
    reconnect();
  }

  void waitForConnection() async {
    if (client.connectionStatus.state == mqtt.MqttConnectionState.connected) {
      return;
    }
    if (client.connectionStatus.state == mqtt.MqttConnectionState.connecting) {
      while (client.connectionStatus.state != mqtt.MqttConnectionState.connected) {
        await Future.delayed(Duration(milliseconds: 100));
      }
    }
  }

  Future<RSAPublicKey> getCertificate() async {
    await connect();
  }

  Future<PaymentRequestEnvelope> getPaymentRequest(
      {String cryptoCurrency = "all"}) async {
    await connect();

    final mqtt.MqttClientPayloadBuilder builder = new mqtt.MqttClientPayloadBuilder();
    builder.addString("");

    client.subscribe("payment_requests/$session_id", mqtt.MqttQos.atLeastOnce);
    client.publishMessage("payment_requests/$session_id/$cryptoCurrency",
        mqtt.MqttQos.atLeastOnce, builder.payload);

    logger.info("Published payment_requests/$session_id");

    final msgs = await client.updates
        .where((List<mqtt.MqttReceivedMessage<mqtt.MqttMessage>> msgs) {
          final tokens = msgs[0].topic.split('/');
          return tokens[0] == "payment_requests";
        })
        .timeout(Duration(seconds: 2))
        .first;

    final mqtt.MqttPublishMessage recMess = msgs[0].payload as mqtt.MqttPublishMessage;
    final json_data =
        mqtt.MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

    final envelope = PaymentRequestEnvelope.fromJson(json.decode(json_data));

    return envelope;
  }

  void sendPayment({@required String transactionHash,
      @required String cryptoCurrency}) async {
    await connect();
    final message = PaymentMessage(
        transaction_hash: transactionHash, crypto_currency: cryptoCurrency);

    final mqtt.MqttClientPayloadBuilder builder = new mqtt.MqttClientPayloadBuilder();
    builder.addString(jsonEncode(message));

    client.subscribe("acks/$session_id", mqtt.MqttQos.atLeastOnce);
    client.publishMessage(
        "payments/$session_id", mqtt.MqttQos.atLeastOnce, builder.payload);

  }
}
