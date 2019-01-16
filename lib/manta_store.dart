/*
 * Package : mqtt_client
 * Author : S. Hamblett <steve.hamblett@linux.com>
 * Date   : 31/05/2017
 * Copyright :  S.Hamblett
 */

import 'dart:async';
import 'dart:convert';
import 'package:async/async.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:decimal/decimal.dart';
import 'package:uuid/uuid.dart';
import 'package:manta_dart/messages.dart';
import 'package:logging/logging.dart';
import 'dart:io';
import 'package:meta/meta.dart';

String generate_session_id() {
  return Uuid().v4();
}

final Logger logger = new Logger('MantaStore');

const RECONNECT_INTERVAL = 3;

class MantaStore {
  String session_id;
  MqttClient client;
  final String application_id;
  final String application_token;
  Stream<AckMessage> acks_stream;
  StreamQueue<AckMessage> acks;

  MantaStore(
      {@required this.application_id,
      @required this.application_token,
      String host = "localhost",
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

  Future<bool> waitForConnection() async {
    if (client.connectionState == ConnectionState.connected) {
      return true;
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
      await client.connect(application_id, application_token);
      logger.info('Connected');
    } catch (e) {
      logger.warning("Client exception - $e");
      await reconnect();
    }

    // Connect acks_stream

    acks_stream = client.updates.where((List<MqttReceivedMessage> c) {
      final tokens = c[0].topic.split('/');
      return tokens[0] == 'acks';
    }).map((List<MqttReceivedMessage> c) {
      final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
      final json_data =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      return AckMessage.fromJson(json.decode(json_data));
    });

    acks_stream.forEach(print);

    acks = StreamQueue<AckMessage>(acks_stream);
  }

  Future<AckMessage> merchant_order_request(
      {@required Decimal amount,
      @required String fiat,
      String crypto = null}) async {
    await connect();

    this.session_id = generate_session_id();

    final request = MerchantOrderRequestMessage(
        amount: amount,
        session_id: session_id,
        fiat_currency: fiat,
        crypto_currency: crypto);

    client.subscribe("acks/$session_id", MqttQos.atLeastOnce);

    final MqttClientPayloadBuilder builder = new MqttClientPayloadBuilder();
    builder.addString(json.encode(request));

    client.publishMessage("merchant_order_request/$application_id",
        MqttQos.atLeastOnce, builder.payload);

    logger.info("Publishing merchant_order_request for session $session_id");

    final ack = await acks.next.timeout(Duration(seconds: 2));

    if (ack.status != 'new') {
      throw Exception("Invalid ack message");
    }

    return ack;
  }

  merchant_order_cancel() {
    logger.info("Publishing merchant_order_cancel for session $session_id");

    final MqttClientPayloadBuilder builder = new MqttClientPayloadBuilder();
    builder.addString('');

    client.publishMessage(
        "merchant_order_cancel/$session_id", MqttQos.atLeastOnce, builder.payload);
  }
}

void main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord rec) {
    print('${rec.level.name}: ${rec.time}: ${rec.message}');
  });

  final store = MantaStore(application_id: 'test', host: 'localhost');
  await store.connect();

//  await store.merchant_order_request(amount: Decimal.parse("0.1"),
//    fiat: 'EUR');

  print("gatto");
//  while (true) {
//    await MqttUtilities.asyncSleep(1);
//  }
}
