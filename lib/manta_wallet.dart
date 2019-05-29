import 'package:mqtt_client/mqtt_client.dart';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart' show Future;
import 'package:logging/logging.dart' show Logger;
import 'package:meta/meta.dart' show required;
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

  MqttClient client;

  static Match parse_url(String url) {
    RegExp exp = new RegExp(r"^manta://((?:\w|\.)+)(?::(\d+))?/(.+)$");
    final matches = exp.allMatches(url);
    return matches.isEmpty ? null : matches.first;
  }

  MantaWallet._internal(
      {this.session_id,
      this.host = "localhost",
      this.port = 1883,
      MqttClient mqtt_client = null}) {
    client = (mqtt_client == null)
        ? MqttClient(host, generate_session_id())
        : mqtt_client;
    //client.logging(true);
    client.keepAlivePeriod = 20;
    client.onDisconnected = onDisconnected;
  }

  void reconnect() async {
    logger.info('Waiting $RECONNECT_INTERVAL seconds');
    sleep(Duration(seconds: RECONNECT_INTERVAL));
    logger.info('Reconnecting');
    await connect();
  }

  void onDisconnected() {
    logger.info("Client disconnection");
    reconnect();
  }

  void waitForConnection() async {
    if (client.connectionState == ConnectionState.connected) {
      return;
    }
    if (client.connectionState == ConnectionState.connecting) {
      while (client.connectionState != ConnectionState.connected) {
        await Future.delayed(Duration(milliseconds: 100));
      }
    }
  }

  void connect() async {
    if (client.connectionState == ConnectionState.connected) return;
    if (client.connectionState == ConnectionState.connecting) {
      await waitForConnection();
      return;
    }

    try {
      await client.connect();
      logger.info('Connected');
    } catch (e) {
      logger.warning("Client exception - $e");
      await reconnect();
    }
  }

  factory MantaWallet(String url, {MqttClient mqtt_client = null}) {
    final match = MantaWallet.parse_url(url);
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

  Future<PaymentRequestEnvelope> getPaymentRequest(
      {String cryptoCurrency = "all"}) async {
    await connect();

    final MqttClientPayloadBuilder builder = new MqttClientPayloadBuilder();
    builder.addString("");

    client.subscribe("payment_requests/$session_id", MqttQos.atLeastOnce);
    client.publishMessage("payment_requests/$session_id/$cryptoCurrency",
        MqttQos.atLeastOnce, builder.payload);

    logger.info("Published payment_requests/$session_id");

    final msgs = await client.updates
        .where((List<MqttReceivedMessage> msgs) {
          final tokens = msgs[0].topic.split('/');
          return tokens[0] == "payment_requests";
        })
        .timeout(Duration(seconds: 2))
        .first;

    final MqttPublishMessage recMess = msgs[0].payload as MqttPublishMessage;
    final json_data =
        MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

    final envelope = PaymentRequestEnvelope.fromJson(json.decode(json_data));

    return envelope;
  }

  void sendPayment(
      {@required String transactionHash,
      @required String cryptoCurrency}) async {
    await connect();
    final message = PaymentMessage(
        transaction_hash: transactionHash, crypto_currency: cryptoCurrency);

    final MqttClientPayloadBuilder builder = new MqttClientPayloadBuilder();
    builder.addString(jsonEncode(message));

    client.subscribe("acks/$session_id", MqttQos.atLeastOnce);
    client.publishMessage(
        "payments/$session_id", MqttQos.atLeastOnce, builder.payload);
  }
}
