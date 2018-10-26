// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'messages.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MerchantOrderRequestMessage _$MerchantOrderRequestMessageFromJson(
    Map<String, dynamic> json) {
  return new MerchantOrderRequestMessage(
      amount: json['amount'] == null
          ? null
          : str_to_decimal(json['amount'] as String),
      session_id: json['session_id'] as String,
      fiat_currency: json['fiat_currency'] as String,
      crypto_currency: json['crypto_currency'] as String);
}

abstract class _$MerchantOrderRequestMessageSerializerMixin {
  Decimal get amount;
  String get session_id;
  String get fiat_currency;
  String get crypto_currency;
  Map<String, dynamic> toJson() => <String, dynamic>{
        'amount': amount == null ? null : decimal_to_str(amount),
        'session_id': session_id,
        'fiat_currency': fiat_currency,
        'crypto_currency': crypto_currency
      };
}

AckMessage _$AckMessageFromJson(Map<String, dynamic> json) {
  return new AckMessage(
      txid: json['txid'] as String,
      status: json['status'] as String,
      url: json['url'] as String,
      amount: json['amount'] == null
          ? null
          : str_to_decimal(json['amount'] as String),
      transaction_hash: json['transaction_hash'] as String,
      transaction_currency: json['transaction_currency'] as String,
      memo: json['memo'] as String);
}

abstract class _$AckMessageSerializerMixin {
  String get txid;
  String get status;
  String get url;
  Decimal get amount;
  String get transaction_hash;
  String get transaction_currency;
  String get memo;
  Map<String, dynamic> toJson() => <String, dynamic>{
        'txid': txid,
        'status': status,
        'url': url,
        'amount': amount == null ? null : decimal_to_str(amount),
        'transaction_hash': transaction_hash,
        'transaction_currency': transaction_currency,
        'memo': memo
      };
}
