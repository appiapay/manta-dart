import 'dart:convert' show json, jsonEncode, jsonDecode;
import "dart:io" show File;

import 'package:decimal/decimal.dart' show Decimal;
import "package:pointycastle/export.dart" show RSAPublicKey;
import 'package:test/test.dart' show expect, equals, isNot, test;

import 'package:manta_dart/crypto.dart' show RsaKeyHelper;
import 'package:manta_dart/messages.dart' show AckMessage, PaymentRequestEnvelope;

void main() {
  test('AckMessage encode', () {
    final ack = AckMessage(
        status: 'new',
        url: 'manta://something',
        txid: '0',
        amount: Decimal.parse('5.45'));
    expect(
        ack.toJson(),
        equals({
          'status': 'new',
          'url': 'manta://something',
          'txid': '0',
          'amount': '5.45',
          'transaction_hash': null,
          'transaction_currency': null,
          'memo': null
        }));
  });
  test('AckMessage decode', () {
    AckMessage ack = AckMessage.fromJson({
      'status': 'new',
      'url': 'manta://something',
      'txid': '0',
      'amount': '5.45',
      'transaction_hash': null,
      'transaction_currency': null,
      'memo': null
    });
    expect(
        ack,
        equals(AckMessage(
            status: 'new',
            url: 'manta://something',
            txid: '0',
            amount: Decimal.parse('5.45'))));
  });
  test('Equality test with same class', () {
    var a = AckMessage(status: 'new');
    var b = AckMessage(status: 'new');
    expect(b, equals(a));
    b.memo = 'foo';
    expect(b, isNot(equals(a)));
  });
  test('Verify PaymentRequestEnvelope signature', () {
      var msg_file = File('test/payment_request_envelope.json');
      var envelope = PaymentRequestEnvelope.fromJson(
        jsonDecode(msg_file.readAsStringSync()));
      var cert = File('test/certificates/root/certs/test.crt');
      var helper = RsaKeyHelper();
      RSAPublicKey key = helper.parsePublicKeyFromCertificate(cert.readAsStringSync());
      expect(envelope.verify(key), true);
      envelope.message += 'foo';
      expect(envelope.verify(key), false);
  });
}
