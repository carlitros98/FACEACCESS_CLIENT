import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:capacity_access_device/providers/AppState.dart';
import 'package:capacity_access_device/screens/FirstScreen.dart';
import 'package:capacity_access_device/themes/app_theme.dart';
import 'package:capacity_access_device/themes/theme_model.dart';
import 'package:qrscan/qrscan.dart' as scanner;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;
import 'package:restart_app/restart_app.dart';
import 'package:preferences/preferences.dart';
import 'package:provider/provider.dart';

import 'package:camera/camera.dart';
import 'package:google_ml_vision/google_ml_vision.dart';
import 'package:image/image.dart' as im2;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PrefService.init(prefix: 'pref_');
  runApp(ChangeNotifierProvider(
      create: (_) => ThemeModel(),
      child: Consumer<ThemeModel>(
          builder: (context, ThemeModel themeNotifier, child) {
        return MaterialApp(
          home: FirstScreen(
            title: '',
          ),
          theme: themeNotifier.isDark ? AppTheme.dark : AppTheme.light,
          debugShowCheckedModeBanner: false,
        );
      })));
}
