import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:decimal/decimal.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:mqtt_client/mqtt_client.dart' as mqtt;
import 'package:uuid/uuid.dart';

import 'package:manta_dart/messages.dart';

String generate_session_id() {
  return Uuid().v4();
}

final Logger logger = Logger('MantaStore');

const RECONNECT_INTERVAL = 3;

class MantaStore {
  String session_id;
  final subscriptions = <String>[];
  mqtt.MqttClient client;
  final String application_id;
  final String application_token;
  Stream<AckMessage> acks_stream;
  StreamQueue<AckMessage> acks;
  bool reconnection = true;

  MantaStore(
      {@required this.application_id,
      this.application_token,
      String host = 'localhost',
      mqtt.MqttClient mqtt_client})
      : assert(host?.isNotEmpty) {
    client = (mqtt_client == null)
        ? mqtt.MqttClient(host, generate_session_id())
        : mqtt_client;
    //client.logging(on: true);
    client.keepAlivePeriod = 20;
    client.onDisconnected = onDisconnected;
    client.onUnsubscribed = onUnsubscribed;
    client.setProtocolV311();
  }

  void reconnect() async {
    logger.info('Waiting $RECONNECT_INTERVAL seconds');
    await Future.delayed(const Duration(seconds: RECONNECT_INTERVAL));
    // sleep(Duration(seconds: RECONNECT_INTERVAL));
    logger.info('Reconnecting');
    await connect();
  }

  void onDisconnected() {
    logger.info('Client disconnection');
    if (reconnection) {
      reconnect();
    }
    ;
  }

  void onUnsubscribed(String topic) {
    logger.info('Unsubscribed from $topic');
  }

  Future<void> waitForConnection() async {
    if (client.connectionStatus.state == mqtt.MqttConnectionState.connected) {
      return;
    } else if (client.connectionStatus.state ==
        mqtt.MqttConnectionState.connecting) {
      while (
          client.connectionStatus.state != mqtt.MqttConnectionState.connected) {
        await Future.delayed(Duration(milliseconds: 100));
      }
    }
  }

  void subscribe(String topic) {
    client.subscribe(topic, mqtt.MqttQos.exactlyOnce);
    subscriptions.add(topic);
  }

  void clean() async {
    for (var topic in subscriptions) {
      logger.info('Unsubscribing $topic');
      client.unsubscribe(topic);
    }

    await acks.cancel();

    acks = StreamQueue<AckMessage>(acks_stream.asBroadcastStream());

    subscriptions.clear();
  }

  void connect() async {
    if (client.connectionStatus.state == mqtt.MqttConnectionState.connected) {
      return;
    }
    if (client.connectionStatus.state == mqtt.MqttConnectionState.connecting) {
      await waitForConnection();
      return;
    }

    try {
      await client.connect(application_id, application_token);
      logger.info('Connected');
    } catch (e) {
      logger.warning('Client exception - $e');
      await reconnect();
    }

    // Connect acks_stream

    acks_stream = client.updates.where((c) {
      final tokens = c[0].topic.split('/');
      return tokens[0] == 'acks';
    }).map((List<mqtt.MqttReceivedMessage> c) {
      final recMess = c[0].payload as mqtt.MqttPublishMessage;
      final json_data = mqtt.MqttPublishPayload.bytesToStringAsString(
          recMess.payload.message);
      final ackMessage = AckMessage.fromJson(json.decode(json_data));
      return ackMessage;
    });

    acks = StreamQueue<AckMessage>(acks_stream.asBroadcastStream());
  }

  void disconnect() {
    reconnection = false;
    client.disconnect();
  }

  void dispose() {
    disconnect();
    client = null;
  }

  Future<AckMessage> merchant_order_request(
      {@required Decimal amount, @required String fiat, String crypto}) async {
    await connect();

    await clean();

    session_id = generate_session_id();

    final request = MerchantOrderRequestMessage(
        amount: amount,
        session_id: session_id,
        fiat_currency: fiat,
        crypto_currency: crypto);

    subscribe('acks/$session_id');

    final builder = mqtt.MqttClientPayloadBuilder();
    builder.addString(json.encode(request));

    client.publishMessage('merchant_order_request/$application_id',
        mqtt.MqttQos.atLeastOnce, builder.payload);

    logger.info('Publishing merchant_order_request for session $session_id');

    final ack = await acks.next.timeout(Duration(seconds: 2));

    if (ack.status != 'new') {
      throw Exception('Invalid ack message ${ack.toJson()}');
    }

    logger.info('Received ack: ${ack.toJson()}');

    return ack;
  }

  void merchant_order_cancel() {
    logger.info('Publishing merchant_order_cancel for session $session_id');

    final builder = mqtt.MqttClientPayloadBuilder();
    builder.addString('');

    client.publishMessage('merchant_order_cancel/$session_id',
        mqtt.MqttQos.atLeastOnce, builder.payload);
  }
}

void main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord rec) {
    print('${rec.level.name}: ${rec.time}: ${rec.message}');
  });

  final store = MantaStore(application_id: 'test', host: 'localhost');
  await store.connect();
}
