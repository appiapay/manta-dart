import 'dart:async' show Future;
import 'dart:convert' show jsonEncode, jsonDecode, utf8;
import "dart:io" show HttpClient, HttpClientRequest, HttpClientResponse;

import 'package:decimal/decimal.dart';
import 'package:mockito/mockito.dart';
import 'package:mqtt_client/mqtt_client.dart' as mqtt;
import "package:test/test.dart" show expect, isNot, setUp, test;

import "package:manta_dart/crypto.dart" show RsaKeyHelper;
import "package:manta_dart/manta_wallet.dart" show MantaWallet;
import "package:manta_dart/messages.dart" show AckMessage;

const PRIVATE_KEY = "test/certificates/root/keys/test.key";
const CERTIFICATE = "test/certificates/root/certs/test.crt";

class RemoteController {
  int port;
  String host;
  HttpClient client;

  RemoteController(int port, [String host]) {
    this.port = port;
    this.host = host ?? 'localhost';
    client = HttpClient();
  }
  Future<String> send(String path, [Map data = null]) async {
    data ??=  Map();
    HttpClientRequest req = await client.post(host, port, path);
    req.write(jsonEncode(data));
    HttpClientResponse res = await req.close();
    String result = '';
    await res.transform(utf8.decoder).listen((contents) {
        result += contents;
    });
    return result;
  }
}


void main() {
  MantaWallet wallet;
  RemoteController store;
  RemoteController payproc;
  setUp(() {
      wallet = MantaWallet('manta://localhost/123');
      store = RemoteController(8090);
      payproc = RemoteController(8092);
  });
  test("Connection", () async {
      expect(wallet.client.connectionStatus.state,
        mqtt.MqttConnectionState.disconnected);
      await wallet.connect();
      expect(wallet.client.connectionStatus.state,
        mqtt.MqttConnectionState.connected);
  });
  test("Get and verify PaymentRequest with local cert", () async {
      String res = await store.send("/merchant_order",
        {"amount": "10", "fiat": "EUR"});
      print("Res is '${res}'");
      var ack = AckMessage.fromJson(jsonDecode(res));
      wallet = MantaWallet(ack.url);
      await wallet.connect();
      expect(wallet.client.updates.isBroadcast, true);
      var envelope = await wallet.getPaymentRequest(cryptoCurrency: 'NANO');
      final helper = RsaKeyHelper();
      expect(envelope.verify(helper.parsePublicKeyFromCertificateFile(CERTIFICATE)), true);
      var pr = envelope.unpack();
      expect(pr.fiat_currency, "EUR");
  });
  test("Get and verify PaymentRequest with PayProc's cert", () async {
      String res = await store.send("/merchant_order",
        {"amount": "10", "fiat": "EUR"});
      print("Res is '${res}'");
      var ack = AckMessage.fromJson(jsonDecode(res));
      wallet = MantaWallet(ack.url);
      var envelope = await wallet.getPaymentRequest(cryptoCurrency: 'NANO');
      var cert = await wallet.getCertificate(); 
      final helper = RsaKeyHelper();
      expect(envelope.verify(cert), true);
      var pr = envelope.unpack();
      expect(pr.fiat_currency, "EUR");
  });
}
