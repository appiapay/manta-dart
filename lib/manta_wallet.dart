import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart' show StreamQueue;
import 'package:logging/logging.dart' show Logger;
import 'package:meta/meta.dart' show required;
import 'package:mqtt_client/mqtt_client.dart' as mqtt;
import 'package:pointycastle/export.dart' show RSAPublicKey;
import 'package:uuid/uuid.dart' show Uuid;

import 'messages.dart' show AckMessage, BaseMessage, PaymentMessage,
       PaymentRequestEnvelope;
import 'crypto.dart' show RsaKeyHelper;


String generate_session_id() {
  return Uuid().v4();
}

final Logger logger = new Logger('MantaWallet');

const RECONNECT_INTERVAL = 3;
const MQTT_DEFAULT_PORT = 1883;


class MantaWallet {
  String session_id;
  String host;
  int port;
  Map<String, String> topics;
  mqtt.MqttClient client;
  Completer<RSAPublicKey> certificate;
  StreamQueue<RSAPublicKey> certificates;
  StreamQueue<AckMessage> acks;
  StreamQueue<PaymentRequestEnvelope> requests;
  bool _gettingCert = false;
  bool useWebSocket = false;
  bool autoReconnect = false;

  static Match parseUrl(String url) {
    RegExp exp = new RegExp(r"^manta://((?:\w|\.)+)(?::(\d+))?/(.+)$");
    final matches = exp.allMatches(url);
    return matches.isEmpty ? null : matches.first;
  }

  MantaWallet._internal({this.session_id, this.host = "localhost",
      this.port = MQTT_DEFAULT_PORT, mqtt.MqttClient mqtt_client = null,
      this.useWebSocket = false, this.autoReconnect = false}) {
    client = (mqtt_client == null)
      ? mqtt.MqttClient.withPort(host, generate_session_id(), port)
      : mqtt_client;
    //client.logging(true);
    client.keepAlivePeriod = 20;
    client.onDisconnected = onDisconnected;
    client.onConnected = onConnected;
    certificate = Completer();
    topics = {
      'acks': 'acks/$session_id',
      'certificate': 'certificate',
      'payments': 'payments/$session_id',
      'requests': 'payment_requests/$session_id'
    };
  }

  factory MantaWallet(String url, {mqtt.MqttClient mqtt_client = null,
      useWebSocket = false, autoReconnect = false}) {
    final match = MantaWallet.parseUrl(url);
    if (match != null) {
      int port;
      String host = match.group(1);
      if (useWebSocket) {
        port = match.group(2) ?? 443;
        host = "wss://$host/mqtt";
      } else {
        port = match.group(2) ?? MQTT_DEFAULT_PORT;
      }
      MantaWallet inst = MantaWallet._internal(
        session_id: match.group(3),
        host: host,
        port: port,
        mqtt_client: mqtt_client,
        useWebSocket: useWebSocket,
        autoReconnect: autoReconnect);
      inst.client.useAlternateWebSocketImplementation = false;
      return inst;
    }
    return null;
  }

  Stream<AckMessage> _ackStream(String topic) {
    final msg_lists = mqtt.MqttClientTopicFilter(topic, client.updates);
    return msg_lists.updates.map((msgs) {
      final mqtt.MqttPublishMessage msg = msgs[0].payload as mqtt.MqttPublishMessage;
      final String jsonData = mqtt.MqttPublishPayload.bytesToStringAsString(msg.payload.message);
      return AckMessage.fromJson(json.decode(jsonData));
    });
  }

  Stream<RSAPublicKey> _certStream(String topic) {
    final msg_lists = mqtt.MqttClientTopicFilter(topic, client.updates);
    final helper = RsaKeyHelper();
    return msg_lists.updates.map((msgs) {
      final mqtt.MqttPublishMessage msg = msgs[0].payload as mqtt.MqttPublishMessage;
      final String certData = mqtt.MqttPublishPayload.bytesToStringAsString(msg.payload.message);
      return helper.parsePublicKeyFromCertificate(certData);
    });
  }

  Stream<PaymentRequestEnvelope> _requestStream(String topic) {
    final msg_lists = mqtt.MqttClientTopicFilter(topic, client.updates);
    return msg_lists.updates.map((msgs) {
      final mqtt.MqttPublishMessage msg = msgs[0].payload as mqtt.MqttPublishMessage;
      final String jsonData = mqtt.MqttPublishPayload.bytesToStringAsString(msg.payload.message);
      return PaymentRequestEnvelope.fromJson(json.decode(jsonData));
    });
  }

  Future<AckMessage> getAck({Duration timeout = const Duration(seconds: 5)}) async {
    final msg = await acks.next.timeout(timeout);
    return msg;
  }

  void connect() async {
    if (client.connectionStatus.state == mqtt.MqttConnectionState.connected) return;
    if (client.connectionStatus.state == mqtt.MqttConnectionState.connecting) {
      await waitForConnection();
      return;
    }

    try {
      client.useWebSocket = useWebSocket;
      await client.connect();
    } catch (e) {
      logger.warning("Client exception - $e");
      if (autoReconnect) await reconnect();
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
    client.subscribe(topics['certificate'], mqtt.MqttQos.atLeastOnce);
    client.subscribe(topics['requests'], mqtt.MqttQos.atLeastOnce);
    client.subscribe(topics['acks'], mqtt.MqttQos.atLeastOnce);

    certificates = StreamQueue(_certStream(topics['certificate']));
    requests = StreamQueue(_requestStream(topics['requests']));
    acks = StreamQueue(_ackStream(topics['acks']));
    getCertificate();
  }

  void onDisconnected() {
    logger.info("Client disconnection");
    if (autoReconnect) reconnect();
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

  Future<RSAPublicKey> getCertificate({Duration timeout = const Duration(seconds: 5)}) async {
    await connect();
    if (!certificate.isCompleted && !_gettingCert) {
      _gettingCert = true;
      try {
        final msg = await certificates.next
          .timeout(timeout);
        certificate.complete(msg);
      } catch (e) {
        certificate.completeError(e);
      }
    }
    return await certificate.future;
  }

  Future<PaymentRequestEnvelope> getPaymentRequest(
      {String cryptoCurrency = "all", Duration timeout = const Duration(seconds: 5)}) async {
    await connect();

    final mqtt.MqttClientPayloadBuilder builder = new mqtt.MqttClientPayloadBuilder();
    builder.addString("");

    client.publishMessage("payment_requests/$session_id/$cryptoCurrency",
        mqtt.MqttQos.atLeastOnce, builder.payload);

    logger.info("Published payment_requests/$session_id");

    final msg = await requests.next.timeout(timeout);
    return msg;
  }

  void sendPayment({@required String transactionHash,
      @required String cryptoCurrency}) async {
    await connect();
    final message = PaymentMessage(
        transaction_hash: transactionHash, crypto_currency: cryptoCurrency);
    final mqtt.MqttClientPayloadBuilder builder = new mqtt.MqttClientPayloadBuilder();
    builder.addString(jsonEncode(message));

    client.publishMessage(
        topics['payments'], mqtt.MqttQos.atLeastOnce, builder.payload);

  }
}
