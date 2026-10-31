import 'package:flutter/material.dart';

import 'home/ble_home_screen.dart';

void main() {
  runApp(
    MaterialApp(
      title: 'Heart Rate Sensor Sample',
      debugShowCheckedModeBanner: false,
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.system,
      home:  BleHomeScreen(),
      // home:  MyApp(),
    ),
  );
}
