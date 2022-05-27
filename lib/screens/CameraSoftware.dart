import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:capacity_access_device/BBDD/classes/Cliente.dart';
import 'package:capacity_access_device/BBDD/logicaDB.dart';
import 'package:capacity_access_device/providers/AppState.dart';
import 'package:capacity_access_device/providers/Utils.dart';
import 'package:capacity_access_device/screens/FaseReconocimiento.dart';
import 'package:capacity_access_device/screens/FirstScreen.dart';
import 'package:qrscan/qrscan.dart' as scanner;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;
import 'package:restart_app/restart_app.dart';
import 'package:preferences/preferences.dart';
import 'package:provider/provider.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:camera/camera.dart';
import 'package:google_ml_vision/google_ml_vision.dart';
import 'package:image/image.dart' as im2;
import 'package:typed_data/typed_data.dart';
import 'package:flutter_blue/flutter_blue.dart';

late CameraController _controller;
late Future<void> _initController;
var cameraReady = false;

class CameraSoftware extends StatefulWidget {
  final BluetoothCharacteristic car;

  const CameraSoftware({Key? key, required this.title, required this.car})
      : super(key: key);

  final String title;

  @override
  State<CameraSoftware> createState() => _CameraSoftware(bluetooth: car);
}

class _CameraSoftware extends State<CameraSoftware>
    with WidgetsBindingObserver {
  int changes = 0;
  int exec = 0;
  final FaceDetector faceDetector = GoogleVision.instance.faceDetector();
  late XFile imageFile;
  late MqttClient subclient;
  String topic_sub = "receiveClient";
  String sender = "";
  var r2 = math.Random();
  BBDD db = BBDD();
  final BluetoothCharacteristic bluetooth;

  _CameraSoftware({Key? key, required this.bluetooth});

  @override
  void initState() {
    super.initState();

    initCamera();
    sender = (r2.nextDouble() * 2999).toString() + "_client";
    print("1403 AAA");
    WidgetsBinding.instance?.addObserver(this);
  }

  void volcado() async {
    await db.initDB();
    db.getAllClientes().then((value) {
      print("volcado db:" + value.length.toString());
      //currentAppState.setFullCliente(value);
      Utils.insertAllCliente(value);
      print("prov:" + Utils.clientes.length.toString());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance?.removeObserver(this);
    //_controller?.dispose();
    subclient.unsubscribe(topic_sub);
    subclient.disconnect();
    faceDetector.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // TODO: implement didChangeAppLifecycleState
    // App state changed before we got the chance to initialize.

    if (state == AppLifecycleState.resumed) {
      _initController =
          (_controller != null ? _controller.initialize() : null)!;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      cameraReady = true;
    });
  }

  Widget cameraWidget(context) {
    var camera = _controller.value;
    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * camera.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return Transform.scale(
        scale: scale, child: Center(child: CameraPreview(_controller)));
  }

  Future<void> initCamera() async {
    final cameras = await availableCameras();
    final firstCamera = cameras[0];
    _controller = CameraController(firstCamera, ResolutionPreset.high);
    _initController = _controller.initialize();
    if (!mounted) return;

    setState(() {
      cameraReady = true;
    });
  }

  Future<void> changeCamera() async {
    final cameras = await availableCameras();
    changes++;

    final firstCamera = cameras[changes % 2];
    _controller = CameraController(firstCamera, ResolutionPreset.high);
    _initController = _controller.initialize();
    if (!mounted) return;

    setState(() {
      cameraReady = true;
    });
  }

  var interpreter;

  Future loadModel() async {
    try {
      interpreter = await tfl.Interpreter.fromAsset('facenet_hiroki.tflite');
    } on Exception {
      print('Failed to load model.');
    }
  }

  Float32List imageToByteListFloat32(
      im2.Image image, int inputSize, double mean, double std) {
    print("sf1");
    var convertedBytes = Float32List(1 * inputSize * inputSize * 3);
    print("sf2");

    print("inputSize:" + inputSize.toString());

    List<int> ops = [0, inputSize * inputSize];

    var buffer = Float32List.view(convertedBytes.buffer, 0);

    int pixelIndex = 0;

    for (var i = 0; i < inputSize; i++) {
      for (var j = 0; j < inputSize; j++) {
        var pixel = image.getPixel(j, i);

        buffer[pixelIndex++] = (im2.getRed(pixel) - mean) / std;

        buffer[pixelIndex++] = (im2.getGreen(pixel) - mean) / std;

        buffer[pixelIndex++] = (im2.getBlue(pixel) - mean) / std;
      }
    }
    return convertedBytes.buffer.asFloat32List();
  }

  List<List> dataset = [];

  double euclideanDistance(List e1, List e2) {
    double sum = 0.0;
    for (int i = 0; i < e1.length; i++) {
      sum += math.pow((e1[i] - e2[i]), 2);
    }
    return math.sqrt(sum);
  }

  String cercanos(List e1) {
    try {
      int i = 0;

      List<Cliente> lista = Utils.clientes;

      double umbral = 10.0;

      double best_distance = 100.0;
      String best_name = "";
      String best_cert = "";

      lista.forEach((element) {
        String puntos = element.puntos;

        double distance = 0.0;

        String ptos_2 = puntos.trim();
        String ptos_3 = puntos.substring(1, ptos_2.length - 1);
        List<String> list = ptos_3.split(",");
        var j = 0;

        List e_db = [];

        while (j < list.length) {
          e_db.add(double.parse(list[j]));
          j++;
        }

        distance = euclideanDistance(e_db, e1);

        if (best_distance > distance) {
          best_distance = distance;
          best_name = element.nombre;
          best_cert = element.certificate_id;
        }
      });

      if (best_distance <= umbral) {
        return best_name + "<" + best_cert + "<" + e1.toString();
      } else {
        return "None" + "<" + "None" + "<" + e1.toString();
      }
    } catch (Exception) {
      print("Error en el proceso");
    }

    return "";
  }

  String _recog(im2.Image img) {
    List input = imageToByteListFloat32(img, 160, 128, 128);

    input = input.reshape([1, 160, 160, 3]);

    List output = List.filled(1 * 128, null, growable: false).reshape([1, 128]);

    interpreter.run(input, output);

    output = output.reshape([128]);

    List puntos_foto = List.from(output);

    String resultado = cercanos(puntos_foto);

    return resultado;
  }

  Future<int> pub(String topic, String message) async {
    //mqtt broker 地址
    var rng = math.Random();

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
      print("Pre ok");

      await client.connect();
      print("todo ok");
    } on Exception catch (e) {
      print("Todo ko: " + e.toString());

      client.disconnect();
    }

    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      String topic_a = topic; // Not a wildcard topic
      client.subscribe(topic_a, MqttQos.atMostOnce);
      client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) async {
        try {
          final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
          final String pt =
              MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

          print("");
          print("Message received: " + pt);
          String newJson = '';
          newJson = pt.replaceAll("'", "\"");
          Map<String, dynamic> json2 = jsonDecode(newJson);
          print("sender ->" + sender);
          print("json" + json2.toString());
          String receiver = json2['receiver'].toString();
          String fun = json2['function'].toString();
          print("func:" + fun);
          if (fun != "updateClient") {
            if (receiver == sender) {
              PrefService.setString('message', pt);
              PrefService.setString('receive', 'true');
              PrefService.setString('lock', 'false');
            }

            if (fun == "forbiddenClient") {
              String message = json2['message'].toString();
              showToast(message);
              sleep(Duration(seconds: 1));
              Navigator.pop(context);
            }
          } else {
            String sender_aux = PrefService.getString("sender_aux") ?? "";
            if (receiver != sender_aux) {
              String status = json2['status'].toString();
              print("BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB");

              if (status == "OK" || status == "OKO") {
                print("Cliente nuevo");
                List<dynamic> data = json2['data'];
                int id_max = 0;
                var client = data[0];

                Cliente c = Cliente.fromJson(client);

                PrefService.setString("idCliente", c.id.toString());

                //currentAppState.setCliente(c);
                Utils.insertCliente(c);
                db.insertCliente(c);
                print("r:" + receiver + ", send:" + sender);

                print("Cliente insertado");
              }
            } else {
              print("CAUTION");
              String status = json2['status'].toString();
              String message = json2['message'].toString();

              if (status == "OK" || status == "OKO") {
                List<dynamic> data = json2['data'];
                var client = data[0];
                Cliente c = Cliente.fromJson(client);
                //PrefService.setString("idCliente", c.id.toString());

                int at = 0;

                for (Cliente n in Utils.clientes) {
                  if (n.id == c.id) {
                    at = 1;
                    n.puntos = c.puntos;
                    db.updatePoints(n);
                  }
                }

                if (at == 0) {
                  PrefService.setString("idCliente", c.id.toString());

                  //currentAppState.setCliente(c);
                  Utils.insertCliente(c);
                  db.insertCliente(c);
                }
              }

              if (status == "OK") {
                showToast("Acceso concedido");
                bluetooth.write([0xA0, 0x01, 0x01, 0xA2]);

                await Future.delayed(Duration(seconds: 5));

                bluetooth.write([0xA0, 0x01, 0x00, 0xA1]);
                Navigator.pop(context);
              } else {
                showToast("Cliente registrado, pero aforo lleno");
                sleep(Duration(seconds: 1));
                Navigator.pop(context);
              }
            }
          }
        } on Exception {}
      });
    } else {
      client.disconnect();
    }

    return 0;
  }

  void getImageDraw(im2.Image im, String path, BuildContext context) {
    final GoogleVisionImage visionImage =
        GoogleVisionImage.fromFile(File(path));
    final FaceDetector faceDetector = GoogleVision.instance.faceDetector();
    loadModel();

    faceDetector.processImage(visionImage).then((value) async {
      if (value.length == 1) {
        // solo se permite una cara
        Rect rect = value[0].boundingBox;

        double x, y, w, h;

        x = (rect.left - 10);
        y = (rect.top - 10);
        w = (rect.width + 10);
        h = (rect.height + 10);

        im2.Image croppedImage =
            im2.copyCrop(im, x.round(), y.round(), w.round(), h.round());

        croppedImage = im2.copyResizeCropSquare(croppedImage, 160);

        final x1 = rect.bottomLeft.dx.toInt();
        final x2 = rect.topRight.dx.toInt();
        final y1 = rect.bottomLeft.dy.toInt();
        final y2 = rect.topRight.dy.toInt();

        final nx0 = math.min(x1, x2);
        final ny0 = math.min(y1, y2);
        final nx1 = math.max(x1, x2);
        final ny1 = math.max(y1, y2);

        final color = 0xFF0099FF;

        im2.drawLine(im, nx0, ny0, nx1, ny0, color, thickness: 10);
        im2.drawLine(im, nx1, ny0, nx1, ny1, color, thickness: 10);
        im2.drawLine(im, nx0, ny1, nx1, ny1, color, thickness: 10);
        im2.drawLine(im, nx0, ny0, nx0, ny1, color, thickness: 10);

        final jpg = im2.encodeJpg(im);
        File aux = File(path);
        aux.writeAsBytes(jpg);

        String reconocimiento = _recog(croppedImage);
        print("1404: " + reconocimiento);
        String bytesFoto =
            base64.encode(im2.encodeJpg(croppedImage, quality: 100));

        print("bytes: " + bytesFoto);

        print("rr" + reconocimiento);
        List resultados = reconocimiento.split("<");

        String new_res = resultados[0] + "<" + resultados[1];
        String points = resultados[2];

        bool rec = false;

        print("1404: " + new_res + ", " + rec.toString());

        if (resultados[0] != "None") {
          rec = true;
        }

        await _controller.dispose();

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FaseReconocimiento(
                image: aux,
                existRec: rec,
                clientData: new_res,
                facePoints: points,
                cropBytes: bytesFoto,
                bluetooth: bluetooth),
          ),
        ).then((value) async {
          setState(() {});

          int v = 0;
          print("v: " + changes.toString());
          if (changes % 2 == 0) {
            v = 0;
          } else {
            v = 1;
          }

          final cameras = await availableCameras();
          final firstCamera = cameras[v];
          _controller = CameraController(firstCamera, ResolutionPreset.high);
          _initController = _controller.initialize();
        });
      }
    });
  }

  Future<List<Face>> getFaces(File t) async {
    final GoogleVisionImage visionImage = GoogleVisionImage.fromFile(t);
    final FaceDetector faceDetector = GoogleVision.instance.faceDetector();
    return await faceDetector.processImage(visionImage);
  }

  captureImage(BuildContext context) {
    _controller.takePicture().then((value) async {
      setState(() {
        imageFile = value;
      });

      if (mounted) {
        //Image foto = Image.file(File(imageFile.path), fit: BoxFit.fill);
        File photofile = File(imageFile.path);

        final bytes = await photofile.readAsBytes().then((value) {
          final im2.Image? imagen = im2.decodeImage(value);

          getImageDraw(imagen!, imageFile.path, context);
        });
      }
    });
  }

  Future<void> requestHelp() async {
    PrefService.setString("lock", "true");
    PrefService.setString("receive", "false");
    PrefService.setString('message', '');
    showToast(
        "Tu solicitud de ayuda ha sido enviada a los empleados del establecimiento");
    String sendable =
        "{\"function\" : \"helpClient\", \"sender\" : \"$sender\", \"data\" : \"\"}";

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
        print("msg : " + msg);
        PrefService.setString("receive", "false");
        String newJson = '';
        newJson = msg.replaceAll("'", "\"");
        Map<String, dynamic> json2 = jsonDecode(newJson);
        String function = json2['function'].toString();
        String receiver = json2['receiver'].toString();

        if (function == "helpClient" && receiver == sender) {
          String status = json2['status'].toString();

          if (status != "OK") {
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

  Future<bool> _onWillPop() async {
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (changes == 0) {
      //changes++;
      volcado();
    }
    String id = PrefService.getString("idCliente");
    String broker = PrefService.getString("broker");
    Utils.id_actual = id;
    var y = math.Random();
    subclient = MqttServerClient(broker, 'flutter' + y.nextInt(100).toString());

    sub(subclient, topic_sub);
    return new WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
          body: FutureBuilder(
        future: _initController,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                cameraWidget(context),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    color: Color(0xAA33363),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        SizedBox.fromSize(
                          size: Size(52, 52), // button width and height
                          child: ClipOval(
                            child: Material(
                              color: Colors.white, // button color
                              child: InkWell(
                                splashColor: Colors.white, // splash color
                                onTap: () {
                                  changeCamera();
                                }, // button pressed
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    Icon(
                                      Icons.cameraswitch_rounded,
                                      size: 35,
                                      color: Colors.black,
                                    ), // icon
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 65,
                        ),
                        SizedBox.fromSize(
                          size: Size(65, 65), // button width and height
                          child: ClipOval(
                            child: Material(
                              color: Colors.white, // button color
                              child: InkWell(
                                splashColor: Colors.white, // splash color
                                onTap: () {
                                  captureImage(context);
                                }, // button pressed
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    Icon(Icons.camera_alt,
                                        size: 40, color: Colors.black), // icon
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 65,
                        ),
                        SizedBox.fromSize(
                          size: Size(52, 52), // button width and height
                          child: ClipOval(
                            child: Material(
                              color: Colors.white, // button color
                              child: InkWell(
                                splashColor: Colors.white, // splash color
                                onTap: () {
                                  requestHelp();
                                }, // button pressed
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    Icon(Icons.help,
                                        size: 40, color: Colors.black), // icon
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              ],
            );
          } else {
            return Center(
              child: CircularProgressIndicator(),
            );
          }
        },
      )
          // This trailing comma makes auto-formatting nicer for build methods.
          ),
    );
  }
}
