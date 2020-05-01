import 'dart:async';
import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:mockito/mockito.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:test/test.dart';
import 'package:decimal/decimal.dart';
import 'package:manta_dart/manta_store.dart';
import 'package:manta_dart/messages.dart';

class MockClient extends Mock implements MqttClient {}

MockClient mock_it() {
  final client = MockClient();
  final mqtt_stream_controller =
      StreamController<List<MqttReceivedMessage<MqttMessage>>>();
  final status = MqttClientConnectionStatus();
  status.state = MqttConnectionState.disconnected;

  final ack = AckMessage(status: 'new', url: 'manta://something', txid: '0');
  final publish_message = MqttPublishMessage();
  final builder = MqttClientPayloadBuilder();
  builder.addString(json.encode(ack));
  publish_message.publishData(builder.payload);

  final message = MqttReceivedMessage('acks/123', publish_message);
  when(client.updates)
      .thenAnswer((_) => mqtt_stream_controller.stream.asBroadcastStream());
  when(client.publishMessage('merchant_order_request/application1', any, any))
      .thenAnswer((_) {
    mqtt_stream_controller.add([message]);
    return null;
  });
  when(client.connectionStatus).thenReturn(status);
  when(client.connect()).thenAnswer((_) {
    status.state = MqttConnectionState.connected;
    client.onConnected();
    return Future.value(null);
  });
  return client;
}

void main() {
  test('First test', () {
    var string = 'foo';
    expect(string, equals('foo'));
  });

  test('Connect', () async {
    final client = mock_it();

    final store =
        MantaStore(application_id: 'application1', mqtt_client: client);
    await store.connect();
    verify(client.connect(any, any));
  });

  test('Generate Payment Request', () async {
    final client = mock_it();

    final store =
        MantaStore(application_id: 'application1', mqtt_client: client);

    final ack = await store.merchant_order_request(
        amount: Decimal.parse('0.1'), fiat: 'EUR');

    expect(ack.status, equals('new'));
    expect(ack.txid, equals('0'));
  });
}
