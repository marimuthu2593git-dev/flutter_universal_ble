import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:convert/convert.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_universal_ble_poc_sample/home/widgets/scan_filter_widget.dart';
import 'package:flutter_universal_ble_poc_sample/home/widgets/scanned_item_widget_new.dart';
import 'package:pdf/pdf.dart';

import 'package:universal_ble/universal_ble.dart';

import '../ble_constants.dart';
import '../permission_handler.dart';
import '../widgets/pagination_widget.dart';
import '../widgets/platform_button.dart';
import '../widgets/responsive_buttons_grid.dart';
import 'heartratesample.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'dart:math' as math;

class BleHomeScreen extends StatefulWidget {
  const BleHomeScreen({Key? key}) : super(key: key);

  @override
  State createState() => _BleHomeScreenState();
}

class _BleHomeScreenState extends State<BleHomeScreen> {
  final _bleDevices = <BleDevice>[];
  bool _isScanning = false;

  // QueueType _queueType = QueueType.global;
  QueueType _queueType = QueueType.global;
  TextEditingController servicesFilterController = TextEditingController();
  TextEditingController namePrefixController = TextEditingController();
  TextEditingController manufacturerDataController = TextEditingController();

  AvailabilityState? bleAvailabilityState;
  ScanFilter? scanFilter;
  Set<String> scannedDeviceIds = {};

  List<ScannedItemWidgetNew> scannedItems = [];

  bool isHeartRateSensor = true;

  Timer? _heartRateWriteTimer;

  List<HeartRateSample> heartRateLog = [];
  List<int> _currentWindowValues = [];

  Timer? _peakRecordTimer;
  DateTime? _startTime;
  int _intervalCount = 0;
  int heartRate = 0;
  int battery = 0;

  int currentPage =0;

  // final int totalRecordingDurationInSeconds = 120; // 2 minutes

  // final int totalRecordingDurationInSeconds = 300;
  final int totalRecordingDurationInSeconds =
      Duration(minutes: 60).inSeconds; // returns 600

  final int intervalDurationInSeconds = 30;
  late final int maxIntervals =
      totalRecordingDurationInSeconds ~/ intervalDurationInSeconds;
  Map<int, int> _perSecondHeartRates = {}; // key: elapsedSec, value: heart rate

// Global variables
//   Map<String, int> hrPerSecondMap = {}; // e.g., {'14:25': 78}
  Map<DateTime, int> hrPerSecondMap = {};

  DateTime? startTime;
  Timer? peakRecordTimer;
  int intervalCount = 0;

  int intervalInSeconds = 30;

  late List<HeartRateSample> _peakDataFuture;

  double rMSSD= 0.0;

  void stopPeakRecording() {
    _peakRecordTimer?.cancel();
    _peakRecordTimer = null;
  }

  Future<List<HeartRateSample>> loadPeakDataFromAssets() async {
    final jsonString =
        await rootBundle.loadString('assets/data/heartrate_values.json');
    final List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList.map((e) => HeartRateSample.fromJson(e)).toList();
  }

  @override
  void initState() {
    super.initState();
    initScanFilter();

    // UniversalBle.timeout = const Duration(seconds: 10);
    UniversalBle.queueType = _queueType;
    // servicesFilterController.text = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
    // namePrefixController.text = "BLUE,YELLOW";
    servicesFilterController.text = "6e40fff0-b5a3-f393-e0a9-e50e24dcca9e";
    // namePrefixController.text = "H59_F002";
    namePrefixController.text = "H59_";

    /// Set mock instance for testing
    // if (const bool.fromEnvironment('MOCK')) {
    //   UniversalBle.setInstance(MockUniversalBle());
    // }

    /// Setup queue and timeout
    // UniversalBle.queueType = _queueType;
    // UniversalBle.timeout = const Duration(seconds: 60);
    UniversalBle.timeout = null;
    UniversalBle.onAvailabilityChange = (state) {
      setState(() {
        bleAvailabilityState = state;
      });
    };

    UniversalBle.onScanResult = (result) {
      // debugPrint("Scan result  === ${result.deviceId} --- ${result.name}");
      int index = _bleDevices.indexWhere((e) => e.deviceId == result.deviceId);
      final GlobalKey<ScannedItemWidgetNewState> key =
          GlobalKey<ScannedItemWidgetNewState>();

      if (!scannedDeviceIds.contains(result.deviceId)) {
        scannedDeviceIds.add(result.deviceId); // Track unique devices
        _bleDevices.add(result); // Add only unique devices

        print("✅ New Device Found: ${result.deviceId} --- ${result.name}");
        // Update UI only when new device is found
      }
      if (_bleDevices.isNotEmpty) {
        if (!scannedItems
            .any((item) => item.bleDevice.deviceId == result.deviceId)) {
          setState(() {
            scannedItems.add(
              ScannedItemWidgetNew(
                isHeartRateSensor: isHeartRateSensor,
                key: GlobalKey<ScannedItemWidgetNewState>(),
                bleDevice: result,
                onTap: () {
                  print("Clicked on ${result.deviceId}");
                },
              ),
            );
          });
        }
      }
      ;
    };

    UniversalBle.onConnectionChange = _handleConnectionChange;
  }

  @override
  void dispose() {
    stopHeartRateWriteLoop();
    stopPeakRecording();
    super.dispose();
  }

  Future<void> disconnectAllDevices() async {
    for (var item in scannedItems) {
      try {
        String deviceId = item.bleDevice.deviceId;
        print("🔌 Disconnecting from $deviceId...");
        await UniversalBle.disconnect(deviceId);
        print("❌ Disconnected from $deviceId");
      } catch (e) {
        print("❌ Failed to disconnect: $e");
      }
    }
  }

  Future<void> startScan() async {
    // _bleDevices.clear();
    initScanFilter();
    await UniversalBle.startScan(
      scanFilter: scanFilter,
    );
    Duration scanTimeout = Duration(seconds: 30); // Set timeout duration

    Future.delayed(scanTimeout, () async {
      await UniversalBle.stopScan();

      print("⏳ Scan stopped after ${scanTimeout.inSeconds} seconds.");
      setState(() {
        _isScanning = false;
      });
    });
  }

  Future<void> exportChartToPdf(GlobalKey chartKey) async {
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      final context = chartKey.currentContext;

      if (context == null) {
        print("❌ chartKey context is null. Make sure the widget is visible.");
        return;
      }

      final renderObject = context.findRenderObject();
      if (renderObject == null || renderObject is! RenderRepaintBoundary) {
        print("❌ Render object is null or not a RenderRepaintBoundary.");
        return;
      }

      final boundary = renderObject as RenderRepaintBoundary;
      final ui.Image chartImage = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData =
          await chartImage.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        print("❌ Failed to convert image to byte data.");
        return;
      }

      final Uint8List imageBytes = byteData.buffer.asUint8List();

      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  "📊 Heart Rate Peak Chart",
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 20),
                pw.Center(
                  child: pw.Image(pw.MemoryImage(imageBytes)),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  "📌 Note: This chart visualizes the heart rate peaks captured during the session.",
                  style: pw.TextStyle(fontSize: 12),
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
      );

      print("✅ Chart exported to PDF successfully.");
    } catch (e, stack) {
      print("❌ Exception during chart export: $e");
      print(stack);
    }
  }

  Future<void> exportChartToPdf1(GlobalKey chartKey) async {
    try {
      // Ensure the widget is rendered
      await Future.delayed(const Duration(milliseconds: 100));
      final context = chartKey.currentContext;

      if (context == null) {
        print("❌ chartKey context is null. Make sure the widget is visible.");
        return;
      }

      final renderObject = context.findRenderObject();
      if (renderObject == null || renderObject is! RenderRepaintBoundary) {
        print("❌ Render object is null or not a RenderRepaintBoundary.");
        return;
      }

      final boundary = renderObject as RenderRepaintBoundary;
      final ui.Image chartImage = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData =
          await chartImage.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        print("❌ Failed to convert image to byte data.");
        return;
      }

      final Uint8List imageBytes = byteData.buffer.asUint8List();

      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(pw.MemoryImage(imageBytes)),
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
      );

      print("✅ Chart exported to PDF successfully.");
    } catch (e, stack) {
      print("❌ Exception during chart export: $e");
      print(stack);
    }
  }

  Future<void> _getSystemDevices() async {
    // For macOS and iOS, it is recommended to set a filter to get system devices
    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS &&
            (scanFilter?.withServices ?? []).isEmpty) {
      showSnackbar(
          "No services filter was set for getting system connected devices. Using default services...");
    }

    List<BleDevice> devices = await UniversalBle.getSystemDevices(
      withServices: scanFilter?.withServices,
    );
    if (devices.isEmpty) {
      showSnackbar("No System Connected Devices Found");
    }
    setState(() {
      _bleDevices.clear();
      _bleDevices.addAll(devices);
    });
  }

  initScanFilter() {
    List<String> serviceUUids = [];
    List<String> namePrefixes = [];
    List<ManufacturerDataFilter> manufacturerDataFilters = [];

    // Parse Services
    if (ServiceUUID.isNotEmpty) {
      List<String> services = ServiceUUID.split(',');
      for (String service in services) {
        try {
          serviceUUids.add(BleUuidParser.string(service.trim()));
        } on FormatException catch (_) {
          throw Exception("Invalid Service UUID $service");
        }
      }
    }

    String namePrefix = BLENAMES;
    // String namePrefix ="BLUE,YELLOW";
    if (namePrefix.isNotEmpty) {
      namePrefixes = namePrefix.split(',').map((e) => e.trim()).toList();
    }

    scanFilter = ScanFilter(
      withServices: serviceUUids,
      withNamePrefix: namePrefixes,
      withManufacturerData: manufacturerDataFilters,
    );
  }

  void stopHeartRateWriteLoop() {
    _heartRateWriteTimer?.cancel();
    _heartRateWriteTimer = null;
  }

  void _showScanFilterBottomSheet() {
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      builder: (context) {
        return ScanFilterWidget(
          servicesFilterController: servicesFilterController,
          namePrefixController: namePrefixController,
          manufacturerDataController: manufacturerDataController,
          onScanFilter: (ScanFilter? filter) {
            setState(() {
              scanFilter = filter;
            });
          },
        );
      },
    );
  }

  void showSnackbar(message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.toString())),
    );
  }

  _discoverServices(
      String deviceId, GlobalKey<ScannedItemWidgetNewState> key) async {
    const webWarning =
        "Note: Only services added in ScanFilter or WebOptions will be discovered";
    try {
      var services = await UniversalBle.discoverServices(deviceId);
      print('${services.length} services discovered');
      print(services);
      key.currentState?.updateDiscoveredServices(services);
      // Here i filtered the service UUID for application
    } catch (e) {
      // _addLog("DiscoverServicesError", '$e\n${kIsWeb ? webWarning : ""}');
    }
  }

  Uint8List createRequestFrame() {
    Uint8List reqFrame = Uint8List(20);
    reqFrame[0] = 0x53;
    reqFrame[1] = 0x31;
    reqFrame[19] = 0x4E;
    List<int> intList = reqFrame.toList();

    return reqFrame /*intList*/;
  }

  Uint8List buildHeartRateStartCommand() {
    final List<int> cmd = List.filled(16, 0);
    cmd[0] = 0x1E; // CMD_REAL_TIME_HEART_RATE
    cmd[1] = 0x01; // ACTION_START

    // CRC calculation
    int crc = 0;
    for (int i = 0; i < 15; i++) {
      crc += cmd[i];
    }
    cmd[15] = crc & 0xFF;

    print(
        "Sending Start HR command: ${cmd.map((b) => b.toRadixString(16).padLeft(2, '0')).join('-')}");
    return Uint8List.fromList(cmd);
  }

  Uint8List buildHeartRateContinueCommand() {
    final List<int> cmd = List.filled(16, 0);
    cmd[0] = 0x1E; // CMD_REAL_TIME_HEART_RATE
    cmd[1] = 0x03; // ACTION_CONTINUE

    // Fill rest with 0s (already done by List.filled), now compute CRC
    int crc = 0;
    for (int i = 0; i < 15; i++) {
      crc += cmd[i];
    }
    cmd[15] = crc & 0xFF;

    print(
        "Sending Continue HR command: ${cmd.map((b) => b.toRadixString(16).padLeft(2, '0')).join('-')}");
    return Uint8List.fromList(cmd);
  }

  Uint8List buildBatteryRequestCommand() {
    List<int> cmd = List.filled(16, 0); // Create a list of 16 zero bytes
    cmd[0] = 0x03; // CMD_GET_DEVICE_ELECTRICITY_VALUE

    int crc = 0;
    for (int i = 0; i < cmd.length - 1; i++) {
      crc += cmd[i];
    }
    cmd[15] = crc & 0xFF; // Ensure CRC is a single byte (0–255)

    return Uint8List.fromList(cmd);
  }

  String bitConverterLike(List<int> data) {
    return data
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join('-');
  }

  /// Call this method when new heart rate value is received
  void addHeartRateValue(int value) {
    _currentWindowValues.add(value);
    print(
        "❤️ Heart Rate: $value bpm /  arraylength --- ${_currentWindowValues}");
  }

  /// Print result in JSON format
  void _printJson() {
    final jsonOutput = heartRateLog.map((e) => e.toJson()).toList();
    print("📊 JSON Result:\n${jsonEncode(jsonOutput)}");
  }

  /// Optional: Call this to cancel early
  void stopRecording() {
    _peakRecordTimer?.cancel();
    print("🛑 Recording manually stopped.");
  }

  /// Call this to start recording
/*
  void startPeakHeartRateRecording() {
    startTime = DateTime.now();
    heartRateLog.clear();
    hrPerSecondMap.clear();
    intervalCount = 0;

    final maxIntervals = totalRecordingDurationInSeconds ~/ intervalInSeconds;

    peakRecordTimer?.cancel();
    peakRecordTimer = Timer.periodic(Duration(seconds: intervalInSeconds), (timer) {
      intervalCount++;

      final startWindow = startTime!.add(Duration(seconds: (intervalCount - 1) * intervalInSeconds));
      final endWindow = startTime!.add(Duration(seconds: intervalCount * intervalInSeconds));

      final windowEntries = hrPerSecondMap.entries.where((entry) {
        final parts = entry.key.split(":");
        final entryTime = DateTime(
          startWindow.year,
          startWindow.month,
          startWindow.day,
          startWindow.hour,
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
        return entryTime.isAfter(startWindow.subtract(Duration(milliseconds: 1))) &&
            entryTime.isBefore(endWindow.add(Duration(milliseconds: 1)));
      }).toList();

      if (windowEntries.isNotEmpty) {
        final peak = windowEntries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
        final alignedTimestamp = endWindow;

        heartRateLog.add(HeartRateSample(
          durationInSec: intervalCount * intervalInSeconds,
          timestamp: alignedTimestamp,
          peak: peak,
          minute: alignedTimestamp.minute.toString().padLeft(2, '0'),
          second: alignedTimestamp.second.toString().padLeft(2, '0'),
        ));

        print("📈 PEAK: $peak bpm @ ${alignedTimestamp.minute}:${alignedTimestamp.second}");
      } else {
        print("⚠️ No HR data in window ending at $endWindow");
      }

      if (intervalCount >= maxIntervals) {
        timer.cancel();
        print("✅ Done logging ${(intervalCount * intervalInSeconds) ~/ 60} min of heart rate peaks.");
        printHeartRateJson();
      }
    });
  }
*/

  /// Print final results
  void printHeartRateJson() {
    final jsonList = heartRateLog.map((e) => e.toJson()).toList();
    print("📊 Final HR Log JSON:");
    print(jsonList);
  }

  /*void startPeakHeartRateRecording1() {
    _startTime = DateTime.now();
    _intervalCount = 0;
    _perSecondHeartRates.clear();
    heartRateLog.clear();

    final int intervalDurationInSeconds = 30;
    final int totalDurationInSeconds = 120; // 2 minutes

    _peakRecordTimer?.cancel();
    _peakRecordTimer = Timer.periodic(Duration(seconds: intervalDurationInSeconds), (timer) {
      _intervalCount++;
      final elapsedWindowStart = (_intervalCount - 1) * intervalDurationInSeconds;
      final elapsedWindowEnd = _intervalCount * intervalDurationInSeconds - 1;

      int? peakValue;
      int? peakSecond;

      for (int sec = elapsedWindowStart; sec <= elapsedWindowEnd; sec++) {
        final value = _perSecondHeartRates[sec];
        if (value != null) {
          if (peakValue == null || value > peakValue) {
            peakValue = value;
            peakSecond = sec;
          }
        }
      }

      final alignedTimestamp = _startTime!.add(Duration(seconds: _intervalCount * intervalDurationInSeconds));

      if (peakValue != null && peakSecond != null) {
        heartRateLog.add(HeartRateSample(
          durationInSec: _intervalCount * intervalDurationInSeconds,
          timestamp: alignedTimestamp,
          peak: peakValue,
          peakAtSec: peakSecond,
          peakAtMin: peakSecond ~/ 60,
        ));

        print("📈 Peak $peakValue bpm at second $peakSecond (window ${elapsedWindowStart}–${elapsedWindowEnd})");
      } else {
        print("⚠️ No HR data in window $elapsedWindowStart–$elapsedWindowEnd");
      }

      if (_intervalCount * intervalDurationInSeconds >= totalDurationInSeconds) {
        timer.cancel();
        print("✅ Finished recording.");
        _printJson(); // Optional: output the results
      }
    });
  }*/

/*  /// Call this method once to start recording
  void startPeakHeartRateRecording1() {
    _startTime = DateTime.now();
    heartRateLog.clear();
    _currentWindowValues.clear();
    _intervalCount = 0;

    // final int totalRecordingDurationInSeconds = 120; // e.g. 2 mins
    // final int intervalDurationInSeconds = 30;
    // final int maxIntervals = totalRecordingDurationInSeconds ~/ intervalDurationInSeconds;

    _peakRecordTimer?.cancel();
    _peakRecordTimer = Timer.periodic(Duration(seconds: intervalDurationInSeconds), (timer) {
      _intervalCount++;
      final alignedTimestamp =
      _startTime!.add(Duration(seconds: _intervalCount * intervalDurationInSeconds));

      if (_currentWindowValues.isNotEmpty) {
        print("Saved heart rate value == $_currentWindowValues");
        final peak = _currentWindowValues.reduce((a, b) => a > b ? a : b);

        heartRateLog.add(HeartRateSample(
          durationInSec: _intervalCount * intervalDurationInSeconds,
          timestamp: alignedTimestamp,
          peak: peak,
        ));

        print("📈 Peak: $peak bpm @ ${alignedTimestamp.toIso8601String()}");
      } else {
        print("⚠️ No HR data in window ending at $alignedTimestamp");
      }

      _currentWindowValues.clear();

      if (_intervalCount >= maxIntervals) {
        timer.cancel();
        print("✅ Done logging ${_intervalCount * intervalDurationInSeconds ~/ 60} minutes of peak heart rates.");
        _printJson();
      }
    });
  }*/

  void startPeakLogging() {
    _startTime = DateTime.now();
    _intervalCount = 0;
    hrPerSecondMap.clear();
    heartRateLog.clear();
    print("start peak is called == =");

    Timer.periodic(Duration(seconds: intervalDurationInSeconds), (timer) {
      _intervalCount++;

      final startWindow = _startTime!.add(
          Duration(seconds: (_intervalCount - 1) * intervalDurationInSeconds));
      final endWindow = _startTime!
          .add(Duration(seconds: _intervalCount * intervalDurationInSeconds));

      final entries = hrPerSecondMap.entries.where((entry) {
        final entryTime = entry.key; // ✅ DateTime key directly
        return entryTime.isAfter(
                startWindow.subtract(const Duration(milliseconds: 1))) &&
            entryTime.isBefore(endWindow.add(const Duration(milliseconds: 1)));
      }).toList();

      if (entries.isNotEmpty) {
        final peakEntry = entries
            .reduce((a, b) => a.value > b.value ? a : b); // peak HR entry
        final peak = peakEntry.value;
        final peakTime = peakEntry.key; // ✅ Already DateTime

        final peakTimestamp = peakTime;
        final peakMin = peakTime.minute;
        final peakSec = peakTime.second;
        final peakhour = peakTime.hour;

        heartRateLog.add(HeartRateSample(
          durationInSec: _intervalCount * intervalDurationInSeconds,
          timestamp: peakTimestamp,
          heartRatePeak: peak,
          peakAthour: peakhour,
          peakAtMin: peakMin,
          peakAtSec: peakSec,
        ));

        print(
            "📈 PEAK: $peak bpm @ ${peakMin.toString().padLeft(2, '0')}:${peakSec.toString().padLeft(2, '0')}");
      } else {
        print("⚠️ No HR data in window ending at $endWindow");
      }

      if (_intervalCount >= maxIntervals) {
        timer.cancel();
        print("✅ Peak logging complete");
        print(
            "📤 Final JSON:\n${jsonEncode(heartRateLog.map((e) => e.toJson()).toList())}");
      }
    });
  }

  void listenToNotifications() {
    UniversalBle.onValueChange =
        (String deviceId, String characteristicId, Uint8List value) {
      List<int> _sensorvalue = value.toList();
      String hexString = bytesToHex(_sensorvalue);

      /*if (isHeartRateSensor) {
        if (value.isNotEmpty) {
          final raw = bitConverterLike(value);

          int heartRate = 0;
          int battery = 0;

          if (_intervalCount >= maxIntervals) {
            print("❌ Heart rate sensor value read stopped");
            return;
          }

          if (value.length >= 2 && value[0] == 0x1E) {
            heartRate = value[1] & 0xFF;

            // ✅ Log per-second heart rate value
            final now = DateTime.now();
            final key = '${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
            hrPerSecondMap[key] = heartRate;
            print("❤️ HR recorded: $heartRate bpm at $key");
          } else if (value[0] == 0x03) {
            battery = value[1] & 0xFF;
            if (battery >= 0 && battery <= 100) {
              print("🔋 Battery: $battery%");
            } else {
              print("❗ Battery value out of range: $battery");
            }
          }

          // Update UI widget with data
          for (var item in scannedItems) {
            if (item.bleDevice.deviceId == deviceId) {
              final key = item.key as GlobalKey<ScannedItemWidgetNewState>;
              key.currentState?.updateHeartRateSendorData(heartRate, battery);
              break;
            }
          }
        }
      }*/

      if (isHeartRateSensor && value.isNotEmpty) {
        final raw = bitConverterLike(value);

        if (_intervalCount >= maxIntervals) {
          print("❌ Heart rate sensor value read stopped");
          return;
        }

        final now = DateTime.now();

        if (value.length >= 2 && value[0] == 0x1E) {
          final is16Bit = (value[0] & 0x01) == 0x01;

          if (is16Bit && value.length >= 3) {
            // 16-bit heart rate
            heartRate = value[1] & 0xFF | ((value[2] & 0xFF) << 8);
          } else {
            // 8-bit heart rate
            heartRate = value[1] & 0xFF;
          }
          // heartRate = value[1] & 0xFF;

          // ✅ Use DateTime directly as key
          hrPerSecondMap[now] = heartRate;

          print("❤️ HR recorded: $heartRate bpm at ${now.toIso8601String()}");
        } else if (value[0] == 0x03) {
          battery = value[1] & 0xFF;
          print(battery >= 0 && battery <= 100
              ? "🔋 Battery: $battery%"
              : "❗ Battery value out of range: $battery");
        }

        // ✅ Update UI
        for (var item in scannedItems) {
          if (item.bleDevice.deviceId == deviceId) {
            final key = item.key as GlobalKey<ScannedItemWidgetNewState>;
            key.currentState?.updateHeartRateSendorData(heartRate, battery);
            break;
          }
        }
      }

      if (!isHeartRateSensor) {
        for (var item in scannedItems) {
          if (item.bleDevice.deviceId == deviceId) {
            final key = item.key as GlobalKey<ScannedItemWidgetNewState>;
            // key.currentState?.updateConnectionState(isConnected);
            key.currentState?.dataConversion4(/*_value*/ hexString);
            debugPrint(
                'onValueChange $deviceId, $characteristicId, ${hex.encode(value)}');
            break;
          }
        }
      }
    };
  }

  void submitData1(BuildContext context, List<HeartRateSample> heartRateLog) {
    if (heartRateLog.isEmpty) {
      print("⚠️ No heart rate data recorded.");
      return;
    }

    final jsonList = heartRateLog.map((e) => e.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    print("📤 Final JSON:\n$jsonString");

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Recorded Peak Heart Rates"),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🔶 Legend
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.circle, color: Colors.orange, size: 10),
                  const SizedBox(width: 4),
                  const Text("HR > 80"),
                  const SizedBox(width: 12),
                  Icon(Icons.circle, color: Colors.blue, size: 10),
                  const SizedBox(width: 4),
                  const Text("HR ≤ 80"),
                ],
              ),
              const SizedBox(height: 8),

              // 📈 Chart
              SizedBox(
                height: 200,
                child: LineChart(
                  LineChartData(
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 1,
                          getTitlesWidget: (value, _) => Text(
                            "#${value.toInt() + 1}",
                            style: const TextStyle(
                                fontSize: 10, color: Colors.black),
                          ),
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 20,
                          getTitlesWidget: (value, _) => Text(
                            value.toInt().toString(),
                            style: const TextStyle(
                                fontSize: 10, color: Colors.black),
                          ),
                        ),
                      ),
                      rightTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(show: true),
                    borderData: FlBorderData(show: true),
                    lineBarsData: [
                      // 💙 Blue line for HR ≤ 80
                      LineChartBarData(
                        spots: heartRateLog
                            .asMap()
                            .entries
                            .where((e) => e.value.heartRatePeak <= 80)
                            .map((e) => FlSpot(e.key.toDouble(),
                                e.value.heartRatePeak.toDouble()))
                            .toList(),
                        isCurved: true,
                        barWidth: 2,
                        color: Colors.blue,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, _, __, ___) =>
                              FlDotCirclePainter(
                                  radius: 4,
                                  color: Colors.blue,
                                  strokeWidth: 0),
                        ),
                        // belowBarData: BarAreaData(show: false),
                      ),

                      // 🟠 Orange line for HR > 80
                      LineChartBarData(
                        spots: heartRateLog
                            .asMap()
                            .entries
                            .where((e) => e.value.heartRatePeak > 80)
                            .map((e) => FlSpot(e.key.toDouble(),
                                e.value.heartRatePeak.toDouble()))
                            .toList(),
                        isCurved: true,
                        barWidth: 2,
                        color: Colors.orange,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, _, __, ___) =>
                              FlDotCirclePainter(
                                  radius: 4,
                                  color: Colors.orange,
                                  strokeWidth: 0),
                        ),
                        belowBarData: BarAreaData(show: false),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // 📋 List of values
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: heartRateLog.length,
                  itemBuilder: (context, index) {
                    final sample = heartRateLog[index];
                    return ListTile(
                      leading: Text("#${index + 1}"),
                      title: Text("Peak: ${sample.heartRatePeak} bpm"),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Timestamp: ${sample.timestamp.toLocal()}"),
                          Text("Duration: ${sample.durationInSec}s"),
                          Text(
                              "At: ${sample.peakAtMin.toString().padLeft(2, '0')}:${sample.peakAtSec.toString().padLeft(2, '0')}"),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          )
        ],
      ),
    );
  }

  Widget buildHeartRateCombinedChartWithToolTip(
      List<HeartRateSample> heartRateLog,double rrmsd) {
    final spots = heartRateLog
        .map((e) =>
            FlSpot(e.durationInSec.toDouble(), e.heartRatePeak.toDouble()))
        .toList();

    final Map<double, HeartRateSample> spotDataMap = {
      for (var sample in heartRateLog) sample.durationInSec.toDouble(): sample,
    };
    final screenWidth = MediaQuery.of(context).size.width;

    final maxPeak = heartRateLog
        .map((e) => e.heartRatePeak)
        .reduce((a, b) => a > b ? a : b);
    double contentWidth =
        (heartRateLog.length * 50).toDouble().clamp(300, 1000);
    double chartWidth = math.max(screenWidth * 0.65, contentWidth);
    final maxHeartRate = heartRateLog
        .map((e) => e.heartRatePeak)
        .reduce((a, b) => a > b ? a : b);

    final chartHeight =
        (maxHeartRate * 5).clamp(250, 400).toDouble(); // scale & clamp

    final lineChartBar = LineChartBarData(
      spots: spots,
      isCurved: true,
      barWidth: 0.5,
      // barWidth: 2,
      isStepLineChart: false,
      color: Colors.black,
      // 👈 Line color

      // color: Color.,
      // color: Colors.grey.shade600,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, _, __, ___) {
          final hr = spot.y.toInt();
          return FlDotCirclePainter(
            radius: 4,
            color: hr > 80 ? Colors.orange : Colors.blue,
            strokeWidth: 0,
          );
        },
      ),
      belowBarData: BarAreaData(show: false),
    );

    return SizedBox(
      // height: 250,
      height: chartHeight + 150,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
            // width: (heartRateLog.length * 50).toDouble().clamp(300, 1000),
            width: chartWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10.0),
                  // 👈 Avoid bottom clipping
                  child: SizedBox(
                      height: chartHeight + 60,
                      child: LineChart(
                        LineChartData(
                          minY: 0,
                          maxY:160,
                          // maxY: (((heartRateLog.map((e) => e.heartRatePeak).reduce((a, b) => a > b ? a : b) + 39) ~/ 20) * 20),
                          // maxY: (((heartRateLog
                          //                 .map((e) => e.heartRatePeak)
                          //                 .reduce((a, b) => a > b ? a : b) +
                          //             39) ~/
                          //         20) *
                          //     40),

                          // maxY: ((heartRateLog.map((e) => e.heartRatePeak).reduce((a, b) => a > b ? a : b) + 19) ~/ 20) * 20, // 👈 clean rounded maxY

                          // maxY: heartRateLog.map((e) => e.heartRatePeak).reduce((a, b) => a > b ? a : b) + 10,
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                reservedSize: 28,
                                showTitles: true,
                                interval: 30,
                                getTitlesWidget: (value, _) => Text(
                                    "${value.toInt()}s",
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.black)),
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                reservedSize: 40,
                                // 👈 space for label + padding
                                showTitles: true,
                                interval: 40 /*40*/,
                                getTitlesWidget: (value, _) => Text(
                                    value.toInt().toString(),
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.black)),
                              ),
                            ),
                            rightTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            topTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                          ),
                          gridData: FlGridData(show: true,
                            drawVerticalLine: true,
                            drawHorizontalLine: true,
                            horizontalInterval: 1,
                            verticalInterval: 1,
                              checkToShowHorizontalLine: (value) {
                                // Add grid lines for every 10 units on Y-axis
                                return value % 10 == 0;
                              },
                            getDrawingHorizontalLine: (value) => FlLine(
                              color: Colors.grey.shade300,
                              strokeWidth: 0.5, // 🔧 Thinner horizontal lines
                            ),
                            getDrawingVerticalLine: (value) => FlLine(
                              color: Colors.grey.shade300,
                              strokeWidth: 0.5, // 🔧 Thinner vertical lines
                            ),
                            checkToShowVerticalLine: (value) {
                              final xValues = spots.map((e) => e.x).toSet();

                              // Add extra grid lines every 10 units up to the max x
                              final double maxX = spots.map((e) => e.x).reduce(max);
                              for (double i = 0; i <= maxX + 10; i += 10) {
                                xValues.add(double.parse(i.toStringAsFixed(1)));
                              }

                              return xValues.contains(double.parse(value.toStringAsFixed(1)));
                            },
                            // checkToShowVerticalLine: (value) {
                            //   // Show vertical grid only where there's a matching x value
                            //   final xValues = spots.map((e) => e.x).toSet();
                            //   return xValues.contains(value);
                            // },
                          ),
                          borderData: FlBorderData(show: true),
                          lineBarsData: [lineChartBar],

                          // ✅ Enable tooltips over every dot
                          showingTooltipIndicators: spots
                              .map((spot) => ShowingTooltipIndicators([
                                    LineBarSpot(lineChartBar, 0, spot),
                                  ]))
                              .toList(),

                          lineTouchData: LineTouchData(
                            enabled: true,
                            handleBuiltInTouches: false,
                            getTouchedSpotIndicator: (barData, spotIndexes) {
                              return spotIndexes.map((index) {
                                return TouchedSpotIndicatorData(
                                  FlLine(color: Colors.grey, strokeWidth: 0.5),
                                  // optional vertical line
                                  FlDotData(show: true), // show dot
                                );
                              }).toList();
                            },

                            // getTouchedSpotIndicator: (barData, indexes) {
                            //   return indexes.map((index) {
                            //     return TouchedSpotIndicatorData(
                            //       FlLine(color: Colors.transparent),
                            //       FlDotData(show: false),
                            //     );
                            //   }).toList();
                            // },
                            touchTooltipData: LineTouchTooltipData(
                              // showOnTopOfTheChartBoxArea: true,
                              // tooltipBgColor: Colors.white,
                              // tooltipBgColor: Colors.white.withOpacity(0.095), // 80% opaque white
                              // tooltipRoundedRadius: 10,
                              // tooltipRoundedRadius: 0,                       // ⛔ remove rounded shape
                              // tooltipPadding: const EdgeInsets.all(3),
                              // tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              // tooltipMargin: 5, // 👈 Creates gap between dot and tooltip
                              // tooltipBorder: BorderSide(color: Colors.black26),
                              fitInsideHorizontally: true,
                              fitInsideVertically: true,
                              tooltipBgColor: Colors.transparent,
                              // transparent background
                              tooltipRoundedRadius: 0,
                              // no rounded corners
                              tooltipPadding: EdgeInsets.zero,
                              // no internal padding
                              tooltipMargin: 0,
                              getTooltipItems: (touchedSpots) {
                                return touchedSpots.map((spot) {
                                  final hr = spot.y.toInt();
                                  final duration = spot.x.toInt();

                                  return LineTooltipItem(
                                    "$hr", //
                                    // "⏱ ${duration}s\n❤️ $hr bpm", // Tooltip text
                                    const TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black
                                        // color: Colors.white,
                                        ),
                                    textAlign: TextAlign
                                        .center, // 👈 works only if you use newer fl_chart

                                    // children: [
                                    //   const TextSpan(
                                    //     text: "",
                                    //     style: TextStyle(fontSize: 8, color: Colors.grey),
                                    //   ),
                                    // ],
                                  );
                                }).toList();
                              },
                            ),

                            // touchTooltipData: LineTouchTooltipData(
                            //   tooltipBgColor: Colors.white,
                            //   // tooltipRoundedRadius: 4,
                            //   tooltipPadding: const EdgeInsets.all(6),
                            //   tooltipBorder: BorderSide(color: Colors.black26),
                            //   fitInsideHorizontally: true,
                            //   fitInsideVertically: true,
                            //   tooltipRoundedRadius: 8,
                            //   tooltipMargin: 12, // 👈 Push tooltip away from dot
                            //   getTooltipItems: (touchedSpots) {
                            //     return touchedSpots.map((spot) {
                            //       return LineTooltipItem(
                            //         "${spot.y.toInt()} bpm",
                            //         const TextStyle(
                            //           fontWeight: FontWeight.bold,
                            //           fontSize: 10,
                            //           color: Colors.black,
                            //         ),
                            //       );
                            //     }).toList();
                            //   },
                            // ),
                          ),
                        ),
                      )),
                ),

                const SizedBox(height: 2),
                // spacing
                // const Text(
                //   "30's Interval ", // 👈 your custom label
                //   style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                // ),
                const Center(
                  child: Text(
                    "30's Interval ", // 👈 Centered label below chart
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.black),
                  ),
                ),

                Center(
                  child: Text(
                    "RMMSD Value  ${rrmsd}", // 👈 Centered label below chart
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.blue, // 🔵 Updated color
                    ),
                  ),
                ),

              ],
            )),
      ),
    );
  }

  Widget buildHeartRateCombinedChartWihoutTooltip(
      List<HeartRateSample> heartRateLog) {
    return SizedBox(
      height: 220,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: (heartRateLog.length * 50).toDouble().clamp(300, 1000),
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: heartRateLog
                      .map((e) => e.heartRatePeak)
                      .reduce((a, b) => a > b ? a : b) +
                  10,
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 30,
                    getTitlesWidget: (value, _) => Text(
                      "${value.toInt()}s",
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 20,
                    getTitlesWidget: (value, _) => Text(
                      value.toInt().toString(),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
                rightTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(show: true),
              borderData: FlBorderData(show: true),
              lineBarsData: [
                LineChartBarData(
                  spots: heartRateLog
                      .map((e) => FlSpot(e.durationInSec.toDouble(),
                          e.heartRatePeak.toDouble()))
                      .toList(),
                  isCurved: true,
                  barWidth: 2,
                  color: Colors.grey.shade600,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, _, __, ___) {
                      final hr = spot.y.toInt();
                      return FlDotCirclePainter(
                        radius: 4,
                        color: hr > 80 ? Colors.orange : Colors.blue,
                        strokeWidth: 0,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(show: false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildHeartRateWithoutCombineChart(List<HeartRateSample> heartRateLog) {
    return SizedBox(
      height: 220,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: (heartRateLog.length * 50).toDouble().clamp(300, 1000),
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: heartRateLog
                      .map((e) => e.heartRatePeak)
                      .reduce((a, b) => a > b ? a : b) +
                  10,
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 30,
                    getTitlesWidget: (value, _) => Text(
                      "${value.toInt()}s",
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 20,
                    getTitlesWidget: (value, _) => Text(
                      value.toInt().toString(),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
                rightTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(show: true),
              borderData: FlBorderData(show: true),
              lineBarsData: [
                // 💙 Blue line for HR ≤ 80
                LineChartBarData(
                  spots: heartRateLog
                      .where((e) => e.heartRatePeak <= 80)
                      .map((e) => FlSpot(e.durationInSec.toDouble(),
                          e.heartRatePeak.toDouble()))
                      .toList(),
                  isCurved: true,
                  barWidth: 2,
                  color: Colors.blue,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                        radius: 4, color: Colors.blue, strokeWidth: 0),
                  ),
                  belowBarData: BarAreaData(show: false),
                ),

                // 🟠 Orange line for HR > 80
                LineChartBarData(
                  spots: heartRateLog
                      .where((e) => e.heartRatePeak > 80)
                      .map((e) => FlSpot(e.durationInSec.toDouble(),
                          e.heartRatePeak.toDouble()))
                      .toList(),
                  isCurved: true,
                  barWidth: 2,
                  color: Colors.orange,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                        radius: 4, color: Colors.orange, strokeWidth: 0),
                  ),
                  belowBarData: BarAreaData(show: false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> submitData(
      BuildContext context, List<HeartRateSample> heartRateLog) async {
    if (heartRateLog.isEmpty) {
      print("⚠️ No heart rate data recorded.");
      return;
    }

    final jsonList = heartRateLog.map((e) => e.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    print("📤 Final JSON:\n$jsonString");

    final List<double> rrinterval = jsonList.map((entry) {
      final peak = entry['peak'] as int;
      return double.parse((60000 / peak).toStringAsFixed(2));
    }).toList();
    print("📤 RR interval ${rrinterval}");

    final List<double> successiveRRIntervalDiffs = [];
    for (int i = 1; i < rrinterval.length; i++) {
      final diff = rrinterval[i] - rrinterval[i - 1];
      successiveRRIntervalDiffs.add(diff);
    }

    // for (int i = 1; i < rrinterval.length; i++) {
    //   double diff =
    //       double.parse((rrinterval[i] - rrinterval[i - 1]).toStringAsFixed(2));
    //   rrintervalDiff.add(diff);
    // }
    print("📤 RR interval Difference ${successiveRRIntervalDiffs}");

    // Step 3: Square root of absolute differences
    final List<double> squaredDiffs = successiveRRIntervalDiffs
        .map((d) => double.parse(pow(d.abs(), 2).toStringAsFixed(4)))
        .toList();
    print("📤 RR interval Difference square root ${squaredDiffs}");




    // Step 4: Sum and Average
    final double sqrtDiffSum = squaredDiffs.reduce((a, b) => a + b);
    final double meanSquare  = double.parse((sqrtDiffSum / squaredDiffs.length).toStringAsFixed(4));
    print("📤 RR interval Difference square root sum & average  ${sqrtDiffSum} / ${meanSquare }");

    final double RMSSD = double.parse(sqrt(meanSquare).toStringAsFixed(4));

    print("RMSSD value  === ${RMSSD} ms");

    rMSSD = RMSSD;
    final GlobalKey chartKey = GlobalKey();


    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white, // 👈 Set background here

        title: const Text("Recorded Peak Heart Rates",
            style: const TextStyle(fontSize: 10, color: Colors.black)),
        content: SingleChildScrollView(
          child: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 🔶 Legend
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.circle, color: Colors.orange, size: 10),
                    const SizedBox(width: 4),
                    const Text("HR > 80",
                        style:
                            const TextStyle(fontSize: 10, color: Colors.black)),
                    const SizedBox(width: 12),
                    Icon(Icons.circle, color: Colors.blue, size: 10),
                    const SizedBox(width: 4),
                    const Text("HR ≤ 80",
                        style:
                            const TextStyle(fontSize: 10, color: Colors.black)),
                  ],
                ),
                const SizedBox(height: 8),

                // 📈 Chart with horizontal scroll
                // buildHeartRateCombinedChart(heartRateLog),
                // 2️⃣ Wrap the chart with RepaintBoundary
                Row(
                  children: [
                    RepaintBoundary(
                      key: chartKey,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: SizedBox(
                          // height: 300, // ⬅️ Increase this value to make the chart taller
                          child: buildHeartRateCombinedChartWithToolTip(
                              heartRateLog,RMSSD),
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        exportChartToPdf(chartKey);
                      },
                      child: Text("Export to PDF",
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white)),
                    )
                  ],
                ),

                const SizedBox(height: 10),

                // 📋 List of values
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: heartRateLog.length,
                  itemBuilder: (context, index) {
                    final sample = heartRateLog[index];
                    return ListTile(
                      leading: Text("#${index + 1}",
                          style: const TextStyle(
                              fontSize: 10, color: Colors.black)),
                      title: Text("Peak: ${sample.heartRatePeak} bpm",
                          style: const TextStyle(
                              fontSize: 10, color: Colors.black)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Timestamp: ${sample.timestamp.toLocal()}",
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.black)),
                          Text("Duration: ${sample.durationInSec}s",
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.black)),
                          Text(
                              "At: ${sample.peakAtMin.toString().padLeft(2, '0')}:${sample.peakAtSec.toString().padLeft(2, '0')}",
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.black)),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close",
                style: const TextStyle(fontSize: 10, color: Colors.white)),
          )
        ],
      ),
    );

    setState(() {

    });
  }

  Future<void> enableNotificationsForMultipleSensors(
      List<ScannedItemWidgetNew> devices) async {
    for (var device in devices) {
      try {
        await UniversalBle.setNotifiable(device.bleDevice.deviceId, ServiceUUID,
            NotifyCharacteristicUUID, BleInputProperty.notification);
        print("✅ Notifications enabled for ${device.bleDevice.name}");
      } catch (e) {
        print(
            "❌ Failed to enable notifications for ${device.bleDevice.name}: $e");
      }
      await Future.delayed(
          Duration(milliseconds: 200)); // Small delay between notifications
    }
  }

  Future<void> writeToMultipleSensors(
      /*List<BleDevice>*/
      List<ScannedItemWidgetNew> devices,
      Uint8List value) async {
    for (var device in devices) {
      try {
        await UniversalBle.writeValue(device.bleDevice.deviceId, ServiceUUID,
            WriteCharacteristicUUID, value, BleOutputProperty.withoutResponse);
        print("📤 Data sent to ${device.bleDevice.name}");
      } catch (e) {
        print("❌ Failed to write to ${device.bleDevice.name}: $e");
      }
      await Future.delayed(
          Duration(milliseconds: 200)); // Small delay between writes
    }
  }

  Future<void> writeDateToHeartRateSensors(
    List<ScannedItemWidgetNew> devices,
    Uint8List heartrate,
    Uint8List continueHeartrate,
    Uint8List batteryRate,
  ) async {
    for (var device in devices) {
      final deviceId = device.bleDevice.deviceId;
      final deviceName = device.bleDevice.name;

      try {
        // 1️⃣ Send heart rate start command
        await UniversalBle.writeValue(
          deviceId,
          ServiceUUID,
          WriteCharacteristicUUID,
          heartrate,
          BleOutputProperty.withoutResponse,
        );
        print("📤 Heart rate start sent to $deviceName");
        await Future.delayed(Duration(milliseconds: 200));
      } catch (e) {
        print("❌ Failed to send heart rate start to $deviceName: $e");
      }

      try {
        // 2️⃣ Send battery request
        await UniversalBle.writeValue(
          deviceId,
          ServiceUUID,
          WriteCharacteristicUUID,
          batteryRate,
          BleOutputProperty.withoutResponse,
        );
        print("📤 Battery request sent to $deviceName");
        await Future.delayed(Duration(milliseconds: 200));
      } catch (e) {
        print("❌ Failed to send battery request to $deviceName: $e");
      }

      try {
        // 3️⃣ Start periodic continuous heart rate write
        startHeartRateWriteLoop(device, continueHeartrate);
        print("🔁 Started periodic continuous HR write for $deviceName");
      } catch (e) {
        print("❌ Failed to start HR write loop for $deviceName: $e");
      }
    }
  }

  void startHeartRateWriteLoop(
      ScannedItemWidgetNew scanneddevice, Uint8List value1) {
    _heartRateWriteTimer?.cancel(); // Cancel previous timer if any

    _heartRateWriteTimer = Timer.periodic(Duration(seconds: 30), (_) async {
      // for (var device in scannedItems) {
      try {
        await UniversalBle.writeValue(
          scanneddevice.bleDevice.deviceId,
          ServiceUUID,
          WriteCharacteristicUUID,
          value1,
          BleOutputProperty.withResponse,
        );
        print(
            "📤 Sent continuous HR command to ${scanneddevice.bleDevice.name}");
      } catch (e) {
        print("❌ Failed to write to ${scanneddevice.bleDevice.name}: $e");
      }

      await Future.delayed(
          Duration(seconds: 8)); // Optional: small gap between devices

      try {
        await UniversalBle.writeValue(
          scanneddevice.bleDevice.deviceId,
          ServiceUUID,
          WriteCharacteristicUUID,
          buildBatteryRequestCommand(),
          BleOutputProperty.withResponse,
        );
        print("📤 Sent Battery  command to ${scanneddevice.bleDevice.name}");
      } catch (e) {
        print("❌ Failed to write to ${scanneddevice.bleDevice.name}: $e");
      }
      // }
    });
  }

  void _handleConnectionChange(
      String deviceId, bool isConnected, String? error) async {
    print(
        '_handleConnectionChange $deviceId, $isConnected ${error != null ? 'Error: $error' : ''}');

    for (var item in scannedItems) {
      if (item.bleDevice.deviceId == deviceId) {
        final key = item.key as GlobalKey<ScannedItemWidgetNewState>;
        key.currentState?.updateConnectionState(isConnected);
        if (isConnected) {
          await _discoverServices(deviceId, key);
        }

        break;
      }
    }
  }

  String bytesToHex(List<int> bytes) {
    if (bytes == null) {
      return "";
    }

    var sb = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
      if (i < bytes.length - 1) {
        sb.write('_'); // Add underscore between each pair of hexadecimal digits
      }
    }

    return sb.toString();
  }

  void connectAllDevices() async {
    for (ScannedItemWidgetNew item in scannedItems) {
      try {
        String deviceId = item.bleDevice.deviceId;
        print("🔗 Connecting to $deviceId...");
        await UniversalBle.connect(deviceId);
        print("✅ Connected to $deviceId");
      } catch (e) {
        print("❌ Failed to connect: $e");
      }
    }
  }

  Future<List<HeartRateSample>> loadPage(int page) async {
    final fileName = 'assets/data/page$page.json';
    final jsonString =
    await rootBundle.loadString(fileName);
    final List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList.map((e) => HeartRateSample.fromJson(e)).toList();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Heart Rate Monitor'),
        elevation: 4,
        actions: [
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator.adaptive(
                    strokeWidth: 2,
                  )),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ResponsiveButtonsGrid(
              children: [
                // Start scan
                PlatformButton(
                  text: 'Start Scan',
                  onPressed: () async {
                    setState(() {
                      _bleDevices.clear();
                      _isScanning = true;
                    });
                    try {
                      await startScan();
                    } catch (e) {
                      setState(() {
                        _isScanning = false;
                      });
                      showSnackbar(e);
                    }
                  },
                ),

                //Stop Scan

                PlatformButton(
                  text: 'Stop Scan',
                  onPressed: () async {
                    await UniversalBle.stopScan();
                    setState(() {
                      _isScanning = false;
                    });
                  },
                ),

                if (BleCapabilities.supportsBluetoothEnableApi)
                  bleAvailabilityState != AvailabilityState.poweredOn
                      ? PlatformButton(
                          text: 'Enable Bluetooth',
                          onPressed: () async {
                            bool isEnabled =
                                await UniversalBle.enableBluetooth();
                            showSnackbar("BluetoothEnabled: $isEnabled");
                          },
                        )
                      : PlatformButton(
                          text: 'Disable Bluetooth',
                          onPressed: () async {
                            bool isDisabled =
                                await UniversalBle.disableBluetooth();
                            showSnackbar("BluetoothDisabled: $isDisabled");
                          },
                        ),
                if (BleCapabilities.requiresRuntimePermission)
                  PlatformButton(
                    text: 'Check Permissions',
                    onPressed: () async {
                      bool hasPermissions =
                          await PermissionHandler.arePermissionsGranted();
                      if (hasPermissions) {
                        showSnackbar("Permissions granted");
                      }
                    },
                  ),
                if (BleCapabilities.supportsConnectedDevicesApi)
                  PlatformButton(
                    text: 'System Devices',
                    onPressed: _getSystemDevices,
                  ),
                PlatformButton(
                  text: 'Queue: ${_queueType.name}',
                  onPressed: () {
                    setState(() {
                      _queueType = switch (_queueType) {
                        QueueType.global => QueueType.perDevice,
                        QueueType.perDevice => QueueType.none,
                        QueueType.none => QueueType.global,
                      };
                      UniversalBle.queueType = _queueType;
                    });
                  },
                ),

                //Scan filter

                PlatformButton(
                  text: 'Scan Filters',
                  onPressed: _showScanFilterBottomSheet,
                ),
                // if (_bleDevices.isNotEmpty)
                PlatformButton(
                  text: 'Clear List',
                  onPressed: () async {
                    stopHeartRateWriteLoop();
                    stopPeakRecording();
                    await disconnectAllDevices();
                    heartRateLog.clear();
                    heartRate = 0;
                    battery = 0;
                    _intervalCount = 0;
                    setState(() {
                      _bleDevices.clear();
                    });
                  },
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Ble Availability : ${bleAvailabilityState?.name}',
                ),
              ),
            ],
          ),
          const Divider(color: Colors.blue),
          ResponsiveButtonsGrid(children: [
            PlatformButton(
              text: 'Connect ',
              enabled: scannedItems.isNotEmpty, // Enable only if devices exist
              onPressed: () async {
                try {
                  connectAllDevices();
                } catch (e) {}
              },
            ),
            PlatformButton(
              text: 'Disconnect',
              enabled: true,
              onPressed: () async {
                stopHeartRateWriteLoop(); // stop periodic write

                await disconnectAllDevices();
              },
            ),
            PlatformButton(
              enabled: true,
              onPressed: () async {
                try {
                  if (!isHeartRateSensor) {
                    Uint8List value = createRequestFrame();

                    if (scannedItems.isNotEmpty) {
                      await writeToMultipleSensors(scannedItems, value);
                    } else {
                      print("❌ No connected BLE devices found.");
                    }
                  } else if (isHeartRateSensor) {
                    Uint8List heartRatecmd = buildHeartRateStartCommand();
                    Uint8List continueHeartRatecmd =
                        buildHeartRateContinueCommand();

                    Uint8List batteryValcmd = buildBatteryRequestCommand();

                    await writeDateToHeartRateSensors(scannedItems,
                        heartRatecmd, continueHeartRatecmd, batteryValcmd);
                  }
                } catch (e) {
                  return;
                }
              },
              text: 'Write',
            ),
            PlatformButton(
              enabled: true,
              onPressed: () async {
                try {
                  if (scannedItems.isNotEmpty) {
                    await enableNotificationsForMultipleSensors(scannedItems);
                    listenToNotifications();
                    startPeakLogging();
                  } else {
                    print("❌ No connected BLE devices found.");
                  }
                } catch (e) {
                  return;
                }
              },
              text: 'Subscribe',
            ),
            PlatformButton(
              text: 'Submit',
              enabled: true,
              onPressed: () async {
                try {
                  await submitData(context, heartRateLog);
                } catch (e) {}
              },
            ),

            PlatformButton(
              text: 'PDf From Local',
              enabled: true,
              onPressed: () async {
                try {
                  _peakDataFuture = await loadPeakDataFromAssets();
                  print("json from local == ${_peakDataFuture.length}");
                  await submitData(context,_peakDataFuture);
                } catch (e) {
                  print("local excaprion ==${e}");
                }
              },
            ),
          ]),
          PaginationWidget(
            currentPage: currentPage,
            totalPages: 9,
            onPageChanged: (page) async {
              _peakDataFuture = await loadPage(page);
              print("json from local == ${_peakDataFuture.length}");
              await submitData(context,_peakDataFuture);
              setState(() {
                currentPage = page;
              });
            },
          ),
          /*Row(
            children: [

              const SizedBox(width: 8),
              PlatformButton(
                text: 'Connect ',
                enabled: scannedItems.isNotEmpty, // Enable only if devices exist
                onPressed: () async {
                  try {
                    connectAllDevices();
                  } catch (e) {
                  }
                },
              ),
              const SizedBox(width: 8),
              PlatformButton(
                text: 'Disconnect',
                enabled: true,
                onPressed: () async {
                  await disconnectAllDevices();
                },
              ),
              const SizedBox(width: 8),
              PlatformButton(
                enabled:true,
                onPressed: () async {
                  try {
                  Uint8List value = createRequestFrame();

                  if (scannedItems.isNotEmpty) {
                    await writeToMultipleSensors(scannedItems, value);
                  } else {
                    print("❌ No connected BLE devices found.");
                  }
                  } catch (e) {
                    return;
                  }
                },
                text: 'Write',
              ),
              PlatformButton(
                enabled:true,

                onPressed: () async {
                  try {

                    if (scannedItems.isNotEmpty) {
                      await enableNotificationsForMultipleSensors(scannedItems);
                      listenToNotifications();
                    } else {
                      print("❌ No connected BLE devices found.");
                    }
                  } catch (e) {
                    return;
                  }
                },
                text: 'Subscribe',
              ),

            ],
          ),*/
          Expanded(
            child: scannedItems.isEmpty
                ? Center(child: Text("No devices found"))
                : SingleChildScrollView(
                    child:
                        Column(children: scannedItems), // Show widgets directly
                  ),
          ),
        ],
      ),
    );
  }
}
