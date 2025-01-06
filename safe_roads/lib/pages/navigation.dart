import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart'; // For coordinates
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'package:safe_roads/notifications.dart';

class NavigationPage extends StatefulWidget {
  final List<LatLng> routeCoordinates;
  final String distance;
  final String time;

  const NavigationPage(this.routeCoordinates, this.distance, this.time, {super.key});

  @override
  _NavigationPageState createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  // final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final Notifications _notifications = Notifications();
  late Location location;
  LatLng? currentPosition;
  LatLng? previousPosition;
  double bearing = 0.0; // For map rotation
  StreamSubscription<LocationData>? locationSubscription;
  final MapController _mapController = MapController();
  bool isFirstLocationUpdate = true;
  String estimatedArrivalTime = "??:??"; // To display the arrival time

  @override
  void initState() {
    super.initState();
    location = Location();

    _initializeLocation();

    // Calculate the estimated arrival time
    _calculateArrivalTime(widget.time);

    // Start tracking location
    locationSubscription = location.onLocationChanged.listen((LocationData loc) {
      if (loc.latitude != null && loc.longitude != null) {
        LatLng newPosition = LatLng(loc.latitude!, loc.longitude!);

        setState(() {
          if (previousPosition != null) {
            // Calculate bearing between previous and current position
            // bearing = _calculateBearing(previousPosition!, newPosition);
          }
          previousPosition = currentPosition;
          currentPosition = newPosition;

          // print("previousPosition: $previousPosition");
          // print("newPosition: $newPosition");
        });

        if (isFirstLocationUpdate) {
          // Center the map on the initial position and set rotation
          _mapController.moveAndRotate(currentPosition!, 19.0, bearing);
          isFirstLocationUpdate = false;
        } else {
          // Smoothly pan to the updated position with rotation
          _mapController.moveAndRotate(currentPosition!, 19.0, bearing);
        }

        _sendPositionToServer(loc.latitude!, loc.longitude!);
      }
    });
  }

  Future<void> _initializeLocation() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    // NOTIFICATIONS TEST
    await _notifications.setupFirebaseMessaging(); 

    if (_notifications.fcmToken!.isNotEmpty) {
      print("fcmToken: ${_notifications.fcmToken}");

      // Send the token to the server
      try {
        final response = await http.post(
          Uri.parse('http://192.168.1.82:3000/send'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "fcmToken": _notifications.fcmToken,
            "title": "Attention: Risk zone!",
            "body": "High probability of encountering amphibians!",
          }),
        );

        if (response.statusCode == 200) {
          print("Token sent successfully");
        } else {
          print("Failed to send token: ${response.statusCode}");
        }
      } catch (e) {
        print("Error sending token to server: $e");
      }
    } else {
      print("FCM Token is not available");
    }

    // Check if location services are enabled
    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        return;
      }
    }

    // Check if permission is granted
    permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        return;
      }
    }

    // Get the initial location
    // final initialLocation = await location.getLocation();
    setState(() {
      // currentPosition = LatLng(initialLocation.latitude!, initialLocation.longitude!);
      currentPosition = const LatLng(38.902464, -9.163266); // Test with coordinates of Ribas de Baixo

    });
    }

  void _calculateArrivalTime(String travelTimeInMinutes) {
    try {
      // Get the current time
      DateTime now = DateTime.now();

      // Parse the travel time from the provided string
      int travelMinutes = int.tryParse(travelTimeInMinutes) ?? 0;

      // Add travel minutes to the current time
      DateTime arrivalTime = now.add(Duration(minutes: travelMinutes));

      // Format the time in 24-hour format (e.g., 13:45)
      String formattedTime = "${arrivalTime.hour.toString().padLeft(2, '0')}:${arrivalTime.minute.toString().padLeft(2, '0')}";

      // Update the state
      setState(() {
        estimatedArrivalTime = formattedTime;
      });
    } catch (e) {
      print("Error calculating arrival time: $e");
    }
  }


  Future<void> _sendPositionToServer(double lat, double lon) async {
    try {
      await http.post(
        Uri.parse('http://192.168.1.82:3000/update-position'),
        body: {
          // 'userId': '123', // Example user ID
          'lat': lat.toString(),
          'lon': lon.toString(),
        },
      );
    } catch (e) {
      print("Error sending position: $e");
    }
  }

  @override
  void dispose() {
    locationSubscription?.cancel();
    super.dispose();
  }

  // Calculate the bearing between two LatLng points
  double _calculateBearing(LatLng start, LatLng end) {
    double lat1 = start.latitudeInRad;
    double lon1 = start.longitudeInRad;
    double lat2 = end.latitudeInRad;
    double lon2 = end.longitudeInRad;

    double dLon = lon2 - lon1;

    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);

    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _notifications.scaffoldMessengerKey,
      home: Scaffold(
        // appBar: AppBar(title: const Text("Navigation")),
        body: SafeArea(
          child: Stack(
            children: [
              if (currentPosition != null)
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: currentPosition ?? widget.routeCoordinates.first,
                  initialZoom: 20.0,
                  initialRotation: bearing, // Set initial rotation
                ),
                children: [
                  TileLayer(
                    urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                    subdomains: const ['a', 'b', 'c'],
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: widget.routeCoordinates,
                        strokeWidth: 8.0,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                  // if (currentPosition != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: currentPosition!,
                          child: const Icon(
                            Icons.my_location, // Use a static icon
                            color: Colors.blue,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              Positioned(
                top: 20,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 40),
                  onPressed: () {
                    Navigator.pop(context); // Stop navigation and return to the previous page
                  },
                )
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 120,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.rectangle,
                    // borderRadius: BorderRadius.vertical(
                    //   top: Radius.circular(30.0),
                    // ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        estimatedArrivalTime,
                        style: const TextStyle(
                          fontSize: 30.0,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.distance,
                            style: const TextStyle(
                              fontSize: 22.0,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(width: 30), // Add some spacing
                          Text(
                            widget.time,
                            style: const TextStyle(
                              fontSize: 22.0,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20), // Add some spacing
                      // ElevatedButton(
                      //   onPressed: () {
                      //     Navigator.pop(context); // Stop navigation and return to the previous page
                      //   },
                      //   child: const Text(
                      //     "Stop",
                      //     style: TextStyle(fontSize: 18.0),
                      //   ),
                      // ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
