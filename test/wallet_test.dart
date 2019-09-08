import 'dart:async';
import 'dart:convert';
import "dart:io";

import 'package:decimal/decimal.dart';
import 'package:mockito/mockito.dart';
import 'package:mqtt_client/mqtt_client.dart';
import "package:test/test.dart" show equals, expect, isNotNull, isNull,
        test;

import "package:manta_dart/crypto.dart";
import "package:manta_dart/manta_wallet.dart";
import "package:manta_dart/messages.dart";

const PRIVATE_KEY = "test/certificates/root/keys/test.key";
const CERTIFICATE = "test/certificates/root/certs/test.crt";

class MockClient extends Mock implements MqttClient {}

MockClient mock_it() {
  final client = MockClient();
  final status = MqttClientConnectionStatus();
  status.state = MqttConnectionState.disconnected;

  final mqtt_stream_controller = StreamController<List<MqttReceivedMessage<MqttMessage>>>();

  var publish_message = MqttPublishMessage();
  MqttClientPayloadBuilder builder = MqttClientPayloadBuilder();
  builder.addString(json.encode(payment_request()));

  publish_message.publishData(builder.payload);

  final message = MqttReceivedMessage("payment_requests/123", publish_message);

  publish_message = MqttPublishMessage();
  builder = MqttClientPayloadBuilder();
  builder.addString(File(CERTIFICATE).readAsStringSync());
  publish_message.publishData(builder.payload);

  final certMessage = MqttReceivedMessage("certificate", publish_message);
  final updates = mqtt_stream_controller.stream.asBroadcastStream();

  when(client.updates)
    .thenAnswer((_) => updates);
  when(client.publishMessage("payment_requests/123/BTC", any, any))
    .thenAnswer((_) {
        mqtt_stream_controller.add([message]);
        return null;
    });
  when(client.subscribe('certificate', MqttQos.atLeastOnce))
    .thenAnswer((_) {
        mqtt_stream_controller.add([certMessage]);
        return null;
    });
  when(client.connectionStatus).thenReturn(status);
  when(client.connect())
    .thenAnswer((_) {
        status.state = MqttConnectionState.connected;
        if (client.onConnected != null) {
          client.onConnected();
        }
        return Future.value(null);
    });
  return client;
}

final DESTINATIONS = [
  Destination(
      amount: Decimal.fromInt(5),
      destination_address: "btc_daddress",
      crypto_currency: "BTC"),
  Destination(
      amount: Decimal.fromInt(10),
      destination_address: "nano_daddress",
      crypto_currency: "NANO")
];

final MERCHANT = Merchant(name: "Merchant 1", address: "5th Avenue");

PaymentRequestEnvelope payment_request() {
  final helper = RsaKeyHelper();
  final privKey = helper.parsePrivateKeyFromPemFile(PRIVATE_KEY);

  final message = PaymentRequestMessage(
      merchant: MERCHANT,
      amount: Decimal.fromInt(10),
      fiat_currency: 'EURO',
      destinations: DESTINATIONS,
      supported_cryptos: Set.from(['BTC', 'XMR', 'NANO']));

  return message.getEnvelope(privKey);
}

void main() {
  test("First test", () {
    var string = "foo";
    expect(string, equals("foo"));
  });

  test("Parse url", () {
    final match =
        MantaWallet.parseUrl("manta://localhost/JqhCQ64gTYi02xu4GhBzZg==");
    expect(match.group(1), equals('localhost'));
    expect(match.group(3), equals('JqhCQ64gTYi02xu4GhBzZg=='));
  });

  test("Parse url with port", () {
    final match = MantaWallet.parseUrl("manta://127.0.0.1:8000/123");
    expect(match.group(1), equals('127.0.0.1'));
    expect(match.group(2), equals('8000'));
    expect(match.group(3), equals('123'));
  });

  test("Parse invalid url", () {
    final match = MantaWallet.parseUrl("mantas://127.0.0.1:8000/123");
    expect(match, isNull);
  });

  test("Test factory", () {
    final wallet = MantaWallet("manta://127.0.0.1/123");
    expect(wallet.host, equals('127.0.0.1'));
    expect(wallet.port, equals(1883));
    expect(wallet.session_id, equals('123'));
  });

  test("Get payment request", () async {
    final client = mock_it();
    final wallet = MantaWallet("manta://127.0.0.1/123", mqtt_client: client);
    await wallet.connect();
    wallet.onConnected(); // this is only needed due to the mock not working
                          // very well
    final envelope = await wallet.getPaymentRequest(cryptoCurrency: "BTC");
    final helper = RsaKeyHelper();
    final pr = envelope.unpack();

    expect(pr.merchant.name, equals('Merchant 1'));
    expect(pr.destinations[0].amount, equals(Decimal.fromInt(5)));
    expect(pr.destinations[0].destination_address, equals('btc_daddress'));
    expect(envelope.verify(helper.parsePublicKeyFromCertificateFile(CERTIFICATE)), true);
});


  test("Send Payment", () async {
    final client = mock_it();
    final wallet = MantaWallet("manta://127.0.0.1/123", mqtt_client: client);
    await wallet.connect();
    wallet.onConnected(); // this is only needed due to the mock not working
                          // very well
    await wallet.sendPayment(transactionHash: "myhash", cryptoCurrency: "NANO");

    final publishedParams =
        verify(client.publishMessage(captureAny, any, captureAny)).captured;

    final topic = publishedParams[0];
    final payload = String.fromCharCodes(publishedParams[1]);
    final pm = PaymentMessage.fromJson(jsonDecode(payload));

    expect(pm.transaction_hash, equals("myhash"));
    expect(pm.crypto_currency, equals("NANO"));
    expect(topic, equals("payments/123"));
  });

  test("Receive certificate", () async {
    final client = mock_it();
    final wallet = MantaWallet("manta://127.0.0.1/123", mqtt_client: client);
    await wallet.connect();
    wallet.onConnected(); // this is only needed due to the mock not working
                          // very well
    final cert = wallet.getCertificate();
    expect(cert , isNotNull);
  });
}
