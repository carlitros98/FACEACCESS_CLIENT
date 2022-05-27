import 'dart:convert';
import 'dart:io';
import 'package:capacity_access_device/BBDD/classes/Cliente.dart';
import 'package:typed_data/typed_data.dart';
import 'package:capacity_access_device/BBDD/logicaDB.dart';
import 'package:capacity_access_device/COVID/dgc_v1.dart';
import 'package:capacity_access_device/COVID/hc1.dart';
import 'package:capacity_access_device/COVID/names.dart';
import 'package:capacity_access_device/COVID/v.dart';
import 'package:capacity_access_device/providers/AppState.dart';
import 'package:capacity_access_device/providers/Utils.dart';
import 'package:capacity_access_device/screens/FirstScreen.dart';
import 'package:flutter/material.dart';
import 'package:qrscan/qrscan.dart' as scanner;
import 'package:provider/provider.dart';
import 'package:dart_base45/dart_base45.dart';
import 'package:dart_cose/dart_cose.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'package:preferences/preferences.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:flutter_blue/flutter_blue.dart';

class FaseReconocimiento extends StatefulWidget {
  var image;
  var existRec;
  var clientData;
  var facePoints;
  var cropBytes;
  final BluetoothCharacteristic bluetooth;

  FaseReconocimiento(
      {Key? key,
      required this.image,
      required this.existRec,
      required this.clientData,
      required this.facePoints,
      required this.cropBytes,
      required this.bluetooth})
      : super(key: key);

  @override
  State<StatefulWidget> createState() {
    print("bytes1" + cropBytes);
    return FaseReconocimientoState(
        image: this.image,
        existRec: this.existRec,
        clientData: this.clientData,
        facePoints: this.facePoints,
        cropBytes: this.cropBytes,
        bluetooth: this.bluetooth);
  }
}

class FaseReconocimientoState extends State<FaseReconocimiento> {
  final File image;
  final bool existRec;
  final String clientData;
  final String cropBytes;
  String name_client = "";
  String cert_client = "";
  String facePoints = "";
  String broker = PrefService.getString("broker");

  String cropBytesAux = "";
  final BluetoothCharacteristic bluetooth;

  String _barcode = "";
  FaseReconocimientoState(
      {Key? key,
      required this.image,
      required this.existRec,
      required this.clientData,
      required this.facePoints,
      required this.cropBytes,
      required this.bluetooth});

  bool register = true;
  bool acceso = true;
  BBDD db = BBDD();

  late MqttClient subclient;
  String topic_sub = "receiveClient";
  String sender = "";
  var r2 = math.Random();

  String messageClient = "";

  @override
  void initState() {
    print("bytes2" + cropBytes);
    cropBytesAux = cropBytes;
    sender = (r2.nextDouble() * 2999).toString() + "_client";
    PrefService.setString("sender_aux", sender);
    if (!existRec) {
      messageClient =
          'Este usuario no está registrado en el sistema - requiere de QR';
    } else {
      final lista = clientData.split("<");
      name_client = lista[0];
      cert_client = lista[1];
      messageClient = 'Bienvenido ' + name_client + " [" + cert_client + "]";
    }
    iniciarBBDD();
    super.initState();
  }

  @override
  Future<void> iniciarBBDD() async {
    await db.initDB();
  }

  @override
  void dispose() async {
    super.dispose();
    subclient.unsubscribe(topic_sub);
    subclient.disconnect();
  }

  Future<int> pub(String topic, String message) async {
    var rng = math.Random();

    String mqttBroker = PrefService.getString("broker");
    final MqttClient client =
        MqttServerClient(mqttBroker, 'flutter' + rng.nextInt(100).toString());

    client.logging(on: false);
    client.keepAlivePeriod = 2;

    final MqttConnectMessage connMess = MqttConnectMessage()
        .withClientIdentifier(message.substring(1, 12))
        .keepAliveFor(2)
        .startClean();

    client.connectionMessage = connMess;

    try {
      await client.connect();
    } on Exception catch (e) {
      print("error conexion " + e.toString());
      client.disconnect();
    }

    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      String pubTopic = topic;
      final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder();
      builder.addString(message);
      Uint8Buffer? send = builder.payload;
      client.publishMessage(pubTopic, MqttQos.exactlyOnce, send!);
    } else {
      client.disconnect();
    }

    await MqttUtilities.asyncSleep(10);

    return 0;
  }

  Future<int> sub(MqttClient client, String topic) async {
    await db.initDB();

    client.logging(on: false);
    client.keepAlivePeriod = 2;

    final MqttConnectMessage connMess = MqttConnectMessage()
        .withClientIdentifier("sub" + topic.toString())
        .keepAliveFor(2)
        .startClean();

    client.connectionMessage = connMess;

    try {
      await client.connect();
    } on Exception catch (e) {
      client.disconnect();
    }

    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      String topic_a = topic; // Not a wildcard topic
      client.subscribe(topic_a, MqttQos.atMostOnce);
      client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        try {
          final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
          final String pt =
              MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

          String newJson = '';
          newJson = pt.replaceAll("'", "\"");
          Map<String, dynamic> json2 = jsonDecode(newJson);
          String receiver = json2['receiver'].toString();

          String fun = json2['function'].toString();
          if (fun != "updateClient") {
            if (receiver == sender) {
              PrefService.setString('message', pt);
              PrefService.setString('receive', 'true');
              PrefService.setString('lock', 'false');
            }
          }
        } on Exception {}
      });
    } else {
      client.disconnect();
    }

    return 0;
  }

  Future<void> registerClient(BuildContext context, String name, String surname,
      String cert, String fecha, String ptos) async {
    await db.initDB();
    showToast("Registrando cliente y enviando la solicitud de entrada");
    PrefService.setString("lock", "true");
    PrefService.setString("receive", "false");
    PrefService.setString('message', '');
    print("bytesaux: " + cropBytesAux);
    String sendable =
        "{\"function\" : \"registerClient\", \"sender\" : \"$sender\", \"data\" : {\"certificate_id\" : \"$cert\", \"nombre\" : \"$name\", \"apellidos\" : \"$surname\",  \"fecha\" : \"$fecha\", \"puntos\" : \"$ptos\", \"photo\" : \"$cropBytesAux\" }}";

    pub("getClient", sendable);
  }

  Future<void> solicitarAcceso(BuildContext context) async {
    await db.initDB();
    showToast("Enviando la solicitud de entrada");
    PrefService.setString("lock", "true");
    PrefService.setString("receive", "false");
    PrefService.setString('message', '');

    String sendable =
        "{\"function\" : \"requestAccess\", \"sender\" : \"$sender\", \"data\" : {\"certificate_id\" : \"$cert_client\"}}";

    pub("getClient", sendable);

    String n = PrefService.getString("lock");
    int p = 0;
    Future.doWhile(() async {
      await Future.delayed(Duration(milliseconds: 500));

      bool ok = true;
      String n = PrefService.getString("lock");

      if (n != "true" || p == 20) {
        PrefService.setString("lock", "true");
        ok = false;
      }
      p++;

      return ok;
    }).then((value) async {
      sleep(Duration(milliseconds: 500));

      String p = PrefService.getString("receive");

      if (p == "true") {
        String msg = PrefService.getString('message');
        PrefService.setString("receive", "false");
        String newJson = '';
        newJson = msg.replaceAll("'", "\"");
        Map<String, dynamic> json2 = jsonDecode(newJson);
        String function = json2['function'].toString();
        String receiver = json2['receiver'].toString();

        if (function == "requestAccess" && receiver == sender) {
          String status = json2['status'].toString();

          if (status == "OK") {
            showToast("Acceso concedido");

            bluetooth.write([0xA0, 0x01, 0x01, 0xA2]);

            await Future.delayed(Duration(seconds: 5));

            bluetooth.write([0xA0, 0x01, 0x00, 0xA1]);

            Navigator.pop(context);
          } else {
            showToast(json2['message'].toString());
          }
        } else {
          showToast("Error en el proceso");
        }
      } else {
        showToast("Error de comunicación por tópico");
      }
      PrefService.setString('message', '');
    });
  }

  @override
  @override
  Widget build(BuildContext context) {
    String result = "";

    var y = math.Random();

    String broker = PrefService.getString("broker");
    subclient = MqttServerClient(broker, 'flutter' + y.nextInt(100).toString());
    sub(subclient, topic_sub);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          InkWell(
            onTap: () {},
            child: Image.file(
              image,
              fit: BoxFit.fill,
              height: double.infinity,
              width: double.infinity,
            ),
          ),
          Positioned(
            bottom: 110,
            width: MediaQuery.of(context).size.width,
            child: Container(
              width: 240.0,
              height: 42.0,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24.0),
                  color: const Color(0xff2c2c2c).withOpacity(0.7)),
              child: Center(
                child: Text(
                  messageClient,
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontSize: 15,
                    color: Colors.white,
                    height: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 30,
            width: MediaQuery.of(context).size.width,
            child: Center(
              child: Visibility(
                child: RaisedButton(
                  onPressed: () async {
                    String v = await scanner.scan().then((value) {
                      try {
                        if (value.substring(0, 4) == "HC1:") {
                          var base45_decoded =
                              Base45.decode(value.substring(4));

                          var inflated = zlib.decode(base45_decoded);

                          final result = Cose.decodeAndVerify(
                            inflated,
                            {'kid': '''pem'''},
                          );
                          Hc1 certmodel = Hc1.fromMap(result.payload);

                          DgcV1 dgc = certmodel.certificate!;

                          Names names = dgc.names!;

                          V v = dgc.v!;

                          String validTo = DateFormat('dd-MM-yyyy')
                              .format(DateTime.fromMillisecondsSinceEpoch(
                                  (certmodel.expirationTime ?? 0) * 1000))
                              .toString();

                          String? birthday = dgc.dateOfBirth;
                          final names_sep = names.givenNameT!.split('<');
                          final ap_sep = names.familyNameT!.split('<');

                          String nombre_completo = "";
                          int i = 0;
                          for (String name in names_sep) {
                            if (i == 0) {
                              nombre_completo = name;
                            } else {
                              nombre_completo = nombre_completo + " " + name;
                            }
                            i++;
                          }

                          String apellido_completo = "";

                          String cert_id = v.ci!;
                          int j = 0;

                          for (String apellido in ap_sep) {
                            if (i == 0) {
                              apellido_completo = apellido;
                            } else {
                              apellido_completo =
                                  apellido_completo + " " + apellido;
                            }
                            i++;
                          }

                          DateTime validez =
                              new DateFormat("dd-MM-yyyy").parse(validTo);

                          int posix_now =
                              DateTime.now().toUtc().millisecondsSinceEpoch;

                          int posix_valido =
                              validez.toUtc().millisecondsSinceEpoch;

                          if (posix_now < posix_valido) {
                            showToast("Certificado COVID válido");
                            registerClient(
                                context,
                                nombre_completo,
                                apellido_completo,
                                cert_id,
                                birthday!,
                                facePoints);
                          } else {
                            showToast("Certificado COVID expirado");
                          }
                        } else if (value.substring(0, 4) == "FCP:") {
                          showToast(
                              "Certificado COVID válido - formato auxiliar");

                          String decoded =
                              utf8.decode(base64.decode(value.substring(4)));

                          print("Valor;" + decoded.toString());

                          String newJson = '';
                          newJson = decoded.replaceAll("'", "\"");
                          Map<String, dynamic> json2 = jsonDecode(newJson);

                          var fecha_aux = json2['date'].toString().split("/");

                          var day = fecha_aux[0].toString();
                          var month = fecha_aux[1].toString();
                          var year = fecha_aux[2].toString();

                          String res_date = year + "/" + month + "/" + day;

                          registerClient(
                              context,
                              json2['nombre'].toString(),
                              json2['apellido'].toString(),
                              json2['id_cert'].toString(),
                              res_date,
                              facePoints);
                        } else {
                          showToast("Formato incorrecto");
                        }
                      } catch (Exception) {
                        showToast("Formato incorrecto");
                      }

                      return "";
                    });
                  },
                  elevation: 0,
                  padding: EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  child: Center(
                      child: Text(
                    "Registrar reconocimiento",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  )),
                ),
                visible: !existRec,
              ),
            ),
          ),
          Positioned(
            bottom: 30,
            width: MediaQuery.of(context).size.width,
            child: Center(
              child: Visibility(
                child: RaisedButton(
                  onPressed: () {
                    solicitarAcceso(context);
                  },
                  elevation: 0,
                  padding: EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  child: Center(
                      child: Text(
                    "Acceder/salir del establecimiento",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  )),
                ),
                visible: existRec,
              ),
            ),
          )
        ],
      ),
    );
  }
}
