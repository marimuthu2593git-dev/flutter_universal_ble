// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_universal_ble_poc_sample/peripheral_details/widgets/result_widget.dart';
import 'package:flutter_universal_ble_poc_sample/peripheral_details/widgets/services_list_widget.dart';
import 'package:universal_ble/universal_ble.dart';

import '../widgets/platform_button.dart';
import '../widgets/responsive_buttons_grid.dart';
import '../widgets/responsive_view.dart';

import 'package:vector_math/vector_math_64.dart'
    show Quaternion, Vector3, degrees, Matrix3;

class PeripheralDetailPage extends StatefulWidget {
  final String deviceId;
  final String deviceName;
  const PeripheralDetailPage(this.deviceId, this.deviceName, {Key? key})
      : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _PeripheralDetailPageState();
  }
}

class _PeripheralDetailPageState extends State<PeripheralDetailPage> {
  bool isConnected = false;
  GlobalKey<FormState> valueFormKey = GlobalKey<FormState>();
  List<BleService> discoveredServices = [];
  final List<String> _logs = [];
  final binaryCode = TextEditingController();

  Vector3 accVect = Vector3.zero();
  Vector3 curAngle = Vector3.zero();

  double pitch = 0, yaw = 0, roll = 0;
  double calibPitch = 0, calibYaw = 0, calibRoll = 0;
  double accX = 0, accY = 0, accZ = 0;
  String batteryVal = "";

  BleCharacteristic? writeCharacteristic;
  BleCharacteristic? readCharacteristic;

  ({
    BleService service,
    BleCharacteristic characteristic
  })? selectedCharacteristic;


  @override
  void initState() {
    super.initState();
    UniversalBle.onConnectionChange = _handleConnectionChange;
    UniversalBle.onValueChange = _handleValueChange;
    UniversalBle.onPairingStateChange = _handlePairingStateChange;
  }

  @override
  void dispose() {
    super.dispose();
    UniversalBle.onConnectionChange = null;
    UniversalBle.onValueChange = null;
    // Disconnect when leaving the page
    if (isConnected) UniversalBle.disconnect(widget.deviceId);
  }

  void _addLog(String type, dynamic data) {
    setState(() {
      _logs.clear();
      _logs.add('$type: ${data.toString()}');
    });
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
      if (deviceId == widget.deviceId) {
        this.isConnected = isConnected;
      }
    });
    _addLog('Connection', isConnected ? "Connected" : "Disconnected");
    // Auto Discover Services
    if (this.isConnected) {
      _discoverServices();
    }
  }

  void _handleValueChange(
      String deviceId, String characteristicId, Uint8List value) {
    String s = String.fromCharCodes(value);
    String data = '$s\nraw :  ${value.toString()}';
    List<int> _sensorvalue = value.toList();
    String hexString = bytesToHex(_sensorvalue);
    dataConversion4(/*_value*/ hexString);
    print('_handleValueChange $hexString');
    // print('_handleValueChange $deviceId, $characteristicId, $s');
    // _addLog("Value", _sensorvalue);
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

    _addLog('Sensor data', "pitch _ $pitch , roll _  $roll , yaw _ $yaw" );

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

  Future<void> _discoverServices() async {
    const webWarning =
        "Note: Only services added in ScanFilter or WebOptions will be discovered";
    try {
      var services = await UniversalBle.discoverServices(widget.deviceId);
      print('${services.length} services discovered');
      print(services);

      // Here i filtered the service UUID for application

      final List<BleService> filteredServices = services
          .where((service) => service.uuid == "6e400001-b5a3-f393-e0a9-e50e24dcca9e")
          .toList();


      discoveredServices.clear();
      setState(() {
        discoveredServices = filteredServices /*services*/;
      });

      if (discoveredServices.isNotEmpty) {
        final BleService bleService = filteredServices.first;

        // Extract the write characteristic
        writeCharacteristic = bleService.characteristics.firstWhere(
              (char) => char.properties.contains("write") || char.properties.contains("writeWithoutResponse"),
          // orElse: () => BleCharacteristic(uuid: "", properties: []), // Default empty characteristic
        );

        // Extract the notify characteristic
        readCharacteristic = bleService.characteristics.firstWhere(
              (char) => char.properties.contains("notify"),
          // orElse: () => BleCharacteristic(uuid: "", properties: []), // Default empty characteristic
        );

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

  Future<void> _readValue() async {
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
  }

  List<int> _getRandomBytes() {
    // debugPrint("Sensor write is called === ");
    return createRequestFrame();
    // final math = Random();
    // return [math.nextInt(255), math.nextInt(255), math.nextInt(255), math.nextInt(255)];
  }

  /*List<int>*/ Uint8List createRequestFrame() {
    Uint8List reqFrame = Uint8List(20);

    // Set specific values at particular indices
    reqFrame[0] = 0x53;
    reqFrame[1] = 0x31;
    reqFrame[19] = 0x4E;
    List<int> intList = reqFrame.toList();

    // debugPrint("Sensor write is called === ");

    return reqFrame/*intList*/;
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
      await UniversalBle.writeValue(
        widget.deviceId,
        selectedCharacteristic!.service.uuid,
        selectedCharacteristic!.characteristic.uuid,
        value,
        _hasSelectedCharacteristicProperty(
                [CharacteristicProperty.writeWithoutResponse])
            ? BleOutputProperty.withoutResponse
            : BleOutputProperty.withResponse,
      );
      _addLog('Write', value);
    } catch (e) {
      print(e);
      _addLog('WriteError', e);
    }
  }

  Future<void> _setBleInputProperty(BleInputProperty inputProperty) async {
    if (selectedCharacteristic == null) return;
    try {
      if (inputProperty != BleInputProperty.disabled) {
        List<CharacteristicProperty> properties =
            selectedCharacteristic!.characteristic.properties;
        if (properties.contains(CharacteristicProperty.notify)) {
          inputProperty = BleInputProperty.notification;
        } else if (properties.contains(CharacteristicProperty.indicate)) {
          inputProperty = BleInputProperty.indication;
        } else {
          throw 'No notify or indicate property';
        }
      }
      await UniversalBle.setNotifiable(
        widget.deviceId,
        selectedCharacteristic!.service.uuid,
        selectedCharacteristic!.characteristic.uuid,
        inputProperty,
      );
      _addLog('BleInputProperty', inputProperty);
    } catch (e) {
      _addLog('NotifyError', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.deviceName} - ${widget.deviceId}"),
        elevation: 4,
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
              color: isConnected ? Colors.greenAccent : Colors.red,
              size: 20,
            ),
          )
        ],
      ),
      body: ResponsiveView(builder: (_, DeviceType deviceType) {
        return Row(
          children: [
            if (deviceType == DeviceType.desktop)
              Expanded(
                flex: 1,
                child: Container(
                  color: Theme.of(context).secondaryHeaderColor,
                  child: discoveredServices.isEmpty
                      ? const Center(
                          child: Text('No Services Discovered'),
                        )
                      : ServicesListWidget(
                          discoveredServices: discoveredServices,
                          scrollable: true,
                          onTap: (BleService service,
                              BleCharacteristic characteristic) {

                            print("Selected cahracteristic === $characteristic");
                            setState(() {
                              selectedCharacteristic = (
                                service: service,
                                characteristic: characteristic
                              );
                            });
                          },
                        ),
                ),
              ),
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Top buttons
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: <Widget>[
                            PlatformButton(
                              text: 'Connect',
                              enabled: !isConnected,
                              onPressed: () async {
                                try {
                                  await UniversalBle.connect(
                                    widget.deviceId,
                                  );
                                  _addLog("ConnectionResult", true);
                                } catch (e) {
                                  _addLog('ConnectError (${e.runtimeType})', e);
                                }
                              },
                            ),
                            PlatformButton(
                              text: 'Disconnect',
                              enabled: isConnected,
                              onPressed: () {
                                UniversalBle.disconnect(widget.deviceId);
                              },
                            ),
                          ],
                        ),
                      ),
                      selectedCharacteristic == null
                          ? Text(discoveredServices.isEmpty
                              ? "Please discover services"
                              : "Please select a characteristic")
                          : Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
                              child: Card(
                                child: ListTile(
                                  title: SelectableText(
                                    "Characteristic: ${selectedCharacteristic!.characteristic.uuid}",
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SelectableText(
                                        "Service: ${selectedCharacteristic!.service.uuid}",
                                      ),
                                      Text(
                                        "Properties: ${selectedCharacteristic!.characteristic.properties.map((e) => e.name)}",
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                      if (_hasSelectedCharacteristicProperty([
                        CharacteristicProperty.write,
                        CharacteristicProperty.writeWithoutResponse
                      ]))
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Form(
                            key: valueFormKey,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: TextFormField(
                                controller: binaryCode,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter a value';
                                  }
                                  try {
                                    hex.decode(binaryCode.text);
                                    return null;
                                  } catch (e) {
                                    return 'Please enter a valid hex value ( without spaces or 0x (e.g. F0BB) )';
                                  }
                                },
                                decoration: const InputDecoration(
                                  hintText:
                                      "Enter Hex values without spaces or 0x (e.g. F0BB)",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ResponsiveButtonsGrid(
                          children: [
                            PlatformButton(
                              onPressed: () async {
                                _discoverServices();
                              },
                              enabled: isConnected,
                              text: 'Discover Services',
                            ),
                            PlatformButton(
                              onPressed: () async {
                                _addLog(
                                  'ConnectionState',
                                  await UniversalBle.getConnectionState(
                                    widget.deviceId,
                                  ),
                                );
                              },
                              text: 'Connection State',
                            ),
                            if (BleCapabilities.supportsRequestMtuApi)
                              PlatformButton(
                                enabled: isConnected,
                                onPressed: () async {
                                  int mtu = await UniversalBle.requestMtu(
                                      widget.deviceId, 247);
                                  _addLog('MTU', mtu);
                                },
                                text: 'Request Mtu',
                              ),
                            PlatformButton(
                              enabled: isConnected &&
                                  discoveredServices.isNotEmpty &&
                                  _hasSelectedCharacteristicProperty([
                                    CharacteristicProperty.read,
                                  ]),
                              onPressed: _readValue,
                              text: 'Read',
                            ),
                            PlatformButton(
                              enabled: isConnected &&
                                  discoveredServices.isNotEmpty &&
                                  _hasSelectedCharacteristicProperty([
                                    CharacteristicProperty.write,
                                    CharacteristicProperty.writeWithoutResponse
                                  ]),
                              onPressed: _writeValue,
                              text: 'Write',
                            ),
                            PlatformButton(
                              enabled: isConnected &&
                                  discoveredServices.isNotEmpty &&
                                  _hasSelectedCharacteristicProperty([
                                    CharacteristicProperty.notify,
                                    CharacteristicProperty.indicate
                                  ]),
                              onPressed: () => _setBleInputProperty(
                                  BleInputProperty.notification),
                              text: 'Subscribe',
                            ),
                            PlatformButton(
                              enabled: isConnected &&
                                  discoveredServices.isNotEmpty &&
                                  _hasSelectedCharacteristicProperty([
                                    CharacteristicProperty.notify,
                                    CharacteristicProperty.indicate
                                  ]),
                              onPressed: () => _setBleInputProperty(
                                  BleInputProperty.disabled),
                              text: 'Unsubscribe',
                            ),
                            PlatformButton(
                              enabled: BleCapabilities.supportsAllPairingKinds,
                              onPressed: () async {
                                try {
                                  await UniversalBle.pair(
                                    widget.deviceId,
                                    // pairingCommand: BleCommand(
                                    //   service: "",
                                    //   characteristic: "",
                                    // ),
                                  );
                                  _addLog("Pairing Result", true);
                                } catch (e) {
                                  _addLog('PairError (${e.runtimeType})', e);
                                }
                              },
                              text: 'Pair',
                            ),
                            PlatformButton(
                              onPressed: () async {
                                bool? isPaired = await UniversalBle.isPaired(
                                  widget.deviceId,
                                  // pairingCommand: BleCommand(
                                  //   service: "",
                                  //   characteristic: "",
                                  // ),
                                );
                                _addLog('IsPaired', isPaired);
                              },
                              text: 'IsPaired',
                            ),
                            PlatformButton(
                              onPressed: () async {
                                await UniversalBle.unpair(widget.deviceId);
                              },
                              text: 'Unpair',
                            ),
                          ],
                        ),
                      ),
                      // Services
                      if (deviceType != DeviceType.desktop)
                        ServicesListWidget(
                          discoveredServices: discoveredServices,
                          onTap: (BleService service,
                              BleCharacteristic characteristic) {
                            setState(() {
                              selectedCharacteristic = (
                                service: service,
                                characteristic: characteristic
                              );
                            });
                          },
                        ),
                      const Divider(),
                      ResultWidget(
                          results: _logs,
                          onClearTap: (int? index) {
                            setState(() {
                              if (index != null) {
                                _logs.removeAt(index);
                              } else {
                                _logs.clear();
                              }
                            });
                          }),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  bool _hasSelectedCharacteristicProperty(
          List<CharacteristicProperty> properties) =>
      properties.any((property) =>
          selectedCharacteristic?.characteristic.properties
              .contains(property) ??
          false);
}
