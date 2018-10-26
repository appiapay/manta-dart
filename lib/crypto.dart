import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import "package:pointycastle/export.dart";
import "package:asn1lib/asn1lib.dart";

List<int> decodePEM(String pem) {
  var startsWith = [
    "-----BEGIN PUBLIC KEY-----",
    "-----BEGIN PRIVATE KEY-----",
    "-----BEGIN PGP PUBLIC KEY BLOCK-----\r\nVersion: React-Native-OpenPGP.js 0.1\r\nComment: http://openpgpjs.org\r\n\r\n",
    "-----BEGIN PGP PRIVATE KEY BLOCK-----\r\nVersion: React-Native-OpenPGP.js 0.1\r\nComment: http://openpgpjs.org\r\n\r\n",
  ];
  var endsWith = [
    "-----END PUBLIC KEY-----",
    "-----END PRIVATE KEY-----",
    "-----END PGP PUBLIC KEY BLOCK-----",
    "-----END PGP PRIVATE KEY BLOCK-----",
  ];
  bool isOpenPgp = pem.indexOf('BEGIN PGP') != -1;

  for (var s in startsWith) {
    if (pem.startsWith(s)) {
      pem = pem.substring(s.length);
    }
  }

  for (var s in endsWith) {
    if (pem.endsWith(s)) {
      pem = pem.substring(0, pem.length - s.length);
    }
  }

  if (isOpenPgp) {
    var index = pem.indexOf('\r\n');
    pem = pem.substring(0, index);
  }

  pem = pem.replaceAll('\n', '');
  pem = pem.replaceAll('\r', '');

  return base64.decode(pem);
}

class RsaKeyHelper {
  AsymmetricKeyPair<PublicKey, PrivateKey> generateKeyPair() {
    var keyParams = new RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 12);

    var secureRandom = new FortunaRandom();
    var random = new Random.secure();
    List<int> seeds = [];
    for (int i = 0; i < 32; i++) {
      seeds.add(random.nextInt(255));
    }
    secureRandom.seed(new KeyParameter(new Uint8List.fromList(seeds)));

    var rngParams = new ParametersWithRandom(keyParams, secureRandom);
    var k = new RSAKeyGenerator();
    k.init(rngParams);

    return k.generateKeyPair();
  }

  String encrypt(String plaintext, RSAPublicKey publicKey) {
    var cipher = new RSAEngine()
      ..init(true, new PublicKeyParameter<RSAPublicKey>(publicKey));
    var cipherText = cipher.process(new Uint8List.fromList(plaintext.codeUnits));

    return new String.fromCharCodes(cipherText);
  }

  String decrypt(String ciphertext, RSAPrivateKey privateKey) {
    var cipher = new RSAEngine()
      ..init(false, new PrivateKeyParameter<RSAPrivateKey>(privateKey));
    var decrypted = cipher.process(new Uint8List.fromList(ciphertext.codeUnits));

    return new String.fromCharCodes(decrypted);
  }

  String decrypt_from_b64(String b64text, RSAPrivateKey privatekey) {
    final msg = Base64Decoder().convert(b64text);
    final cipher = PKCS1Encoding(RSAEngine());
    cipher.init(false, PrivateKeyParameter<RSAPrivateKey>(privatekey));
    var decrypted = cipher.process(msg);
    return String.fromCharCodes(decrypted);
  }



  parsePublicKeyFromPem(pemString) {
    List<int> publicKeyDER = decodePEM(pemString);
    var asn1Parser = new ASN1Parser(publicKeyDER);
    var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    var publicKeyBitString = topLevelSeq.elements[1];

    var publicKeyAsn = new ASN1Parser(publicKeyBitString.contentBytes());
    ASN1Sequence publicKeySeq = publicKeyAsn.nextObject();
    var modulus = publicKeySeq.elements[0] as ASN1Integer;
    var exponent = publicKeySeq.elements[1] as ASN1Integer;

    RSAPublicKey rsaPublicKey = RSAPublicKey(
        modulus.valueAsBigInteger,
        exponent.valueAsBigInteger
    );

    return rsaPublicKey;
  }

  parsePrivateKeyFromPem(pemString) {
    List<int> privateKeyDER = decodePEM(pemString);
    var asn1Parser = new ASN1Parser(privateKeyDER);
    var topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    var version = topLevelSeq.elements[0];
    var algorithm = topLevelSeq.elements[1];
    var privateKey = topLevelSeq.elements[2];

    asn1Parser = new ASN1Parser(privateKey.contentBytes());
    var pkSeq = asn1Parser.nextObject() as ASN1Sequence;

    version = pkSeq.elements[0];
    var modulus = pkSeq.elements[1] as ASN1Integer;
    var publicExponent = pkSeq.elements[2] as ASN1Integer;
    var privateExponent = pkSeq.elements[3] as ASN1Integer;
    var p = pkSeq.elements[4] as ASN1Integer;
    var q = pkSeq.elements[5] as ASN1Integer;
    var exp1 = pkSeq.elements[6] as ASN1Integer;
    var exp2 = pkSeq.elements[7] as ASN1Integer;
    var co = pkSeq.elements[8] as ASN1Integer;

    RSAPrivateKey rsaPrivateKey = RSAPrivateKey(
        modulus.valueAsBigInteger,
        privateExponent.valueAsBigInteger,
        p.valueAsBigInteger,
        q.valueAsBigInteger
    );

    return rsaPrivateKey;
  }

  encodePublicKeyToPem(RSAPublicKey publicKey) {
    var algorithmSeq = new ASN1Sequence();
    var algorithmAsn1Obj = new ASN1Object.fromBytes(Uint8List.fromList([0x6, 0x9, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0xd, 0x1, 0x1, 0x1]));
    var paramsAsn1Obj = new ASN1Object.fromBytes(Uint8List.fromList([0x5, 0x0]));
    algorithmSeq.add(algorithmAsn1Obj);
    algorithmSeq.add(paramsAsn1Obj);

    var publicKeySeq = new ASN1Sequence();
    publicKeySeq.add(ASN1Integer(publicKey.modulus));
    publicKeySeq.add(ASN1Integer(publicKey.exponent));
    var publicKeySeqBitString = new ASN1BitString(Uint8List.fromList(publicKeySeq.encodedBytes));

    var topLevelSeq = new ASN1Sequence();
    topLevelSeq.add(algorithmSeq);
    topLevelSeq.add(publicKeySeqBitString);
    var dataBase64 = base64.encode(topLevelSeq.encodedBytes);

    return """-----BEGIN PUBLIC KEY-----\r\n$dataBase64\r\n-----END PUBLIC KEY-----""";
  }

  encodePrivateKeyToPem(RSAPrivateKey privateKey) {
    var version = ASN1Integer(BigInt.from(0));

    var algorithmSeq = new ASN1Sequence();
    var algorithmAsn1Obj = new ASN1Object.fromBytes(Uint8List.fromList([0x6, 0x9, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0xd, 0x1, 0x1, 0x1]));
    var paramsAsn1Obj = new ASN1Object.fromBytes(Uint8List.fromList([0x5, 0x0]));
    algorithmSeq.add(algorithmAsn1Obj);
    algorithmSeq.add(paramsAsn1Obj);

    var privateKeySeq = new ASN1Sequence();
    var modulus = ASN1Integer(privateKey.n);
    var publicExponent = ASN1Integer(BigInt.parse('65537'));
    var privateExponent = ASN1Integer(privateKey.d);
    var p = ASN1Integer(privateKey.p);
    var q = ASN1Integer(privateKey.q);
    var dP = privateKey.d % (privateKey.p - BigInt.from(1));
    var exp1 = ASN1Integer(dP);
    var dQ = privateKey.d % (privateKey.q - BigInt.from(1));
    var exp2 = ASN1Integer(dQ);
    var iQ = privateKey.q.modInverse(privateKey.p);
    var co = ASN1Integer(iQ);

    privateKeySeq.add(version);
    privateKeySeq.add(modulus);
    privateKeySeq.add(publicExponent);
    privateKeySeq.add(privateExponent);
    privateKeySeq.add(p);
    privateKeySeq.add(q);
    privateKeySeq.add(exp1);
    privateKeySeq.add(exp2);
    privateKeySeq.add(co);
    var publicKeySeqOctetString = new ASN1OctetString(Uint8List.fromList(privateKeySeq.encodedBytes));

    var topLevelSeq = new ASN1Sequence();
    topLevelSeq.add(version);
    topLevelSeq.add(algorithmSeq);
    topLevelSeq.add(publicKeySeqOctetString);
    var dataBase64 = base64.encode(topLevelSeq.encodedBytes);

    return """-----BEGIN PRIVATE KEY-----\r\n$dataBase64\r\n-----END PRIVATE KEY-----""";
  }
}
  void main() {
    final helper = RsaKeyHelper();
////    final keypair = helper.generateKeyPair();
////    print (helper.encodePublicKeyToPem(keypair.publicKey));
////    print (helper.encodePrivateKeyToPem(keypair.privateKey));

    final private = '''
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCksoyRf/i7j1+3pFY9+ylXTh+97LrEyieD0j2tOHL0+lQ4QAEgUjsMIuRXJUXzoArhhtaup0b9L6D6+ZqhKclKhX/+ef4Mrxb/2lYwLQpyolvT+Zu4K99aL6R7djCyRYSjluGnBw3gjkN4Y6RGvABFyAU4gFktliRm7buAbyx74WC45D04wRLxsgzbBaKgQTGxJnlpzdgtKXvpfU8P7wBPrHJN3+7sy3OZZJ5R7IBL2KQOfCsjOCblif5bSyrm9Ngq5Myvc3KXoaC661slVxlG3PjnBky0Q3hAneT+M9o3rdqYIIcksd4lvm4czagM6+Ijub5vuaBoiNTpmkfg6RuNAgMBAAECggEAesE18nCupKVtU0Qin5nnK1JoaDfc0TZXk3INVGGhlSRLx401CbEgn6AWDzoR1E7yLTxCIPU+/REV7FpEPWEWzfuI9dRZXXzXKKXE3a2EfwKybOE7hl7035RpBTiHfShBf2jDEao5VqjScxXZaHtRvLEj6wQG8+pXgXwp58V1I3MZCvXLN0pzWPWk51AEftAILP1SJDxOsSzSN8DnIj9T0IR6hpXTxR8zwJ8cGv4iJqOO0WIldrgl9ZBqvKTVDmDNYsmwG2HJpe1DmG++UuuCvPtUQBfUBYumg7yhSr2bA2VP/URNMvDFNBIVTvmckRpZRAJNIiy4ufy9kSyJ4nYzhQKBgQDo9QlaVfxqtxz+fryM+O2O5P0fYi77ZeOYGhwwpAFEVenboggFh5T5uXBk9SicwctmuN5M5rHoFxIxGCW3ZuNWMzXRFMrsbifJFU7LPpA4GMiv09P4o8n3We3yRZdSqJGD+E+52/lDoXEOhoudFafwyRp/lTS7y4XD//VqMytu5wKBgQC0/QiZ8BugMpxnjLC/61xXTuGtVInIuXCQaMtUoICilaHOidbBwPmdXI+vWWOKS0CI4Fz8tRul5p8AdxHXaoIdKW3oXq1h1tKpYIJWkCQkdEplY5yiHUuj9zSpgSSNTDmnWJtLqn6g5VBum1+b4IKTBaDOegkm1/FkGJCYEH0XawKBgQCl8xisj6B27ObsrJ/o1NN1/c4Lc0gAsr6E9eSrCcoVQhaL7UtFlSYdF2rnoHVD5hHdpUhHA/gsW3MMIiWMFvFP0L8/qE4+SuJwroso4fKe45jjGEViVFtlp1yIP+bibU7r8hHpVrik4vbE4DfIuUqfjsMfq8ybEwrBay8KblU8dQKBgFVP4LoPQDZnJOp6muYcX06YVDCL5NbE8pZfj1i4v2nj9n2Q47Y47HCMrP4OuKj7h9P9TlegVwQAjXp+pd5QyjxMxw39cuTnii1k3ItJLoAwgNEB/1c7T+heImi0AzLHd3W2gp1MJJxa+2rnuk2Tqnj68i3hwGaa66IvIhlLzGs5AoGBAIEu5a+kxi0q+fBRbSt3puo1Ot1VEgk9WIsJ374llwBln6q8MQDbDx8+dyDmWqf1I+xfgCVdQbsiDsnfZLKQGyvAyozEpbhnqg0pDUXO2lvNltIomT4xSKsgzzRcedWL3mN8296B6gRglHWvCJm94z9a419lNSAgYXXaW97PpFFg
-----END PRIVATE KEY-----''';

    final private_key = helper.parsePrivateKeyFromPem(private);

    final msg_b64 = 'mwn+unmKW//zB5p/qSwQsDA22xzMCZwerejolhodjXW4Zftq8NkvtJgrHnLKxWoE+VJn5ka9Sl2+zChp+T8qElwbQg01yt6KWjvq4d4aFsQyShvgTr3rygPGqMPD2+PDhjMnEHgfk8bvFrTRuNUpHfXom0kdL2fDFMBZ7USvOnPsnqJEo0esXPysXN4Nc0Roms9u12QNkWKP7GxCJ2/gieu7lNK1nv8hos3In2rk5jSOdYX5lUkVzmFhM+BIfBvKiph6qLX+WKKGZAa1aySKZDEL8mgHRw7Ju9U06TovnGNHWEEiZ1ywRqXRbVjwpe1kwZ8g23tiFLc7vHQ13zyvgg==';

    final decoded = helper.decrypt_from_b64(msg_b64, private_key);

    print (decoded);
    
}
