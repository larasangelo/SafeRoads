import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;

class MapPage extends StatefulWidget {
  const MapPage({Key? key}) : super(key: key);

  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  String? fcmToken;
  final MapController _mapController = MapController();
  LocationData? _currentLocation;
  LatLng? _destinationLocation;
  List<LatLng> _routePoints = [];
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  Future<void> _requestLocationPermission() async {
  // Request location permissions first
  Location location = Location();

  bool serviceEnabled = await location.serviceEnabled();
  if (!serviceEnabled) {
    serviceEnabled = await location.requestService();
    if (!serviceEnabled) return;
  }

  PermissionStatus permissionGranted = await location.hasPermission();
  if (permissionGranted == PermissionStatus.denied) {
    permissionGranted = await location.requestPermission();
    if (permissionGranted != PermissionStatus.granted) return;
  }

  // Fetch location if permission is granted
  _currentLocation = await location.getLocation();
  setState(() {
    if (_currentLocation != null) {
      _routePoints = [
        LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!)
      ];
      _mapController.move(
        LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
        13.0,
      );
    }
  });

  // Setup Firebase messaging only after requesting location permissions
  await _setupFirebaseMessaging();
}

Future<void> _setupFirebaseMessaging() async {
    NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print("Notification permission granted");

      fcmToken = await FirebaseMessaging.instance.getToken();
      print("FCM Token: $fcmToken");

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print("Foreground message received: ${message.notification?.title}");
        _showForegroundNotification(message);
      });
    } else {
      print("Notification permission denied");
    }
}

void _showForegroundNotification(RemoteMessage message) {
    if (message.notification != null) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text("${message.notification!.title}: ${message.notification!.body}"),
        ),
      );
    }
  }
// Paste the _MapPageState class here from your current code
// Ensure that any imports required are adjusted appropriately
 void _setDestination() async {
    if (_latController.text.isNotEmpty && _lngController.text.isNotEmpty) {
      final double lat = double.parse(_latController.text);
      final double lng = double.parse(_lngController.text);

      setState(() {
        _destinationLocation = LatLng(lat, lng);
        _routePoints = [
          LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
          _destinationLocation!,
        ];
      });
      _mapController.move(_destinationLocation!, 13.0);

      // Send push notification
      if (fcmToken != null) {
        await _sendPushNotification(fcmToken!);
      }
    }
  }

  Future<void> _sendPushNotification(String fcmToken) async {
    const serverUrl = 'http://192.168.1.82:3000/send'; 
    try {
      final response = await http.post(
        Uri.parse(serverUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"fcmToken": fcmToken}),
      );
      if (response.statusCode == 200) {
        print("Notification sent successfully");
      } else {
        print("Failed to send notification: ${response.body}");
      }
    } catch (e) {
      print("Error sending token to server: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: Scaffold(
        appBar: AppBar(title: const Text("Safe Roads")),
        body: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(0, 0), // Placeholder; updated when location is fetched
                initialZoom: 13.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  subdomains: ['a', 'b', 'c'],
                ),
                if (_currentLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
                        child: const Icon(Icons.location_pin, color: Colors.blue, size: 40),
                      ),
                    ],
                  ),
                if (_destinationLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _destinationLocation!,
                        child: const Icon(Icons.location_pin, color: Colors.red, size: 40),
                      ),
                    ],
                  ),
                if (_routePoints.length == 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 4.0,
                        color: Colors.blue,
                      ),
                    ],
                  ),
              ],
            ),
            Positioned(
              top: 40.0,
              left: 10.0,
              right: 10.0,
              child: Column(
                children: [
                  TextField(
                    controller: _latController,
                    decoration: const InputDecoration(
                      labelText: "Destination Latitude",
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8.0),
                  TextField(
                    controller: _lngController,
                    decoration: const InputDecoration(
                      labelText: "Destination Longitude",
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8.0),
                  ElevatedButton(
                    onPressed: _setDestination,
                    child: const Text("Set Destination"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
