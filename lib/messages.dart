import 'package:decimal/decimal.dart';
import 'package:json_annotation/json_annotation.dart' show JsonSerializable, JsonKey;
import "package:pointycastle/export.dart";
import "package:manta_dart/crypto.dart";
import 'dart:convert' show jsonDecode, jsonEncode;

part 'messages.g.dart';

const MANTA_VERSION = '1.6';

Decimal str_to_decimal(String value) => Decimal.parse(value);

String decimal_to_str(Decimal value) => value.toString();

@JsonSerializable()
class MerchantOrderRequestMessage {
  @JsonKey(fromJson: str_to_decimal, toJson: decimal_to_str)
  Decimal amount;
  String session_id;
  String fiat_currency;
  String crypto_currency;

  MerchantOrderRequestMessage(
      {Decimal this.amount,
      String this.session_id,
      String this.fiat_currency,
      String this.crypto_currency});
}

@JsonSerializable()
class AckMessage {
  String txid;
  String status;
  String url;

  @JsonKey(fromJson: str_to_decimal, toJson: decimal_to_str)
  Decimal amount;
  String transaction_hash;
  String transaction_currency;
  String memo;

  AckMessage(
      {this.txid,
      this.status,
      this.url,
      this.amount,
      this.transaction_hash,
      this.transaction_currency,
      this.memo});

  factory AckMessage.fromJson(Map<String, dynamic> json) =>
      _$AckMessageFromJson(json);
}

@JsonSerializable()
class Destination {
  @JsonKey(fromJson: str_to_decimal, toJson: decimal_to_str)
  Decimal amount;

  String destination_address;
  String crypto_currency;

  Destination({
    this.amount,
    this.destination_address,
    this.crypto_currency,
  });

  Map<String, dynamic> toJson() => _$DestinationToJson(this);
  factory Destination.fromJson(Map<String, dynamic> json) =>
      _$DestinationFromJson(json);
}

@JsonSerializable()
class Merchant {
  String name;
  String address;

  Merchant({this.name, this.address});

  Map<String, dynamic> toJson() => _$MerchantToJson(this);
  factory Merchant.fromJson(Map<String, dynamic> json) =>
      _$MerchantFromJson(json);
}

@JsonSerializable()
class PaymentRequestMessage {
  Merchant merchant;

  @JsonKey(fromJson: str_to_decimal, toJson: decimal_to_str)
  Decimal amount;

  String fiat_currency;
  List<Destination> destinations;
  Set<String> supported_cryptos;

  Map<String, dynamic> toJson() => _$PaymentRequestMessageToJson(this);
  factory PaymentRequestMessage.fromJson(Map<String, dynamic> json) =>
    _$PaymentRequestMessageFromJson(json);

  PaymentRequestMessage(
      {this.merchant,
      this.amount,
      this.fiat_currency,
      this.destinations,
      this.supported_cryptos});

  PaymentRequestEnvelope getEnvelope(RSAPrivateKey key) {
    final jsonMessage = jsonEncode(this);
    final helper = RsaKeyHelper();
    final signature = helper.sign(jsonMessage, key);

    return PaymentRequestEnvelope(
      message: jsonMessage,
      signature: signature,
    );
  }
}

@JsonSerializable()
class PaymentRequestEnvelope {
  String message;
  String signature;
  String version;

  PaymentRequestEnvelope(
      {this.message, this.signature, this.version = MANTA_VERSION});

  Map<String, dynamic> toJson() => _$PaymentRequestEnvelopeToJson(this);

  factory PaymentRequestEnvelope.fromJson(Map<String, dynamic> json) =>
      _$PaymentRequestEnvelopeFromJson(json);
  
  PaymentRequestMessage unpack() {
    return PaymentRequestMessage.fromJson(jsonDecode(this.message));
  }
}

@JsonSerializable()
class PaymentMessage {
  String crypto_currency;
  String transaction_hash;
  String version;

  PaymentMessage(
  {this.crypto_currency, this.transaction_hash, this.version = MANTA_VERSION}
      );

  Map<String, dynamic> toJson() => _$PaymentMessageToJson(this);

  factory PaymentMessage.fromJson(Map<String, dynamic> json) =>
      _$PaymentMessageFromJson(json);

}