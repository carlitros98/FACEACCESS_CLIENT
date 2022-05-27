import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:capacity_access_device/providers/Utils.dart';
import 'package:capacity_access_device/screens/CameraSoftware.dart';
import 'package:capacity_access_device/themes/app_theme.dart';
import 'package:capacity_access_device/themes/theme_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:preferences/preferences.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:typed_data/typed_data.dart';
import 'package:provider/provider.dart';

import '../BBDD/classes/Cliente.dart';
import '../BBDD/logicaDB.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue/flutter_blue.dart';

class FirstScreen extends StatefulWidget {
  const FirstScreen({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<FirstScreen> createState() => _FirstScreen();
}

void showToast(String mensaje) {
  Fluttertoast.showToast(
      msg: mensaje,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      timeInSecForIos: 2,
      backgroundColor: Colors.black,
      textColor: Colors.white);
}

class _FirstScreen extends State<FirstScreen> with WidgetsBindingObserver {
  TextEditingController brokerController = new TextEditingController();

  late MqttClient subclient;

  BBDD db = BBDD();

  String topic_pub = "getDatabase";

  String topic_sub = "receiveDatabase";

  String sender = "";

  //late AppState currentAppState;

  String idclient = "";
  late final Permission _permission;
  PermissionStatus _permissionStatus = PermissionStatus.denied;

  bool camera_permiso = false;
  bool micro_permiso = false;

  FlutterBlue flutterBlue = FlutterBlue.instance;
  late BluetoothDevice disp;

  late List<BluetoothService> services;

  late BluetoothService servicio;
  late BluetoothCharacteristic car;
  bool establishBluetooth = false;

  @override
  void initState() {
    idclient = PrefService.getString("idCliente") ?? "0";

    if (idclient == "0") {
      PrefService.setString("idCliente", "0");
      Utils.id_actual = "0";
    } else {
      Utils.id_actual = idclient;
    }

    var r2 = Random();
    sender = (r2.nextDouble() * 2999).toString() + "_client";
    PrefService.setString("sender", sender);
    String broker = PrefService.getString("broker") ?? "";

    if (broker != "") {
      brokerController.text = broker;
    }
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    subclient.unsubscribe(topic_sub);
    subclient.disconnect();
  }

  Future<void> requestPermission() async {
    var cameraStatus = await Permission.camera.status;
    var microStatus = await Permission.microphone.status;
    if (!cameraStatus.isGranted) {
      await Permission.camera.request();
    }

    if (!microStatus.isGranted) {
      await Permission.microphone.request();
    }
    cameraStatus = await Permission.camera.status;
    microStatus = await Permission.microphone.status;
    camera_permiso = cameraStatus.isGranted;
    micro_permiso = microStatus.isGranted;
  }

  Future<int> pub(String topic, String message) async {
    var rng = Random();

    String mqttBroker = PrefService.getString("broker");
    final MqttClient client =
        MqttServerClient(mqttBroker, 'flutter' + rng.nextInt(100).toString());

    client.logging(on: false);
    client.keepAlivePeriod = 2;

    final MqttConnectMessage connMess = MqttConnectMessage()
        .withClientIdentifier(message)
        .keepAliveFor(2)
        .startClean();

    client.connectionMessage = connMess;

    try {
      await client.connect();
    } on Exception catch (e) {
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
          if (receiver == sender) {
            PrefService.setString('message', pt);
            PrefService.setString('receive', 'true');
            PrefService.setString('lock', 'false');
          }
        } on Exception {}
      });
    } else {
      client.disconnect();
    }

    return 0;
  }

  Future<void> getDatabase(BuildContext context) async {
    await db.initDB();
    showToast("Descargando la base de datos, espere unos segundos");
    PrefService.setString("lock", "true");
    PrefService.setString("receive", "false");
    PrefService.setString('message', '');

    idclient = PrefService.getString("idCliente") ?? "0";

    late BluetoothDevice cercano;
    int rssi = -10000;

    String sendable =
        "{\"function\" : \"getDatabase\", \"sender\" : \"$sender\", \"data\" : {\"id\" : \"$idclient\"}}";

    if (!establishBluetooth) {
      await flutterBlue.startScan(timeout: Duration(seconds: 2)).then((value) {
        flutterBlue.scanResults.listen((results) async {
          for (ScanResult r in results) {
            if (r.device.name == "DSD Relay") {
              await flutterBlue.stopScan();
              disp = r.device;
              print("PRESEND");

              disp.connect().then((value) {
                disp.discoverServices().then((value) {
                  value.forEach((service) {
                    if (service.uuid.toString() ==
                        "0000ffe0-0000-1000-8000-00805f9b34fb") {
                      servicio = service;
                      var characteristics = service.characteristics;

                      for (BluetoothCharacteristic c in characteristics) {
                        if (c.uuid.toString() ==
                            "0000ffe1-0000-1000-8000-00805f9b34fb") {
                          print("EXITAZO");
                          car = c;
                          establishBluetooth = true;
                          break;
                        }
                      }
                    }
                  });

                  pub(topic_pub, sendable);

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

                      if (function == "getDatabase" && receiver == sender) {
                        String status = json2['status'].toString();

                        if (status == "OK") {
                          List<dynamic> data = json2['data'];

                          if (json2['data'].toString() != "[]") {
                            List<Cliente> database = [];

                            int id_max = 0;

                            for (var client in data) {
                              Cliente c = Cliente.fromJson(client);

                              if (id_max < c.id) {
                                id_max = c.id;
                              }

                              database.add(c);
                            }

                            PrefService.setString(
                                "idCliente", id_max.toString());
                            Utils.id_actual = id_max.toString();

                            db.deleteAllClientes();

                            db.insertAllCliente(database);

                            Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(
                                    builder: (BuildContext context) =>
                                        CameraSoftware(
                                          title: '',
                                          car: car,
                                        )),
                                ModalRoute.withName('/'));

                            setState(() {});
                          } else {
                            Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(
                                    builder: (BuildContext context) =>
                                        CameraSoftware(
                                          title: '',
                                          car: car,
                                        )),
                                ModalRoute.withName('/'));
                          }
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

                  //
                });
              });
              break;
            }
          }
        });
      });
    } else {
      // si todo ok
      pub(topic_pub, sendable);

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

          if (function == "getDatabase" && receiver == sender) {
            String status = json2['status'].toString();

            if (status == "OK") {
              List<dynamic> data = json2['data'];

              if (json2['data'].toString() != "[]") {
                List<Cliente> database = [];

                int id_max = 0;

                for (var client in data) {
                  Cliente c = Cliente.fromJson(client);

                  if (id_max < c.id) {
                    id_max = c.id;
                  }

                  database.add(c);
                }

                PrefService.setString("idCliente", id_max.toString());
                Utils.id_actual = id_max.toString();

                db.deleteAllClientes();

                db.insertAllCliente(database);

                /*         Navigator.of(context)
            .push(
          MaterialPageRoute(
              builder: (BuildContext context) => ChangeNotifierProvider(
                  create: (_) => ThemeModel(),
                  child: Consumer<ThemeModel>(
                      builder: (context, ThemeModel themeNotifier, child) {
                    return MaterialApp(
                      home: const FirstScreen(
                        title: '',
                      ),
                      theme: AppTheme.dark,
                      debugShowCheckedModeBanner: false,
                    );
                  }))),
        )*/

                Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                        builder: (BuildContext context) => CameraSoftware(
                              title: '',
                              car: car,
                            )),
                    ModalRoute.withName('/'));

                setState(() {});
              } else {
                Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                        builder: (BuildContext context) => CameraSoftware(
                              title: '',
                              car: car,
                            )),
                    ModalRoute.withName('/'));
              }
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
  }

  bool compruebaIp(String ip) {
    try {
      final list1 = ip.split(".");

      if (list1.length == 4) {
        for (String byte in list1) {
          int nbyte = int.parse(byte);
          if (nbyte > 255 || nbyte < 0) {
            return false;
          }
        }

        return true;
      } else {
        return false;
      }
    } catch (Exception) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    var y = Random();
    return Consumer<ThemeModel>(
        builder: (context, ThemeModel themeNotifier, child) {
      requestPermission();

      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [],
        ),
        body: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: Container(
            width: size.width,
            height: size.height,
            padding: EdgeInsets.only(
                left: 20, right: 20, bottom: size.height * 0.2, top: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 40),
                        Image(
                            width: 190,
                            alignment: Alignment.center,
                            image: AssetImage('assets/images/LOGO3.png')),
                        SizedBox(width: 40),
                      ],
                    ),
                    SizedBox(
                      height: 120,
                    ),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                      decoration: BoxDecoration(
                          color: Theme.of(context).primaryColorLight,
                          borderRadius: BorderRadius.all(Radius.circular(20))),
                      child: TextField(
                        controller: brokerController,
                        decoration: InputDecoration(
                            border: InputBorder.none, hintText: "Broker"),
                      ),
                    ),
                    SizedBox(
                      height: 50,
                    ),
                    RaisedButton(
                      onPressed: () async {
                        if (brokerController.text.isNotEmpty) {
                          if (compruebaIp(brokerController.text)) {
                            if (camera_permiso && micro_permiso) {
                              flutterBlue.isOn.then((value) {
                                if (value) {
                                  subclient = MqttServerClient(
                                      brokerController.text,
                                      'flutter' + y.nextInt(100).toString());
                                  sub(subclient, topic_sub)
                                      .then((value) => getDatabase(context));
                                } else {
                                  showToast(
                                      'Primero debes activar el bluetooth');
                                  establishBluetooth = false;
                                }
                              });
                            } else {
                              showToast('No tienes los permisos suficientes');
                            }

                            PrefService.setString(
                                "broker", brokerController.text);
                            setState(() {});
                          } else {
                            showToast('Introducir una IP válida');
                          }
                        } else {
                          showToast('Introducir una IP');
                        }
                      },
                      elevation: 0,
                      padding: EdgeInsets.all(18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      child: Center(
                          child: Text(
                        "Acceder a la aplicación",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      )),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
