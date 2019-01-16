import "package:test/test.dart";
import "package:manta_dart/manta_wallet.dart";
import "package:manta_dart/crypto.dart";
import "package:manta_dart/messages.dart";
import 'package:decimal/decimal.dart';
import 'package:mockito/mockito.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'dart:async';
import 'dart:convert';
import "dart:io";

class MockClient extends Mock implements MqttClient {}

MockClient mock_it() {
  final client = MockClient();

  final mqtt_stream_controller = StreamController<List<MqttReceivedMessage>>();

  final publish_message = MqttPublishMessage();
  final MqttClientPayloadBuilder builder = new MqttClientPayloadBuilder();
  builder.addString(json.encode(payment_request()));

  publish_message.publishData(builder.payload);

  final message = MqttReceivedMessage("payment_requests/123", publish_message);

  when(client.updates)
      .thenAnswer((_) => mqtt_stream_controller.stream.asBroadcastStream());

  when(client.publishMessage("payment_requests/123/BTC", any, any))
      .thenAnswer((_) {
    mqtt_stream_controller.add([message]);
    return null;
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
  final privKey = helper.parsePrivateKeyFromPemFile("certs/test.key");

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
        MantaWallet.parse_url("manta://localhost/JqhCQ64gTYi02xu4GhBzZg==");
    expect(match.group(1), equals('localhost'));
    expect(match.group(3), equals('JqhCQ64gTYi02xu4GhBzZg=='));
  });

  test("Parse url with port", () {
    final match = MantaWallet.parse_url("manta://127.0.0.1:8000/123");
    expect(match.group(1), equals('127.0.0.1'));
    expect(match.group(2), equals('8000'));
    expect(match.group(3), equals('123'));
  });

  test("Parse invalid url", () {
    final match = MantaWallet.parse_url("mantas://127.0.0.1:8000/123");
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

    final envelope = await wallet.getPaymentRequest(cryptoCurrency: "BTC");

    final pr = envelope.unpack();

    expect(pr.merchant.name, equals('Merchant 1'));
    expect(pr.destinations[0].amount, equals(Decimal.fromInt(5)));
    expect(pr.destinations[0].destination_address, equals('btc_daddress'));
  });

  test("Send Payment", () async {
    final client = mock_it();

    final wallet = MantaWallet("manta://127.0.0.1/123", mqtt_client: client);

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
}
