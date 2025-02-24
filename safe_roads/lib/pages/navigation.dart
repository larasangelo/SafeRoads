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
  final List<Map<String, dynamic>> routeCoordinates;
  final String distance;
  final String time;

  const NavigationPage(this.routeCoordinates, this.distance, this.time, {super.key});

  @override
  _NavigationPageState createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  final Notifications _notifications = Notifications();
  late Location location;
  LatLng? currentPosition;
  LatLng? previousPosition;
  double bearing = 0.0; // For map rotation
  StreamSubscription<LocationData>? locationSubscription;
  final MapController _mapController = MapController();
  bool isFirstLocationUpdate = true;
  String estimatedArrivalTime = "??:??"; // To display the arrival time
  bool isAnimating = false; // To prevent overlapping animations
  bool _destinationReached = false;
  Set<LatLng> notifiedZones = {}; // Track notified risk zones
  bool _inRiskZone = false;
  DateTime? lastWarningTime; // Move this outside the function to persist the value

  // Extract LatLng safely
  LatLng _getLatLngFromMap(Map<String, dynamic> map) {
    return LatLng(map['latlng'].latitude, map['latlng'].longitude);
  }

  @override
  void initState() {
    super.initState();
    location = Location();

    _initializeLocation();

    print("widget.time, ${widget.time}");
    _calculateArrivalTime(widget.time);

    locationSubscription = location.onLocationChanged.listen((LocationData loc) {
      if (loc.latitude != null && loc.longitude != null) {
        LatLng newPosition = LatLng(loc.latitude!, loc.longitude!);

        if (previousPosition != null && !isAnimating) {
          _animateMarker(previousPosition!, newPosition);
        } else {
          setState(() {
            previousPosition = currentPosition;
            currentPosition = newPosition;
          });

          if (isFirstLocationUpdate) {
            _mapController.moveAndRotate(currentPosition!, 19.0, bearing);
            isFirstLocationUpdate = false;
          }
        }

        _checkRiskZone(); 

        // Extract last coordinate safely
        LatLng lastPoint = _getLatLngFromMap(widget.routeCoordinates.last);
        
        if ((currentPosition!.latitude - lastPoint.latitude).abs() < 0.0001 &&
            (currentPosition!.longitude - lastPoint.longitude).abs() < 0.0001) {
          setState(() {
            _destinationReached = true;
          });
        }
      }
    });
  }

  Future<void> _initializeLocation() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    // NOTIFICATIONS TEST
    await _notifications.setupFirebaseMessaging(); 

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
    final initialLocation = await location.getLocation();
    setState(() {
      currentPosition = LatLng(initialLocation.latitude!, initialLocation.longitude!);
    });
  }

  void _calculateArrivalTime(String travelTime) {
    try {
      DateTime now = DateTime.now();
      int totalMinutes = 0;

      // Define regex to capture time units like "4 min" or "1h 30min"
      final regex = RegExp(r'(\d+)\s*(h|min)');
      final matches = regex.allMatches(travelTime);

      for (final match in matches) {
        int value = int.tryParse(match.group(1)!) ?? 0; 
        String unit = match.group(2)!.toLowerCase(); 

        if (unit == 'h') {
          totalMinutes += value * 60; 
        } else if (unit == 'min') {
          totalMinutes += value; 
        }
      }

      if (totalMinutes == 0) {
        print("Invalid travel time format.");
        return;
      }

      DateTime arrivalTime = now.add(Duration(minutes: totalMinutes));

      // Format the time in 24-hour format (e.g., 13:45)
      String formattedTime = "${arrivalTime.hour.toString().padLeft(2, '0')}:${arrivalTime.minute.toString().padLeft(2, '0')}";

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
        // Uri.parse('http://10.101.121.132:3000/update-position'),    // Para testar na uni

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
  
  void _animateMarker(LatLng start, LatLng end) async {
    const int steps = 20; // Number of steps for smooth animation
    const duration = Duration(milliseconds: 50); // Time per step

    double deltaLat = (end.latitude - start.latitude) / steps;
    double deltaLon = (end.longitude - start.longitude) / steps;

    setState(() {
      isAnimating = true;
    });

    for (int i = 1; i <= steps; i++) {
      await Future.delayed(duration);

      LatLng intermediatePosition = LatLng(
        start.latitude + (deltaLat * i),
        start.longitude + (deltaLon * i),
      );

      setState(() {
        previousPosition = currentPosition;
        currentPosition = intermediatePosition;

        if (previousPosition != null) {
          bearing = _calculateBearing(previousPosition!, currentPosition!);
        }
      });

      _mapController.moveAndRotate(intermediatePosition, 19.0, bearing);
    }

    setState(() {
      isAnimating = false;
      previousPosition = end; // Ensure the final position is set
    });
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

  void _checkRiskZone() async {
    if (currentPosition == null || _notifications.fcmToken == null || _notifications.fcmToken!.isEmpty) return;

    const double alertDistanceThreshold = 150.0; // Notify before entering risk zone
    const double routeDeviationThreshold = 50.0;  // Detect wrong route
    const Distance distance = Distance();

    bool isOnRoute = false;
    int highestUpcomingRisk = 0; // Highest upcoming risk level
    int currentRiskLevel = 0; // Current risk level user is in
    LatLng? riskPoint; // Store the point where risk is detected

    for (var segment in widget.routeCoordinates) {
      if (segment['latlng'] is! LatLng || segment['raster_value'] == null) continue;

      LatLng point = segment['latlng'];
      double distanceToPoint = distance(currentPosition!, point);
      int riskValue = segment['raster_value'];

      // Check if user is on the route
      if (distanceToPoint < routeDeviationThreshold) {
        isOnRoute = true;
      }

      // Determine the current risk level based on proximity
      if (distanceToPoint < routeDeviationThreshold && riskValue > currentRiskLevel) {
        currentRiskLevel = riskValue;
      }

      // Identify the highest risk in the upcoming path
      if (distanceToPoint < alertDistanceThreshold && riskValue > 2) {
        if (riskValue > highestUpcomingRisk) {
          highestUpcomingRisk = riskValue;
          riskPoint = point;
        }
      }
    }

    // Check if we need to send a risk notification:
    // - If moving from Safe (<=2) → Medium (3) OR High (=>4) → Notify
    // - If moving from Medium (3) → High (=>4) → Notify
    // - If already in High Risk (=>4), don't notify again
    if (highestUpcomingRisk > 2 && highestUpcomingRisk > currentRiskLevel && riskPoint != null && isOnRoute) {
      _sendRiskWarning(riskPoint, highestUpcomingRisk);
      _inRiskZone = true; // Mark user as inside a risk zone
    }

    // Update _inRiskZone only if in Medium or High risk zones
    _inRiskZone = currentRiskLevel > 2;

    print("_inRiskZone: $_inRiskZone, currentRiskLevel: $currentRiskLevel, highestUpcomingRisk: $highestUpcomingRisk");
    print("isOnRoute: $isOnRoute");

    // Send off-route warning
    if (!isOnRoute) {
      _sendOffRouteWarning();
    }
  }

  void _sendRiskWarning(LatLng riskPoint, int riskValue) async {
    if (notifiedZones.contains(riskPoint)) return;
    notifiedZones.add(riskPoint);

    String title;
    String body;

    // Define notification message based on risk level
    if (riskValue > 3) {
      title = "🚨 High Amphibian Risk!";
      body = "Slow down! High risk of amphibians ahead.";
    } else {
      title = "⚠️ Caution: Amphibian Presence";
      body = "Be careful! Medium risk of amphibians nearby.";
    }

    try {
      final response = await http.post(
        Uri.parse('http://192.168.1.82:3000/send'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "fcmToken": _notifications.fcmToken,
          "title": title,
          "body": body,
        }),
      );

      if (response.statusCode == 200) {
        print("Risk alert sent successfully: $title");
      }
    } catch (e) {
      print("Error sending risk alert: $e");
    }
  }

  void _sendOffRouteWarning() async {
    if (lastWarningTime == null) {
        lastWarningTime = DateTime.now(); // Initialize for the first time
    } else if (DateTime.now().difference(lastWarningTime!) < Duration(seconds: 30)) {
        return; // Skip if it's been less than 30 seconds
    }

    lastWarningTime = DateTime.now(); // Update timestamp after sending the warning

    try {
      await http.post(
        Uri.parse('http://192.168.1.82:3000/send'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "fcmToken": _notifications.fcmToken,
          "title": "🔃 Wrong Route!",
          "body": "You are off the planned route.",
        }),
      );
    } catch (e) {
      print("Error sending off-route warning: $e");
    }
  }

  @override
  void dispose() {
    // Cancel location updates
    locationSubscription?.cancel();
    
    // Optional: Reset current position to null if needed
    setState(() {
      currentPosition = null;
    });

    print("NavigationPage disposed. Stopping location updates and clearing resources.");
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _notifications.scaffoldMessengerKey,
      home: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              if (currentPosition != null)
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: currentPosition ?? _getLatLngFromMap(widget.routeCoordinates.first), 
                  initialZoom: 19.0,
                  initialRotation: bearing, // Set initial rotation
                ),
                children: [
                  TileLayer(
                    urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                    subdomains: const ['a', 'b', 'c'],
                  ),
                  PolylineLayer(
                    polylines: List.generate(widget.routeCoordinates.length - 1, (index) {
                      final current = widget.routeCoordinates[index];
                      final next = widget.routeCoordinates[index + 1];

                      if (current['latlng'] is! LatLng || next['latlng'] is! LatLng) return null;

                      // Determine color based on raster value
                      Color lineColor;
                      if (current['raster_value'] != null) {
                        if (current['raster_value'] > 3) {
                          lineColor = Colors.red; // High risk
                        } else if (current['raster_value'] > 2) {
                          lineColor = Colors.orange; // Medium risk
                        } else {
                          lineColor = Colors.purple; // Default color
                        }
                      } else {
                        lineColor = Colors.purple; // Fallback color if raster_value is missing
                      }

                      return Polyline(
                        points: [current['latlng'] as LatLng, next['latlng'] as LatLng],
                        strokeWidth: 8.0,
                        color: lineColor,
                      );
                    }).whereType<Polyline>().toList(), // Filters out null values
                  ),
                  MarkerLayer(
                    markers: [
                      if (currentPosition != null)
                        Marker(
                          point: currentPosition!,
                          child: const Icon(
                            Icons.my_location, 
                            color: Colors.red,
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
              if(!_destinationReached)
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
                    ],
                  ),
                ),
              ),
              if(_destinationReached)
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
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Destination Reached!",
                        style: TextStyle(
                          fontSize: 30.0,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(height: 20), // Add some spacing
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
