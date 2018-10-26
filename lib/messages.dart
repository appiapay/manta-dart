import 'package:decimal/decimal.dart';
import 'package:json_annotation/json_annotation.dart';

part 'messages.g.dart';

Decimal str_to_decimal(String value) => Decimal.parse(value);

String decimal_to_str(Decimal value) => value.toString();

@JsonSerializable()
class MerchantOrderRequestMessage extends Object
    with _$MerchantOrderRequestMessageSerializerMixin {
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
class AckMessage extends Object with _$AckMessageSerializerMixin {
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

  factory AckMessage.fromJson(Map<String, dynamic> json) => _$AckMessageFromJson(json);
}
