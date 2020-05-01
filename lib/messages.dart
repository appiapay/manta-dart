import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:decimal/decimal.dart' show Decimal;
import 'package:json_annotation/json_annotation.dart'
    show JsonSerializable, JsonKey;
import "package:pointycastle/export.dart" show RSAPrivateKey, RSAPublicKey;

import "crypto.dart" show RsaKeyHelper;

part 'messages.g.dart';

const MANTA_VERSION = '1.6';
const HASHCODE_K = 37 * 17;

Decimal str_to_decimal(String value) =>
    value == 'null' ? null : Decimal.parse(value);

String decimal_to_str(Decimal value) => value.toString();

abstract class BaseMessage {
  bool _equalData(BaseMessage other) {
    return (jsonEncode(this) == jsonEncode(other));
  }

  @override
  int get hashCode {
    // don't ask me why, see https://dart.dev/guides/libraries/library-tour#implementing-map-keys
    return HASHCODE_K + jsonEncode(this).hashCode;
  }
}

@JsonSerializable()
class MerchantOrderRequestMessage extends BaseMessage {
  @JsonKey(fromJson: str_to_decimal, toJson: decimal_to_str)
  Decimal amount;
  String session_id;
  String fiat_currency;
  String crypto_currency;
  String version = MANTA_VERSION;

  MerchantOrderRequestMessage(
      {this.amount,
      this.session_id,
      this.fiat_currency,
      this.crypto_currency,
      this.version = MANTA_VERSION});

  factory MerchantOrderRequestMessage.fromJson(Map<String, dynamic> json) =>
      _$MerchantOrderRequestMessageFromJson(json);

  @override
  bool operator ==(dynamic other) {
    // cannot use reflection, gets in the way of flutter's tree shaking
    if (other is! MerchantOrderRequestMessage) {
      return false;
    }
    return _equalData(other);
  }

  Map<String, dynamic> toJson() => _$MerchantOrderRequestMessageToJson(this);
}

@JsonSerializable()
class AckMessage extends BaseMessage {
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

  @override
  bool operator ==(dynamic other) {
    // cannot use reflection, gets in the way of flutter's tree shaking
    if (other is! AckMessage) {
      return false;
    }
    return _equalData(other);
  }

  Map<String, dynamic> toJson() => _$AckMessageToJson(this);
}

@JsonSerializable()
class Destination extends BaseMessage {
  @JsonKey(fromJson: str_to_decimal, toJson: decimal_to_str)
  Decimal amount;

  String destination_address;
  String crypto_currency;

  Destination({
    this.amount,
    this.destination_address,
    this.crypto_currency,
  });

  factory Destination.fromJson(Map<String, dynamic> json) =>
      _$DestinationFromJson(json);

  @override
  bool operator ==(dynamic other) {
    // cannot use reflection, gets in the way of flutter's tree shaking
    if (other is! Destination) {
      return false;
    }
    return _equalData(other);
  }

  Map<String, dynamic> toJson() => _$DestinationToJson(this);
}

@JsonSerializable()
class Merchant extends BaseMessage {
  String name;
  String address;

  Merchant({this.name, this.address});

  factory Merchant.fromJson(Map<String, dynamic> json) =>
      _$MerchantFromJson(json);

  @override
  bool operator ==(dynamic other) {
    // cannot use reflection, gets in the way of flutter's tree shaking
    if (other is! Merchant) {
      return false;
    }
    return _equalData(other);
  }

  Map<String, dynamic> toJson() => _$MerchantToJson(this);
}

@JsonSerializable()
class PaymentRequestMessage extends BaseMessage {
  Merchant merchant;

  @JsonKey(fromJson: str_to_decimal, toJson: decimal_to_str)
  Decimal amount;

  String fiat_currency;
  List<Destination> destinations;
  Set<String> supported_cryptos;

  factory PaymentRequestMessage.fromJson(Map<String, dynamic> json) =>
      _$PaymentRequestMessageFromJson(json);

  PaymentRequestMessage(
      {this.merchant,
      this.amount,
      this.fiat_currency,
      this.destinations,
      this.supported_cryptos});

  @override
  bool operator ==(dynamic other) {
    // cannot use reflection, gets in the way of flutter's tree shaking
    if (other is! PaymentRequestMessage) {
      return false;
    }
    return _equalData(other);
  }

  Map<String, dynamic> toJson() => _$PaymentRequestMessageToJson(this);

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
class PaymentRequestEnvelope extends BaseMessage {
  String message;
  String signature;
  String version = MANTA_VERSION;

  PaymentRequestEnvelope(
      {this.message, this.signature, this.version = MANTA_VERSION});

  factory PaymentRequestEnvelope.fromJson(Map<String, dynamic> json) =>
      _$PaymentRequestEnvelopeFromJson(json);

  @override
  bool operator ==(dynamic other) {
    // cannot use reflection, gets in the way of flutter's tree shaking
    if (other is! PaymentRequestEnvelope) {
      return false;
    }
    return _equalData(other);
  }

  Map<String, dynamic> toJson() => _$PaymentRequestEnvelopeToJson(this);

  bool verify(RSAPublicKey publicKey) {
    final helper = RsaKeyHelper();
    return helper.verify(signature, message, publicKey);
  }

  PaymentRequestMessage unpack() {
    return PaymentRequestMessage.fromJson(jsonDecode(this.message));
  }
}

@JsonSerializable()
class PaymentMessage extends BaseMessage {
  String crypto_currency;
  String transaction_hash;
  String version;

  PaymentMessage(
      {this.crypto_currency,
      this.transaction_hash,
      this.version = MANTA_VERSION});

  factory PaymentMessage.fromJson(Map<String, dynamic> json) =>
      _$PaymentMessageFromJson(json);

  @override
  bool operator ==(dynamic other) {
    // cannot use reflection, gets in the way of flutter's tree shaking
    if (other is! PaymentMessage) {
      return false;
    }
    return _equalData(other);
  }

  Map<String, dynamic> toJson() => _$PaymentMessageToJson(this);
}
