import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart'; // For coordinates
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:safe_roads/models/user_preferences.dart';
import 'package:safe_roads/notifications.dart';

class NavigationPage extends StatefulWidget {
  final Map<String, List<Map<String, dynamic>>> routesWithPoints;
  final String selectedRouteKey; // Default value, updated when routes are fetched
  final List<Map<String, dynamic>> routeCoordinates;
  final Map<String, String> distances;
  final Map<String, String> times;

  const NavigationPage(this.routesWithPoints, this.selectedRouteKey, this.routeCoordinates, this.distances, this.times, {super.key});

  @override
  _NavigationPageState createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  late String selectedRouteKey;
  late List<Map<String, dynamic>> routeCoordinates;
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
  bool keepRoute = true;
  Set<LatLng> passedSegments = {}; // Store segments already passed
  int consecutiveOffRouteCount = 0; // Track how many times user is "off-route"
  int offRouteThreshold = 7; // Require 7 consecutive off-route detections
  bool lastOnRouteState = true; // Track last known on-route state
  bool _startRiskNotificationSent = false; // Track if the initial notification was sent
  List<dynamic> notifiedDivergences = [];


  // Extract LatLng safely
  LatLng _getLatLngFromMap(Map<String, dynamic> map) {
    return LatLng(map['latlng'].latitude, map['latlng'].longitude);
  }

  @override
  void initState() {
    super.initState();
    selectedRouteKey = widget.selectedRouteKey; // Set initial route from Home.dart
    routeCoordinates = widget.routesWithPoints[selectedRouteKey] ?? [];
    location = Location();

    // Assign the callback to handle rerouting
    _notifications.onSwitchRoute = switchToAdjustedRoute;
    _notifications.ignoreSwitchRoute = keepDefaultRoute;

    _initializeLocation();

    print("widget.time, ${widget.times[selectedRouteKey]}");
    _calculateArrivalTime(widget.times[selectedRouteKey] ?? "0 min");

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

        if(selectedRouteKey == "defaultRoute"){
          _checkReRoute();
        }
        _checkRiskZone(); 

        // Extract last coordinate safely
        LatLng lastPoint = _getLatLngFromMap(routeCoordinates.last);
        
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
        // Uri.parse('http://10.101.120.162:3000/update-position'),    // Para testar na uni

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

    // Set animation flag to true before starting the animation
    if (!mounted) return; // Early return if the widget is no longer in the tree
    setState(() {
      isAnimating = true;
    });

    for (int i = 1; i <= steps; i++) {
      await Future.delayed(duration);

      // Check if the widget is still mounted before calling setState
      if (!mounted) return; // Stop animation if widget is disposed

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

    // Final position and animation end state
    if (!mounted) return; // Ensure widget is still mounted before finishing the animation
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

    final userPreferences = Provider.of<UserPreferences>(context, listen: false);
    String alertDistance = userPreferences.alertDistance; // Get the user's preference

    // Convert string to a double in meters
    double alertDistanceThreshold = _convertAlertDistance(alertDistance);
    print("alertDistanceThreshold $alertDistanceThreshold");

    // const double alertDistanceThreshold = 150.0; // Notify before entering risk zone
    const double routeDeviationThreshold = 50.0;  // Detect wrong route
    const Distance distance = Distance();

    bool isOnRoute = false;
    int highestUpcomingRisk = 0;
    int currentRiskLevel = 0;
    LatLng? riskPoint;

    Set<LatLng> detectedRiskZone = {}; 

    for (var segment in routeCoordinates) {
      if (segment['latlng'] is! LatLng || segment['raster_value'] == null) continue;

      LatLng point = segment['latlng'];
      double distanceToPoint = distance(currentPosition!, point);
      int riskValue = segment['raster_value'];

      // Skip segments already passed
      if (passedSegments.contains(point)) continue;

      // Check if user is on the route (more stable check)
      if (distanceToPoint < routeDeviationThreshold) {
        isOnRoute = true;
      }

      // Update current risk level
      if (distanceToPoint < routeDeviationThreshold && riskValue > currentRiskLevel) {
        currentRiskLevel = riskValue;
      }

      // Detect new high-risk zone ahead
      if (distanceToPoint < alertDistanceThreshold && riskValue > 2) {
        if (riskValue > highestUpcomingRisk) {
          highestUpcomingRisk = riskValue;
          riskPoint = point;
        }
        detectedRiskZone.add(point);
      }
    }

    if (!_startRiskNotificationSent && currentRiskLevel > 2 && isOnRoute && riskPoint != null) {
      _sendInitialRiskWarning(riskPoint, currentRiskLevel);
      _startRiskNotificationSent = true; // Mark notification as sent
    }

    // Prevent sudden flips between "on-route" and "off-route"
    if (isOnRoute) {
      consecutiveOffRouteCount = 0; // Reset counter if back on track
    } else {
      consecutiveOffRouteCount++; // Count how many times user is "off-route"
    }

    bool confirmedOffRoute = consecutiveOffRouteCount >= offRouteThreshold;

    // Only send off-route warning if user was previously on route and now confirmed off-route
    if (confirmedOffRoute && lastOnRouteState) {
      _sendOffRouteWarning();
    }

    lastOnRouteState = !confirmedOffRoute; // Update last known state

    // Only Notify if Moving into a New High-Risk Zone
    bool enteringNewRiskZone = highestUpcomingRisk > 2 && highestUpcomingRisk > currentRiskLevel;

    if (enteringNewRiskZone && riskPoint != null && isOnRoute) {
      bool alreadyNotified = detectedRiskZone.any((p) => notifiedZones.contains(p));

      if (!alreadyNotified) {
        _sendRiskWarning(riskPoint, highestUpcomingRisk);
        notifiedZones.addAll(detectedRiskZone); // Mark entire zone as notified
      }

      _inRiskZone = true;
      print("_inRiskZone: $_inRiskZone, currentRiskLevel: $currentRiskLevel, highestUpcomingRisk: $highestUpcomingRisk");
    }

    // Mark Passed Segments
    if (currentRiskLevel > 2) {
      passedSegments.addAll(detectedRiskZone);
    }

    // Update _inRiskZone
    _inRiskZone = currentRiskLevel > 2;
  }

  
  // Function to map string values to double values
  double _convertAlertDistance(String distance) {
    switch (distance) {
      case "100 m":
        return 100.0;
      case "500 m":
        return 500.0;
      case "1 km":
        return 1000.0; // Convert km to meters
      default:
        return 200.0; // Default value if no match is found
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
        // Uri.parse('http://10.101.120.162:3000/send'),    // Para testar na uni
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "fcmToken": _notifications.fcmToken,
          "title": title,
          "body": body,
          "button": "false",
        }),
      );

      if (response.statusCode == 200) {
        print("Risk alert sent successfully: $title");
      }
    } catch (e) {
      print("Error sending risk alert: $e");
    }
  }

  void _sendInitialRiskWarning(LatLng riskPoint, int riskValue) async {
    if (notifiedZones.contains(riskPoint)) return;
    notifiedZones.add(riskPoint);

    String title;
    String body;

    // Define notification message based on risk level
    if (riskValue > 3) {
      title = "🚨 High Amphibian Risk!";
      body = "Be careful! You are in a high risk of amphibians ahead.";
    } else {
      title = "⚠️ Caution: Amphibian Presence";
      body = "Be careful! Medium risk of amphibians right here.";
    }

    try {
      final response = await http.post(
        Uri.parse('http://192.168.1.82:3000/send'),
        // Uri.parse('http://10.101.120.162:3000/send'),    // Para testar na uni
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "fcmToken": _notifications.fcmToken,
          "title": title,
          "body": body,
          "button": "false",
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
    } else if (DateTime.now().difference(lastWarningTime!) < const Duration(seconds: 30)) {
        return; // Skip if it's been less than 30 seconds
    }

    lastWarningTime = DateTime.now(); // Update timestamp after sending the warning

    try {
      await http.post(
        Uri.parse('http://192.168.1.82:3000/send'),
        // Uri.parse('http://10.101.120.162:3000/send'),    // Para testar na uni
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "fcmToken": _notifications.fcmToken,
          "title": "🔃 Wrong Route!",
          "body": "You are off the planned route.",
          "button": "false",
        }),
      );
    } catch (e) {
      print("Error sending off-route warning: $e");
    }
  }

  void _checkReRoute() {
    if (currentPosition == null || widget.routesWithPoints.isEmpty) return;

    List<Map<String, dynamic>> defaultRoute = widget.routesWithPoints['defaultRoute'] ?? [];
    List<Map<String, dynamic>> adjustedRoute = widget.routesWithPoints['adjustedRoute'] ?? [];

    if (defaultRoute.isEmpty || adjustedRoute.isEmpty) return;

    const double alertThreshold = 250.0; // Notify before divergence
    const Distance distance = Distance();

    List<LatLng> divergencePoints = [];

    // Identify all divergence points along the routes
    bool previouslyDiverged = false;
    for (int i = 0; i < min(defaultRoute.length, adjustedRoute.length); i++) {
        LatLng defaultPoint = _getLatLngFromMap(defaultRoute[i]);
        LatLng adjustedPoint = _getLatLngFromMap(adjustedRoute[i]);

        if (!_arePointsClose(defaultPoint, adjustedPoint, threshold: 30.0)) {
            if (!previouslyDiverged) {
                divergencePoints.add(defaultPoint); // Save divergence point
                previouslyDiverged = true; // Mark as diverged
            }
        } else {
            previouslyDiverged = false; // Mark as converged
        }
    }

    if (divergencePoints.isEmpty) return; // No divergences found

    // Find the next upcoming divergence
    for (LatLng divergencePoint in divergencePoints) {
        double distanceToDivergence = distance(currentPosition!, divergencePoint);

        if (distanceToDivergence < alertThreshold && !notifiedDivergences.contains(divergencePoint)) {
            _sendReRouteNotification();
            notifiedDivergences.add(divergencePoint); // Mark this divergence as notified
            break; // Stop after notifying the first upcoming divergence
        }
    }
  }

  bool _arePointsClose(LatLng p1, LatLng p2, {double threshold = 30.0}) {
      const Distance distance = Distance();
      return distance(p1, p2) < threshold; // Check if points are close enough
  }

  void _sendReRouteNotification() async {
    if (lastWarningTime == null) {
        lastWarningTime = DateTime.now(); // Initialize for the first time
    } else if (DateTime.now().difference(lastWarningTime!) < const Duration(seconds: 30)) {
        return; // Skip if it's been less than 30 seconds
    }

    lastWarningTime = DateTime.now(); // Update timestamp after sending the warning

    try {
      await http.post(
        Uri.parse('http://192.168.1.82:3000/send'),
        // Uri.parse('http://10.101.120.162:3000/send'),    // Para testar na uni
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "fcmToken": _notifications.fcmToken,
          "title": "🚧 Alternative Route Recommended!",
          "body": "The alternative route has less risk. Consider changing the route.",
          "button": "true"
        }),
      );
    } catch (e) {
      print("Erro ao enviar notificação de re-rota: $e");
    }
  }

  void switchToAdjustedRoute() {
    setState(() {
      keepRoute = false;
      selectedRouteKey = "adjustedRoute";
      routeCoordinates = widget.routesWithPoints[selectedRouteKey] ?? [];
    });

    if (routeCoordinates.isNotEmpty) {
      _mapController.move(_getLatLngFromMap(routeCoordinates.first), 19.0);
    }

    print("Switched to Adjusted Route!");
  }

  void keepDefaultRoute(){
    setState(() {
      keepRoute = true;      
    });
    print("Kept following Default Route!");
  }


  @override
  void dispose() {
    // Cancel location updates
    locationSubscription?.cancel();
    
    //Reset current position to null if needed
    // setState(() {
    //   currentPosition = null;
    // });

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
                  initialCenter: currentPosition ?? _getLatLngFromMap(routeCoordinates.first), 
                  initialZoom: 19.0,
                  initialRotation: bearing, // Set initial rotation
                ),
                children: [
                  TileLayer(
                    urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                    subdomains: const ['a', 'b', 'c'],
                  ),
                  PolylineLayer(
                    polylines: List.generate(routeCoordinates.length - 1, (index) {
                      final current = routeCoordinates[index];
                      final next = routeCoordinates[index + 1];

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
                    Navigator.of(context, rootNavigator: true).pop();
                  }
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
                            widget.distances[selectedRouteKey]!,
                            style: const TextStyle(
                              fontSize: 22.0,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(width: 30),
                          Text(
                            widget.times[selectedRouteKey]!,
                            style: const TextStyle(
                              fontSize: 22.0,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
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
                      SizedBox(height: 20),
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
