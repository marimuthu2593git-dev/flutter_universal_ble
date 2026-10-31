import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:vector_math/vector_math_64.dart'
    show Quaternion, Vector3, degrees, Matrix3;
import 'dart:async';
import 'dart:typed_data';
import 'package:convert/convert.dart';

import '../../ble_constants.dart';
import '../../widgets/platform_button.dart';
import '../../widgets/responsive_buttons_grid.dart';

class ScannedItemWidgetNew extends StatefulWidget {
  final BleDevice bleDevice;
  final VoidCallback? onTap;
  final bool? isHeartRateSensor;

  ScannedItemWidgetNew(
      {super.key,
      required this.bleDevice,
      this.onTap,
      this.isHeartRateSensor = false});

  @override
  State<ScannedItemWidgetNew> createState() => ScannedItemWidgetNewState();
}

class ScannedItemWidgetNewState extends State<ScannedItemWidgetNew> {
  String? name = "";
  BleDevice? bleDevice;

  // String ServiceUUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  // String WriteCharacteristicUUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
  // String NotifyCharacteristicUUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

  bool isConnected = false;

  Vector3 accVect = Vector3.zero();
  Vector3 curAngle = Vector3.zero();

  double pitch = 0, yaw = 0, roll = 0;
  double calibPitch = 0, calibYaw = 0, calibRoll = 0;
  double accX = 0, accY = 0, accZ = 0;
  String batteryVal = "";
  List<BleService> discoveredServices = [];
  final List<String> _logs = [];

  int heartRateval = 0;
  int heartRatesensorBatval = 0;

  BleCharacteristic? writeCharacteristic;
  BleCharacteristic? readCharacteristic;

  ({
    BleService? service,
    BleCharacteristic? characteristic
  })? selectedWriteCharacteristic;

  ({
    BleService? service,
    BleCharacteristic? characteristic
  })? subscribeReadCharacteristic;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    name = widget.bleDevice.name;
    bleDevice = widget.bleDevice;

    // UniversalBle.onConnectionChange = (String deviceId, bool isConnected, String? error) {
    //   debugPrint('OnConnectionChange $deviceId, $isConnected Error: $error');
    // };

    // UniversalBle.onConnectionChange = _handleConnectionChange;
    // UniversalBle.onValueChange = _handleValueChange;
    // UniversalBle.onPairingStateChange = _handlePairingStateChange;
  }

  @override
  void dispose() {
    super.dispose();
    UniversalBle.onConnectionChange = null;
    UniversalBle.onValueChange = null;
    // Disconnect when leaving the page
    if (isConnected) UniversalBle.disconnect(bleDevice!.deviceId);
  }

  void updateConnectionState(bool isconnected) {
    setState(() {
      isConnected = isconnected;
    });
  }

  void updateDiscoveredServices(List<BleService> discoveredservices) {
    // setState(() {
    //   isConndisected = isconnected;
    // });
    this.discoveredServices = discoveredservices;

    if (discoveredServices.isNotEmpty) {
      discoveredServices.forEach((service) {
        service.characteristics.forEach((characteristic) {
          debugPrint("Character ${characteristic.uuid}");
          debugPrint("Character ${characteristic.properties}");
          List<CharacteristicProperty> properties = characteristic.properties;
          if (characteristic.uuid == WriteCharacteristicUUID) {
            if (properties.contains(CharacteristicProperty.write) ||
                properties
                    .contains(CharacteristicProperty.writeWithoutResponse)) {
              writeCharacteristic = characteristic;
              debugPrint(
                  "writeCharacteristic---- ${writeCharacteristic!.uuid}");
            }
          }
          //
          if (characteristic.uuid == NotifyCharacteristicUUID || /*&&*/
              (characteristic.properties
                  .contains(CharacteristicProperty.notify))) {
            readCharacteristic = characteristic;
          }
        });
      });

      // final BleService bleService = filteredServices.first;

      // Extract the write characteristic
      // writeCharacteristic = bleService.characteristics.firstWhere(
      //       (char) => char.properties.contains("write") || char.properties.contains("writeWithoutResponse"),
      // orElse: () => BleCharacteristic(uuid: "", properties: []), // Default empty characteristic
      // );

      // Extract the notify characteristic
      // readCharacteristic = bleService.characteristics.firstWhere(
      //       (char) => char.properties.contains("notify"),
      //   // orElse: () => BleCharacteristic(uuid: "", properties: []), // Default empty characteristic
      // );

      // Debug print
      print("Write Characteristic UUID: ${writeCharacteristic!.uuid}");
      print("Notify Characteristic UUID: ${readCharacteristic!.uuid}");
    }
  }

  void _handleConnectionChange(
    String deviceId,
    bool isConnected,
    String? error,
  ) {
    print(
      '_handleConnectionChange $deviceId, $isConnected ${error != null ? 'Error: $error' : ''}',
    );
    setState(() {
      print(
        '_handleConnectionChange $deviceId, ${bleDevice!.deviceId} ',
      );
      if (deviceId == bleDevice!.deviceId) {
        this.isConnected = isConnected;
      }
      if (this.isConnected) {
        _discoverServices();
      }
    });
    _addLog('Connection', isConnected ? "Connected" : "Disconnected");
    // Auto Discover Services
  }

  void dataConversion4(String rawStr) {
    List<String> rawStrAry = rawStr.split('_');

    double w = combine(rawStrAry[4], rawStrAry[5], 10000.0, 1);
    double x = combine(rawStrAry[6], rawStrAry[7], 10000.0, 2);
    double y = combine(rawStrAry[8], rawStrAry[9], 10000.0, 2);
    double z = combine(rawStrAry[10], rawStrAry[11], 10000.0, 2);
    double accx = combine(rawStrAry[12], rawStrAry[13], 100.0, 2);
    double accy = combine(rawStrAry[14], rawStrAry[15], 100.0, 2);
    double accz = combine(rawStrAry[16], rawStrAry[17], 100.0, 2);

    // Quaternion quatVal = Quaternion(
    //   combine(rawStrAry[4], rawStrAry[5], 10000.0, 4),
    //   combine(rawStrAry[6], rawStrAry[7], 10000.0, 1),
    //   combine(rawStrAry[8], rawStrAry[9], 10000.0, 2),
    //   combine(rawStrAry[10], rawStrAry[11], 10000.0, 3),
    // );

    accVect = Vector3(
      combine(rawStrAry[12], rawStrAry[13], 100.0, 5),
      combine(rawStrAry[14], rawStrAry[15], 100.0, 6),
      combine(rawStrAry[16], rawStrAry[17], 100.0, 7),
    );

    // accX = accVect.x;
    // accY = accVect.y;
    // accZ = accVect.z;

    double _roll = 0;
    double _pitch = 0, _yaw = 0;

    _roll = atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z));
    _yaw = asin(2 * (w * y - x * z));
    // y  = 2.0 * (q.w * q.y - q.x * q.z);
    _pitch = atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y));

    pitch = degreesFromRadians(_pitch); // pitch
    roll = degreesFromRadians(_yaw); // yaw
    yaw = degreesFromRadians(_roll);

    accX = accx;
    accY = accy;
    accZ = accz;
    String hex = rawStrAry[3];
    batteryVal = getBatteryPercentage(hex);
    if (mounted) {
      setState(() {});
    }

    // _addLog('Sensor data', "pitch _ $pitch , roll _  $roll , yaw _ $yaw" );
  }

  void updateHeartRateSendorData(int heartRate, int batteryval) {
    heartRateval = heartRate;
    heartRatesensorBatval = batteryval;
    if (mounted) {
      setState(() {});
    }
  }

  void _addLog(String type, dynamic data) {
    setState(() {
      _logs.clear();
      _logs.add('$type: ${data.toString()}');
    });
  }

  String getBatteryPercentage(String hex) {
    int decimalShot = int.parse(hex, radix: 16);
    int decimalInt = decimalShot;
    return "$decimalInt%";
  }

  double degreesFromRadians(double radians) {
    return radians * (180 / pi);
  }

  double combine(
      String first, String second, double mapConstantVal, int index) {
    String hex = first + second;
    int decimalInt = int.parse(hex, radix: 16);
    if (decimalInt > 0x7FFF) {
      decimalInt -= 0x10000;
    }
    double x = decimalInt / mapConstantVal;
    // debugPrint("Combine log === ${x} --- ${first} , ${ second} --- ${index}");
    return x /*decimalInt / mapConstantVal*/;
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

  void _handlePairingStateChange(String deviceId, bool isPaired) {
    print('isPaired $deviceId, $isPaired');
    _addLog("PairingStateChange - isPaired", isPaired);
  }

  Future<void> _setBleInputProperty(BleInputProperty inputProperty) async {
    if (readCharacteristic == null) return;
    try {
      if (inputProperty != BleInputProperty.disabled) {
        // List<CharacteristicProperty> properties =
        //     selectedCharacteristic!.characteristic.properties;
        List<CharacteristicProperty> properties =
            readCharacteristic!.properties;
        if (properties.contains(CharacteristicProperty.notify)) {
          inputProperty = BleInputProperty.notification;
        } else if (properties.contains(CharacteristicProperty.indicate)) {
          inputProperty = BleInputProperty.indication;
        } else {
          throw 'No notify or indicate property';
        }
      }
      await UniversalBle.setNotifiable(
        bleDevice!.deviceId,
        ServiceUUID,
        readCharacteristic!.uuid,
        inputProperty,
      );
      _addLog('BleInputProperty', inputProperty);
    } catch (e) {
      _addLog('NotifyError', e);
    }
  }

  Future<void> _discoverServices() async {
    const webWarning =
        "Note: Only services added in ScanFilter or WebOptions will be discovered";
    try {
      var services = await UniversalBle.discoverServices(bleDevice!.deviceId);
      print('${services.length} services discovered');
      print(services);

      // Here i filtered the service UUID for application

      final List<BleService> filteredServices = services
          .where((service) =>
              service.uuid == "6e400001-b5a3-f393-e0a9-e50e24dcca9e")
          .toList();

      discoveredServices.clear();
      setState(() {
        discoveredServices = filteredServices /*services*/;
      });

      if (discoveredServices.isNotEmpty) {
        discoveredServices.forEach((service) {
          service.characteristics.forEach((characteristic) {
            debugPrint("Character ${characteristic.uuid}");
            debugPrint("Character ${characteristic.properties}");
            List<CharacteristicProperty> properties = characteristic.properties;
            if (characteristic.uuid == WriteCharacteristicUUID) {
              if (properties.contains(CharacteristicProperty.write) ||
                  properties
                      .contains(CharacteristicProperty.writeWithoutResponse)) {
                writeCharacteristic = characteristic;
                debugPrint(
                    "writeCharacteristic---- ${writeCharacteristic!.uuid}");
              }
            }
            //
            if (characteristic.uuid == NotifyCharacteristicUUID || /*&&*/
                (characteristic.properties
                    .contains(CharacteristicProperty.notify))) {
              readCharacteristic = characteristic;
            }
          });
        });

        // final BleService bleService = filteredServices.first;

        // Extract the write characteristic
        // writeCharacteristic = bleService.characteristics.firstWhere(
        //       (char) => char.properties.contains("write") || char.properties.contains("writeWithoutResponse"),
        // orElse: () => BleCharacteristic(uuid: "", properties: []), // Default empty characteristic
        // );

        // Extract the notify characteristic
        // readCharacteristic = bleService.characteristics.firstWhere(
        //       (char) => char.properties.contains("notify"),
        //   // orElse: () => BleCharacteristic(uuid: "", properties: []), // Default empty characteristic
        // );

        // Debug print
        print("Write Characteristic UUID: ${writeCharacteristic!.uuid}");
        print("Notify Characteristic UUID: ${readCharacteristic!.uuid}");
      }

      if (kIsWeb) {
        _addLog(
          "DiscoverServices",
          '${services.length} services discovered,\n$webWarning',
        );
      }
    } catch (e) {
      _addLog("DiscoverServicesError", '$e\n${kIsWeb ? webWarning : ""}');
    }
  }

  /*Future<void> _readValue() async {
    if (selectedCharacteristic == null) return;
    try {
      Uint8List value = await UniversalBle.readValue(
        widget.deviceId,
        selectedCharacteristic!.service.uuid,
        selectedCharacteristic!.characteristic.uuid,
      );
      String s = String.fromCharCodes(value);
      String data = '$s\nraw :  ${value.toString()}';
      _addLog('Read', data);
    } catch (e) {
      _addLog('ReadError', e);
    }
  }*/

  List<int> _getRandomBytes() {
    // debugPrint("Sensor write is called === ");
    return createRequestFrame();
    // final math = Random();
    // return [math.nextInt(255), math.nextInt(255), math.nextInt(255), math.nextInt(255)];
  }

  /*List<int>*/
  Uint8List createRequestFrame() {
    Uint8List reqFrame = Uint8List(20);

    // Set specific values at particular indices
    reqFrame[0] = 0x53;
    reqFrame[1] = 0x31;
    reqFrame[19] = 0x4E;
    List<int> intList = reqFrame.toList();

    // debugPrint("Sensor write is called === ");

    return reqFrame /*intList*/;
  }

  Future<void> _writeValue() async {
    // if (selectedCharacteristic == null ||
    //     !valueFormKey.currentState!.validate() ||
    //     binaryCode.text.isEmpty) {
    //   return;
    // }

    Uint8List value;
    try {
      // value = Uint8List.fromList(hex.decode(binaryCode.text));
      value = createRequestFrame();
    } catch (e) {
      _addLog('WriteError', "Error parsing hex $e");
      return;
    }

    try {
      // await UniversalBle.writeValue(
      //   bleDevice!.deviceId,
      //   selectedCharacteristic!.service.uuid,
      //   selectedCharacteristic!.characteristic.uuid,
      //   value,
      //   _hasSelectedCharacteristicProperty(
      //       [CharacteristicProperty.writeWithoutResponse])
      //       ? BleOutputProperty.withoutResponse
      //       : BleOutputProperty.withResponse,
      // );

      await UniversalBle.writeValue(bleDevice!.deviceId, ServiceUUID,
          WriteCharacteristicUUID, value, BleOutputProperty.withoutResponse);
      _addLog('Write', value);

      if (readCharacteristic != null) {
        _setBleInputProperty(BleInputProperty.notification);
      }
    } catch (e) {
      print(e);
      _addLog('WriteError', e);
    }
  }

  bool _hasSelectedCharacteristicProperty(
      List<CharacteristicProperty> properties) {
    if (writeCharacteristic != null) {
      return properties.any((property) =>
          writeCharacteristic!.properties.contains(property) ?? false);
    }
    return false;
  }

  /* @override
  Widget build(BuildContext context) {
    List<ManufacturerData> rawManufacturerData =
        widget.bleDevice.manufacturerDataList;
    ManufacturerData? manufacturerData;
    if (rawManufacturerData.isNotEmpty) {
      manufacturerData = rawManufacturerData.first;
    }
    if (name == null || name!.isEmpty) name = 'N/A';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Card(
        child: ListTile(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '$name (${widget.bleDevice!.rssi})',
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(width: 8),
                  // PlatformButton(
                  //   // text: 'Connect - ${bleDevice!.deviceId} ',
                  //   text: 'Connect',
                  //   enabled: !isConnected,
                  //   onPressed: () async {
                  //     try {
                  //       await UniversalBle.connect(
                  //         bleDevice!.deviceId,
                  //       );
                  //       _addLog("ConnectionResult", true);
                  //     } catch (e) {
                  //       _addLog('ConnectError (${e.runtimeType})', e);
                  //     }
                  //   },
                  // ),
                  // const SizedBox(width: 8),
                  // PlatformButton(
                  //   text: 'Disconnect',
                  //   enabled: isConnected,
                  //   onPressed: () {
                  //     UniversalBle.disconnect(widget.bleDevice!.deviceId);
                  //   },
                  // ),
                  // const SizedBox(width: 8),
                  // PlatformButton(
                  //   enabled: isConnected &&
                  //       discoveredServices.isNotEmpty &&
                  //       _hasSelectedCharacteristicProperty([
                  //         CharacteristicProperty.write,
                  //         CharacteristicProperty.writeWithoutResponse
                  //       ]),
                  //   onPressed: _writeValue,
                  //   text: 'Write',
                  // ),
                  // Text(
                  //   'Pitch = $pitch , YAW = $yaw, ROLL = $roll Battery = $batteryVal',
                  //   overflow: TextOverflow.ellipsis,
                  // ),
                  Expanded(
                    child: Column(
                      children: [
                      Text(
                        'Pitch = $pitch',
                        overflow: TextOverflow.ellipsis,
                      ),
                        Text(
                          'YAW = $yaw',
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'ROLL = $roll ',
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Battery = $batteryVal',
                          overflow: TextOverflow.ellipsis,
                        ),

                      ],
                    ),

                    // Text(
                    //   'Pitch = $pitch , YAW = $yaw, ROLL = $roll Battery = $batteryVal',
                    //   overflow: TextOverflow.ellipsis,
                    // ),
                  )
                ],
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(bleDevice!.deviceId),
              Visibility(
                visible: manufacturerData != null,
                child: Text(manufacturerData.toString()),
              ),
              PlatformButton(
                // text: 'Connect - ${bleDevice!.deviceId} ',
                text: 'Connect',
                enabled: !isConnected,
                onPressed: () async {
                  try {
                    await UniversalBle.connect(
                      bleDevice!.deviceId,
                    );
                    _addLog("ConnectionResult", true);
                  } catch (e) {
                    _addLog('ConnectError (${e.runtimeType})', e);
                  }
                },
              ),
              const SizedBox(width: 8),
              if (*/ /*widget.bleDevice?.isPaired */ /* isConnected == true)
                const Text(
                  "Connected",
                  style: TextStyle(color: Colors.green),
                )
              else
                const Text(
                  "Not Connected",
                  style: TextStyle(color: Colors.red),
                ),
            ],
          ),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: widget.onTap,
        ),
      ),
    );
  }*/

  @override
  Widget build(BuildContext context) {
    List<ManufacturerData> rawManufacturerData =
        widget.bleDevice.manufacturerDataList;
    ManufacturerData? manufacturerData;
    if (rawManufacturerData.isNotEmpty) {
      manufacturerData = rawManufacturerData.first;
    }
    if (name == null || name!.isEmpty) name = 'N/A';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column: Sensor name, MAC, Connect button, Status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$name (${widget.bleDevice!.rssi})',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'MAC: ${bleDevice!.deviceId}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    PlatformButton(
                      text: 'Connect',
                      enabled: !isConnected,
                      onPressed: () async {
                        try {
                          await UniversalBle.connect(bleDevice!.deviceId);
                          _addLog("ConnectionResult", true);
                        } catch (e) {
                          _addLog('ConnectError (${e.runtimeType})', e);
                        }
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isConnected ? "Connected" : "Not Connected",
                      style: TextStyle(
                        color: isConnected ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Right Column: Pitch, Yaw, Roll, Battery

              if (widget.isHeartRateSensor!) ...{
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Heart Rate : $heartRateval',
                          overflow: TextOverflow.ellipsis),
                      Text('Battery   : $heartRatesensorBatval',
                          overflow: TextOverflow.ellipsis),

                    ],
                  ),
                ),
              },

              if (!widget.isHeartRateSensor!) ...{
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pitch: $pitch', overflow: TextOverflow.ellipsis),
                      Text('Yaw: $yaw', overflow: TextOverflow.ellipsis),
                      Text('Roll: $roll', overflow: TextOverflow.ellipsis),
                      Text('Battery: $batteryVal',
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              },
            ],
          ),
        ),
      ),
    );
    ;
  }
}
