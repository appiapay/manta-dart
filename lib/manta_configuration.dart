import 'package:meta/meta.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:logging/logging.dart';
import 'dart:io';
import 'dart:convert';
import 'package:pointycastle/pointycastle.dart';
import 'crypto.dart';

final Logger logger = new Logger('MantaConfiguration');

const RECONNECT_INTERVAL = 3;

class MantaConfiguration {
  final String device_id;
  final PrivateKey rsaPrivate;
  final PublicKey rsaPublic;
  final RsaKeyHelper helper;

  MqttClient client;
  Map<String, dynamic> configuration;

  void Function(Map<String, dynamic>) configuration_callback;

  MantaConfiguration(
      {@required this.device_id,
      @required this.rsaPrivate,
      @required this.rsaPublic,
      String host = "localhost",
      MqttClient mqtt_client = null,
      this.configuration_callback}) : helper = RsaKeyHelper()
  {
    client = (mqtt_client == null) ? MqttClient(host, device_id) : mqtt_client;
    client.keepAlivePeriod = 20;
    client.onDisconnected = onDisconnected;
  }

  void reconnect() async {
    logger.info('Waiting $RECONNECT_INTERVAL seconds');
    sleep(Duration(seconds: RECONNECT_INTERVAL));
    logger.info('Reconnecting');
    await connect();
  }

  void onDisconnected() {
    logger.info("Client disconnection");
    reconnect();
  }

  Map<String, dynamic> decode_configuration(String message) {
    configuration = json.decode(message);

    if (configuration['application_token'] != "") {
      configuration['application_token'] = helper.decrypt_from_b64(
        configuration['application_token'], rsaPrivate);
    }

    return configuration;
  }

  Future<bool> waitForConnection() async {
    if (client.connectionStatus.state == MqttConnectionState.connected) {
      return true;
    }
    if (client.connectionStatus.state == MqttConnectionState.connecting) {
      while (client.connectionStatus.state != MqttConnectionState.connected) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      return true;
    }
    return false;
  }

  void connect() async {

    try {
      await client.connect();
      logger.info('Connected');
    } catch (e) {
      logger.warning("Client exception - $e");
      await reconnect();
    }

    client.subscribe("configure/$device_id/configuration", MqttQos.atLeastOnce);

    client.updates.listen((List<MqttReceivedMessage> c) {
      logger.info('Received new configuration');

      final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
      final String pt =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      logger.info(pt);

      configuration = decode_configuration(pt);

      if (configuration_callback != null) {
        configuration_callback(configuration);
      }
    });
  }

  void link(String link_code) async {
    await waitForConnection();

    final MqttClientPayloadBuilder builder = new MqttClientPayloadBuilder();
    builder.addString(helper.encodePublicKeyToPem(rsaPublic));

    client.publishMessage("configure/$device_id/link/$link_code",
        MqttQos.atLeastOnce, builder.payload);

    logger.info('Published key');
  }

  void test_crypto() async {
    await connect();
    final helper = RsaKeyHelper();
    final MqttClientPayloadBuilder builder = new MqttClientPayloadBuilder();
    builder.addString(helper.encodePublicKeyToPem(rsaPublic));
    client.publishMessage("test/",
        MqttQos.atLeastOnce, builder.payload);
  }
}

void main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord rec) {
    print('${rec.level.name}: ${rec.time}: ${rec.message}');
  });

  final private = '''
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCksoyRf/i7j1+3pFY9+ylXTh+97LrEyieD0j2tOHL0+lQ4QAEgUjsMIuRXJUXzoArhhtaup0b9L6D6+ZqhKclKhX/+ef4Mrxb/2lYwLQpyolvT+Zu4K99aL6R7djCyRYSjluGnBw3gjkN4Y6RGvABFyAU4gFktliRm7buAbyx74WC45D04wRLxsgzbBaKgQTGxJnlpzdgtKXvpfU8P7wBPrHJN3+7sy3OZZJ5R7IBL2KQOfCsjOCblif5bSyrm9Ngq5Myvc3KXoaC661slVxlG3PjnBky0Q3hAneT+M9o3rdqYIIcksd4lvm4czagM6+Ijub5vuaBoiNTpmkfg6RuNAgMBAAECggEAesE18nCupKVtU0Qin5nnK1JoaDfc0TZXk3INVGGhlSRLx401CbEgn6AWDzoR1E7yLTxCIPU+/REV7FpEPWEWzfuI9dRZXXzXKKXE3a2EfwKybOE7hl7035RpBTiHfShBf2jDEao5VqjScxXZaHtRvLEj6wQG8+pXgXwp58V1I3MZCvXLN0pzWPWk51AEftAILP1SJDxOsSzSN8DnIj9T0IR6hpXTxR8zwJ8cGv4iJqOO0WIldrgl9ZBqvKTVDmDNYsmwG2HJpe1DmG++UuuCvPtUQBfUBYumg7yhSr2bA2VP/URNMvDFNBIVTvmckRpZRAJNIiy4ufy9kSyJ4nYzhQKBgQDo9QlaVfxqtxz+fryM+O2O5P0fYi77ZeOYGhwwpAFEVenboggFh5T5uXBk9SicwctmuN5M5rHoFxIxGCW3ZuNWMzXRFMrsbifJFU7LPpA4GMiv09P4o8n3We3yRZdSqJGD+E+52/lDoXEOhoudFafwyRp/lTS7y4XD//VqMytu5wKBgQC0/QiZ8BugMpxnjLC/61xXTuGtVInIuXCQaMtUoICilaHOidbBwPmdXI+vWWOKS0CI4Fz8tRul5p8AdxHXaoIdKW3oXq1h1tKpYIJWkCQkdEplY5yiHUuj9zSpgSSNTDmnWJtLqn6g5VBum1+b4IKTBaDOegkm1/FkGJCYEH0XawKBgQCl8xisj6B27ObsrJ/o1NN1/c4Lc0gAsr6E9eSrCcoVQhaL7UtFlSYdF2rnoHVD5hHdpUhHA/gsW3MMIiWMFvFP0L8/qE4+SuJwroso4fKe45jjGEViVFtlp1yIP+bibU7r8hHpVrik4vbE4DfIuUqfjsMfq8ybEwrBay8KblU8dQKBgFVP4LoPQDZnJOp6muYcX06YVDCL5NbE8pZfj1i4v2nj9n2Q47Y47HCMrP4OuKj7h9P9TlegVwQAjXp+pd5QyjxMxw39cuTnii1k3ItJLoAwgNEB/1c7T+heImi0AzLHd3W2gp1MJJxa+2rnuk2Tqnj68i3hwGaa66IvIhlLzGs5AoGBAIEu5a+kxi0q+fBRbSt3puo1Ot1VEgk9WIsJ374llwBln6q8MQDbDx8+dyDmWqf1I+xfgCVdQbsiDsnfZLKQGyvAyozEpbhnqg0pDUXO2lvNltIomT4xSKsgzzRcedWL3mN8296B6gRglHWvCJm94z9a419lNSAgYXXaW97PpFFg
-----END PRIVATE KEY-----''';

  final public = '''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEApLKMkX/4u49ft6RWPfspV04fvey6xMong9I9rThy9PpUOEABIFI7DCLkVyVF86AK4YbWrqdG/S+g+vmaoSnJSoV//nn+DK8W/9pWMC0KcqJb0/mbuCvfWi+ke3YwskWEo5bhpwcN4I5DeGOkRrwARcgFOIBZLZYkZu27gG8se+FguOQ9OMES8bIM2wWioEExsSZ5ac3YLSl76X1PD+8AT6xyTd/u7MtzmWSeUeyAS9ikDnwrIzgm5Yn+W0sq5vTYKuTMr3Nyl6GguutbJVcZRtz45wZMtEN4QJ3k/jPaN63amCCHJLHeJb5uHM2oDOviI7m+b7mgaIjU6ZpH4OkbjQIDAQAB
-----END PUBLIC KEY-----''';

  final helper = RsaKeyHelper();

  final store = MantaConfiguration(
      device_id: 'test3',
      rsaPrivate: helper.parsePrivateKeyFromPem(private),
      rsaPublic: helper.parsePublicKeyFromPem(public),
      host: 'localhost',
      configuration_callback: (configuration) =>
          print("Here it is $configuration"));
  await store.link('7777');
}
