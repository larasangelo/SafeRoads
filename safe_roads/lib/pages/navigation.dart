import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart'; 
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:safe_roads/configuration/language_config.dart';
import 'package:safe_roads/configuration/navigation_config.dart';
import 'package:safe_roads/models/notification_preferences.dart';
import 'package:safe_roads/models/user_preferences.dart';
import 'package:safe_roads/notifications.dart';

class NavigationPage extends StatefulWidget {
  final Map<String, List<Map<String, dynamic>>> routesWithPoints;
  final String selectedRouteKey; // Default value, updated when routes are fetched
  final List<Map<String, dynamic>> routeCoordinates;
  final Map<String, String> distances;
  final Map<String, String> times;
  final String? formattedTime;
  final LatLng? initialPosition;

  const NavigationPage(
    this.routesWithPoints,
    this.selectedRouteKey,
    this.routeCoordinates,
    this.distances,
    this.times, 
    this.formattedTime, {
    this.initialPosition,
    super.key,
  });

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> with WidgetsBindingObserver{
  late String selectedRouteKey;
  late List<Map<String, dynamic>> routeCoordinates;
  final Notifications _notifications = NavigationConfig.notifications;
  late Location location;
  LatLng? currentPosition;
  LatLng? previousPosition;
  double bearing = NavigationConfig.bearing; // For map rotation
  StreamSubscription<LocationData>? locationSubscription;
  late MapController _mapController;
  bool isFirstLocationUpdate = NavigationConfig.isFirstLocationUpdate;
  String estimatedArrivalTime = NavigationConfig.estimatedArrivalTime; // To display the arrival time
  bool isAnimating = NavigationConfig.isAnimating; // To prevent overlapping animations
  bool _destinationReached = NavigationConfig.destinationReached;
  Set<LatLng> notifiedZones = NavigationConfig.notifiedZones; // Track notified risk zones
  bool inRiskZone = NavigationConfig.inRiskZone;
  DateTime? lastWarningTime; // Move this outside the function to persist the value
  bool keepRoute = NavigationConfig.keepRoute;
  Set<LatLng> passedSegments = NavigationConfig.passedSegments; // Store segments already passed
  int consecutiveOffRouteCount = NavigationConfig.consecutiveOffRouteCount; // Track how many times user is "off-route"
  int offRouteThreshold = NavigationConfig.offRouteThreshold; // Require 7 consecutive off-route detections
  bool lastOnRouteState = NavigationConfig.lastOnRouteState; // Track last known on-route state
  bool _startRiskNotificationSent = NavigationConfig.startRiskNotificationSent; // Track if the initial notification was sent
  List<dynamic> notifiedDivergences = NavigationConfig.notifiedDivergences;
  bool _firstRiskDetected = NavigationConfig.firstRiskDetected;
  bool enteringNewRiskZone = NavigationConfig.enteringNewRiskZone;
  bool isOnRoute = NavigationConfig.isOnRoute;
  double highestUpcomingRisk = NavigationConfig.highestUpcomingRisk;
  double currentRiskLevel = NavigationConfig.currentRiskLevel;
  Set<LatLng> detectedRiskZones = NavigationConfig.detectedRiskZones;  
  Map<LatLng, double> upcomingRisks = NavigationConfig.upcomingRisks; // Store multiple risk points
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  bool _destinationReachedNotif = false;

  // Extract LatLng safely
  LatLng _getLatLngFromMap(Map<String, dynamic> map) {
    return LatLng(map['latlng'].latitude, map['latlng'].longitude);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Update the context whenever the widget rebuilds
    _notifications.setContext(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
  }

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    // Reset NavigationConfig values
    NavigationConfig.isFirstLocationUpdate = true;
    NavigationConfig.estimatedArrivalTime = "";
    NavigationConfig.isAnimating = false;
    NavigationConfig.destinationReached = false;
    NavigationConfig.notifiedZones.clear();
    NavigationConfig.inRiskZone = false;
    NavigationConfig.keepRoute = false;
    NavigationConfig.passedSegments.clear();
    NavigationConfig.consecutiveOffRouteCount = 0;
    NavigationConfig.lastOnRouteState = true;
    NavigationConfig.startRiskNotificationSent = false;
    NavigationConfig.notifiedDivergences.clear();
    NavigationConfig.firstRiskDetected = false;
    NavigationConfig.enteringNewRiskZone = false;
    NavigationConfig.isOnRoute = false;
    NavigationConfig.highestUpcomingRisk = 0;
    NavigationConfig.currentRiskLevel = 0;
    NavigationConfig.detectedRiskZones.clear();  
    NavigationConfig.upcomingRisks.clear(); 
    
    // print("enteringNewRiskZone: $enteringNewRiskZone");
    // print("NavigationConfig.enteringNewRiskZone: ${NavigationConfig.enteringNewRiskZone}");
    // print("NavigationConfig.upcomingRisks: ${NavigationConfig.upcomingRisks}");

    super.initState();
    selectedRouteKey = widget.selectedRouteKey; // Set initial route from Home.dart
    routeCoordinates = widget.routesWithPoints[selectedRouteKey] ?? [];
    location = Location();
    _mapController = MapController();

    // Assign the callback to handle rerouting
    _notifications.onSwitchRoute = switchToAdjustedRoute;
    _notifications.ignoreSwitchRoute = keepDefaultRoute;

    _initializeLocation();
    if (widget.initialPosition != null) {
      currentPosition = widget.initialPosition;
    }

    locationSubscription = location.onLocationChanged.listen((LocationData loc) async {
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
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (currentPosition != null) {
                _mapController.moveAndRotate(currentPosition!, NavigationConfig.cameraZoom, bearing);
                isFirstLocationUpdate = false;
              }
            });
          }
        }

        if(selectedRouteKey == "defaultRoute"){
          _checkReRoute();
        }
        _checkRiskZone(); 

        // Extract last coordinate safely
        LatLng lastPoint = _getLatLngFromMap(routeCoordinates.last);
        
        if ((currentPosition!.latitude - lastPoint.latitude).abs() < NavigationConfig.threshold &&
            (currentPosition!.longitude - lastPoint.longitude).abs() < NavigationConfig.threshold) {
          setState(() {
            _destinationReached = true;
          });

          if (_appLifecycleState != AppLifecycleState.resumed && !_destinationReachedNotif && mounted) { //TODO: VER SE MANDA A NOTIFICAÇÃO QUANDO CHEGA AO FIM
            String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
            await http.post(
              Uri.parse('https://ecoterra.rd.ciencias.ulisboa.pt/send'),
              // Uri.parse('http://192.168.1.82:3000/send'),
              // Uri.parse('http://10.101.120.44:3000/send'),    // Para testar na uni
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({
                "fcmToken": _notifications.fcmToken,
                "title": LanguageConfig.getLocalizedString(languageCode, 'destinationReached'),
                "body": LanguageConfig.getLocalizedString(languageCode, 'destinationReachedBody'),
                "button": "false",
                "changeRoute": "false"
              }),
            );
            setState(() {
                _destinationReachedNotif = true;
              });
          }
        }
      }
    });
  }

  // Update the preference globally using Provider
  Future<void> updateMessageSubscription(StreamSubscription<RemoteMessage> newValue) async {
    // Use Provider to update the messageSubscription value
    context.read<NotificationPreferences>().updateMessageSubscription(newValue);
  }

  Future<void> _initializeLocation() async {
    final notificationPreferences = Provider.of<NotificationPreferences>(context, listen: false);
    StreamSubscription<RemoteMessage>? messageSubscription = notificationPreferences.messageSubscription; 

    StreamSubscription<RemoteMessage>? result = await _notifications.setupFirebaseMessaging(context, messageSubscription); 
    updateMessageSubscription(result!);

    // -------------------- TESTE NO DISPOSITIVO FÍSICO ------------------------
      // print("Vou enviar a msg de TESTE");
      // String title = "🚨 TESTE!";
      // String body = "Isto é um teste para o dispositivo móvel.";

      // try {
      //   final response = await http.post(
      //     Uri.parse('https://ecoterra.rd.ciencias.ulisboa.pt/send'),
      //    // Uri.parse('http://192.168.1.82:3000/send'),
      //    // Uri.parse('http://10.101.120.44:3000/send'),    // Para testar na uni
      //     headers: {"Content-Type": "application/json"},
      //     body: jsonEncode({
      //       "fcmToken": _notifications.fcmToken,
      //       "title": title,
      //       "body": body,
      //       "button": "true",
      //       "changeRoute": "false"
      //     }),
      //   );

      //   if (response.statusCode == 200) {
      //     print("Risk alert sent successfully: $title");
      //   }
      // } catch (e) {
      //   print("Error sending risk alert: $e");
      // }
    // ------------------------------------------------------------------------
  }
  
  void _animateMarker(LatLng start, LatLng end) async {
    int steps = NavigationConfig.animationSteps; // Number of steps for smooth animation
    Duration duration = Duration(milliseconds: NavigationConfig.timePerStep); // Time per step

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
    String riskAlertDistance = userPreferences.riskAlertDistance;

    double alertDistanceThreshold = _convertAlertDistance(riskAlertDistance);
    double routeDeviationThreshold = NavigationConfig.routeDeviationThreshold;
    const Distance distance = Distance();

    for (var segment in routeCoordinates) {
      if (segment['latlng'] is! LatLng || segment['raster_value'] == null) continue;

      LatLng point = segment['latlng'];
      double distanceToPoint = distance(currentPosition!, point);
      double riskValue = (segment['raster_value'] as num).toDouble();

      if (passedSegments.contains(point)) continue;

      if (distanceToPoint < routeDeviationThreshold) {
        isOnRoute = true;
      }

      if (distanceToPoint < routeDeviationThreshold && riskValue > currentRiskLevel) {
        currentRiskLevel = riskValue;
      }

      bool withinAlertDistance = distanceToPoint < alertDistanceThreshold;

      if (withinAlertDistance && riskValue > NavigationConfig.mediumRisk) {
        upcomingRisks[point] = riskValue;  // Store all upcoming risk values
        detectedRiskZones.add(point);
        if (riskValue > highestUpcomingRisk || highestUpcomingRisk == 0) {
          highestUpcomingRisk = riskValue;
        }
      }
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

    String currentRiskCategory = getRiskCategory(currentRiskLevel);

    // Process all upcoming risk points (instead of just the highest)
    for (var entry in upcomingRisks.entries) {
      LatLng riskPoint = entry.key;
      double riskValue = entry.value;
      String upcomingRiskCategory = getRiskCategory(riskValue);

      // We need to extract the species list for the current risk point
      // Find the segment that corresponds to the current risk point
      var segment = routeCoordinates.firstWhere(
        (seg) =>
            seg['latlng'].latitude == riskPoint.latitude &&
            seg['latlng'].longitude == riskPoint.longitude,
      );

      List<dynamic> speciesList = segment['species']; // Extract species list for the current risk point
      // print("speciesList: $speciesList");

      if (!_firstRiskDetected && !_startRiskNotificationSent && currentRiskLevel > 0.5 && isOnRoute) {
        _sendInitialRiskWarning(riskPoint, currentRiskLevel, List<dynamic>.from(speciesList));
        _startRiskNotificationSent = true; // Mark notification as sent
        _firstRiskDetected = true;
      }

      if ((currentRiskCategory == "Low" && upcomingRiskCategory == "Medium") ||
          (currentRiskCategory == "Low" && upcomingRiskCategory == "High") ||
          (currentRiskCategory == "Medium" && upcomingRiskCategory == "High")) {
        enteringNewRiskZone = true;
        // print('ele volta a entrar no if e diz que enteringNewRiskZone = $enteringNewRiskZone');
      }

      print("enteringNewRiskZone: $enteringNewRiskZone, highestUpcomingRisk: $highestUpcomingRisk, currentRiskLevel: $currentRiskLevel");

      if (!enteringNewRiskZone) continue; // Skip if not transitioning to a new risk

      Set<LatLng> connectedRiskZone = _findConnectedRiskZone(riskPoint, upcomingRiskCategory);

      print("Connected Risk Zone Size: ${connectedRiskZone.length}");
      // print("connectedRiskZone, $connectedRiskZone");
      // print("notifiedZones, $notifiedZones");

      if (connectedRiskZone.difference(notifiedZones).isNotEmpty) {
        print("🔔 Sending notification for risk at $riskPoint (Risk Level: $riskValue)");
        // print("connectedRiskZone, $connectedRiskZone");
        // print("notifiedZones, $notifiedZones");
        _sendRiskWarning(riskPoint, riskValue, List<dynamic>.from(speciesList)); // Pass species list here
        notifiedZones.addAll(connectedRiskZone);
      } else {
        print("⚠️ Risk already notified: Skipping notification for $riskPoint");
      }
    }

    if (currentRiskLevel > NavigationConfig.mediumRisk) {
      passedSegments.addAll(detectedRiskZones);
    }

    inRiskZone = currentRiskLevel > NavigationConfig.mediumRisk;
  }

  // Determine risk category
  String getRiskCategory(double riskLevel) {
    if (riskLevel < NavigationConfig.mediumRisk) return "Low";
    if (riskLevel >= NavigationConfig.mediumRisk && riskLevel < NavigationConfig.highRisk) return "Medium";
    return "High";
  }

  // Find all connected segments in the same risk category
  Set<LatLng> _findConnectedRiskZone(LatLng startPoint, String riskCategory) {
    Set<LatLng> connectedZone = {};
    Queue<LatLng> queue = Queue();

    // Define the threshold for different risk categories
    double threshold;
    if (riskCategory == "Medium") {
      threshold = NavigationConfig.mediumRisk;
    } else if (riskCategory == "High") {
      threshold = NavigationConfig.highRisk;
    } else {
      threshold = double.infinity; 
    }

    // Initialize with the startPoint
    connectedZone.add(startPoint);
    queue.add(startPoint);

    // Find the starting point index in routeCoordinates
    int startIndex = routeCoordinates.indexWhere((segment) {
      return segment['latlng'] == startPoint;
    });

    if (startIndex == -1) {
      // If startPoint is not found, return an empty set or handle error
      return connectedZone; 
    }

    // Now, iterate through the routeCoordinates from the startPoint onward
    for (int i = startIndex; i < routeCoordinates.length; i++) {
      var segment = routeCoordinates[i];
      
      if (segment['latlng'] is! LatLng || segment['raster_value'] == null) continue;

      LatLng point = segment['latlng'];
      double riskValue = segment['raster_value'];
      String segmentCategory = getRiskCategory(riskValue);

      // Skip points that are below the threshold
      if (riskValue < threshold) {
        return connectedZone;  // Stop adding points once we hit a risk value below threshold
      }

      // Only add points that are connected and belong to the same category
      if (!connectedZone.contains(point) && segmentCategory == riskCategory) {
        connectedZone.add(point);
        queue.add(point);
      }
    }

    return connectedZone;
  }

  // Function to map string values to double values
  double _convertAlertDistance(String distance) {
    switch (distance) {
      case "100 m":
        return 100.0;
      case "250 m":
        return 250.0;
      case "500 m":
        return 500.0;
      case "1 km":
        return 1000.0; // Convert km to meters
      default:
        return 200.0; // Default value if no match is found
    }
  }

  void _sendRiskWarning(LatLng riskPoint, double riskValue, List<dynamic> speciesList) async {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    // print("riskPoint: $riskPoint, riskValue: $riskValue, speciesList: $speciesList");
    notifiedZones.add(riskPoint);
    _firstRiskDetected = true;

    String title;
    String body;

    List<String> translatedSpecies = speciesList.map(
      (species) => LanguageConfig.getLocalizedString(languageCode, species)
    ).toList();

    // Create a comma-separated string of species names
    String speciesNames = translatedSpecies.join(", ");

    // Define notification message based on risk level
    if (riskValue > NavigationConfig.highRisk) {
      title = "${LanguageConfig.getLocalizedString(languageCode, 'highRiskMsgTitle')}: $speciesNames!";
      body = "${LanguageConfig.getLocalizedString(languageCode, 'highRiskMsgBody')}: $speciesNames. ${LanguageConfig.getLocalizedString(languageCode, 'stayAlert')}";
    } else {
      title = "${LanguageConfig.getLocalizedString(languageCode, 'mediumRiskMsgTitle')}: $speciesNames ${LanguageConfig.getLocalizedString(languageCode, 'atRisk')}";
      body = "${LanguageConfig.getLocalizedString(languageCode, 'mediumRiskMsgBody')}: $speciesNames. ${LanguageConfig.getLocalizedString(languageCode, 'caution')}";
    }

    try {
      final response = await http.post(
        Uri.parse('https://ecoterra.rd.ciencias.ulisboa.pt/send'),
        // Uri.parse('http://192.168.1.82:3000/send'),
        // Uri.parse('http://10.101.120.44:3000/send'),    // Para testar na uni
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "fcmToken": _notifications.fcmToken,
          "title": title,
          "body": body,
          "button": "false",
          "changeRoute": "false",
          "type": "warning",
        }),
      );

      if (response.statusCode == 200) {
        print("Risk alert sent successfully: $title");
      }
    } catch (e) {
      print("Error sending risk alert: $e");
    }
  }

  void _sendInitialRiskWarning(LatLng riskPoint, double riskValue, List<dynamic> speciesList) async {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    notifiedZones.add(riskPoint);

    String title;
    String body;

    List<String> translatedSpecies = speciesList.map(
      (species) => LanguageConfig.getLocalizedString(languageCode, species)
    ).toList();

    // Create a comma-separated string of species names
    String speciesNames = translatedSpecies.join(", ");

    // Define notification message based on risk level
    if (riskValue > NavigationConfig.highRisk) {
      title = "${LanguageConfig.getLocalizedString(languageCode, 'highRiskMsgTitle')}: $speciesNames!";
      body = "${LanguageConfig.getLocalizedString(languageCode, 'warning')}: $speciesNames. ${LanguageConfig.getLocalizedString(languageCode, 'caution')}";

    } else {
      title = "${LanguageConfig.getLocalizedString(languageCode, 'mediumRiskMsgTitle')}: $speciesNames ${LanguageConfig.getLocalizedString(languageCode, 'atRisk')}";
      body = "${LanguageConfig.getLocalizedString(languageCode, 'riskZoneHere')}: $speciesNames. ${LanguageConfig.getLocalizedString(languageCode, 'stayAlert')}";
    }

    try {
      final response = await http.post(
        Uri.parse('https://ecoterra.rd.ciencias.ulisboa.pt/send'),
        // Uri.parse('http://192.168.1.82:3000/send'),
        // Uri.parse('http://10.101.120.44:3000/send'),    // Para testar na uni
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "fcmToken": _notifications.fcmToken,
          "title": title,
          "body": body,
          "button": "false",
          "changeRoute": "false",
          "type": "warning",
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
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    if (lastWarningTime == null) {
        lastWarningTime = DateTime.now(); // Initialize for the first time
    } else if (DateTime.now().difference(lastWarningTime!) < const Duration(seconds: 30)) {
        return; // Skip if it's been less than 30 seconds
    }

    lastWarningTime = DateTime.now(); // Update timestamp after sending the warning

    try {
      await http.post(
        Uri.parse('https://ecoterra.rd.ciencias.ulisboa.pt/send'),
        // Uri.parse('http://192.168.1.82:3000/send'),
        // Uri.parse('http://10.101.120.44:3000/send'),    // Para testar na uni
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "fcmToken": _notifications.fcmToken,
          "title": LanguageConfig.getLocalizedString(languageCode, 'wrongRouteMsgTitle'),
          "body": LanguageConfig.getLocalizedString(languageCode, 'wrongRouteMsgBody'),
          "button": "false",
          "changeRoute": "false"
        }),
      );
    } catch (e) {
      print("Error sending off-route warning: $e");
    }
  }

  void _checkReRoute() {
    if (currentPosition == null || widget.routesWithPoints.isEmpty) return;

    final userPreferences = Provider.of<UserPreferences>(context, listen: false); // Get the user's preference
    String rerouteAlertDistance = userPreferences.rerouteAlertDistance; 
    bool changeRoute = userPreferences.changeRoute;

    // Convert string to a double in meters
    double alertThreshold = _convertAlertDistance(rerouteAlertDistance);

    List<Map<String, dynamic>> defaultRoute = widget.routesWithPoints['defaultRoute'] ?? [];
    List<Map<String, dynamic>> adjustedRoute = widget.routesWithPoints['adjustedRoute'] ?? [];

    if (defaultRoute.isEmpty || adjustedRoute.isEmpty) return;

    const Distance distance = Distance();

    List<LatLng> divergencePoints = [];

    // Identify all divergence points along the routes
    bool previouslyDiverged = false;
    for (int i = 0; i < min(defaultRoute.length, adjustedRoute.length); i++) {
      LatLng defaultPoint = _getLatLngFromMap(defaultRoute[i]);
      LatLng adjustedPoint = _getLatLngFromMap(adjustedRoute[i]);

      if (!_arePointsClose(defaultPoint, adjustedPoint, threshold: NavigationConfig.pointsCloseThreshold)) {
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
      // print("distanceToDivergence, $distanceToDivergence");

      if (distanceToDivergence < alertThreshold && !notifiedDivergences.contains(divergencePoint)) {
        _sendReRouteNotification(changeRoute);
        notifiedDivergences.add(divergencePoint); // Mark this divergence as notified
        break; // Stop after notifying the first upcoming divergence
      }
    }
  }

  bool _arePointsClose(LatLng p1, LatLng p2, {required double threshold} ) {
      const Distance distance = Distance();
      return distance(p1, p2) < threshold; // Check if points are close enough
  }

  void _sendReRouteNotification(bool changeRoute) async {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    if (lastWarningTime == null) {
      lastWarningTime = DateTime.now(); // Initialize for the first time
    } else if (DateTime.now().difference(lastWarningTime!) < Duration(seconds: NavigationConfig.reRouteReSend)) {
      return; // Skip if it's been less than 30 seconds
    }

    lastWarningTime = DateTime.now(); // Update timestamp after sending the warning

    try {
      // Identify the alternative route
      String alternativeRouteKey = widget.routesWithPoints.keys.firstWhere(
        (key) => key != selectedRouteKey, 
        orElse: () => ""
      );

      if (alternativeRouteKey.isEmpty) return; // No alternative route found

      // Get times for both routes
      String currentRouteTime = widget.times[selectedRouteKey] ?? "0";
      String alternativeRouteTime = widget.times[alternativeRouteKey] ?? "0";

      // Compare travel times
      String notificationBody;
      if (currentRouteTime == alternativeRouteTime) {
        notificationBody =
          LanguageConfig.getLocalizedString(languageCode, 'sameTimeMsg');
      } else {
        notificationBody =
          LanguageConfig.getLocalizedString(languageCode, 'changeRouteMsg');
      }
      print("Vou enviar ReRouteNotification");
      await http.post(
        Uri.parse('https://ecoterra.rd.ciencias.ulisboa.pt/send'),
        // Uri.parse('http://192.168.1.82:3000/send'),
        // Uri.parse('http://10.101.120.44:3000/send'),    // Para testar na uni
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "fcmToken": _notifications.fcmToken,
          "title": LanguageConfig.getLocalizedString(languageCode, 'altRouteTitle'),
          "body": notificationBody,
          "button": "true",
          "changeRoute": changeRoute.toString(),
          "type": "alternativeRoute",
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
      upcomingRisks.clear(); // Clear risks from the old route
      detectedRiskZones.clear();
      notifiedZones.clear(); // Optional depending on your logic
    });

    if (routeCoordinates.isNotEmpty) {
      _mapController.move(_getLatLngFromMap(routeCoordinates.first), NavigationConfig.cameraZoom);
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
    WidgetsBinding.instance.removeObserver(this);
    // Cancel location updates
    locationSubscription?.cancel();
    _mapController.dispose();
    
    print("NavigationPage disposed. Stopping location updates and clearing resources.");
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    
    // Get screen size to adjust layout
    double screenHeight = MediaQuery.of(context).size.height;
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Stack(
        children: [
          if (currentPosition != null)
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: currentPosition ?? _getLatLngFromMap(routeCoordinates.first),
                initialZoom: NavigationConfig.cameraZoom,
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
                      if (current['raster_value'] > NavigationConfig.highRisk) {
                        lineColor = Colors.red; 
                      } else if (current['raster_value'] > NavigationConfig.mediumRisk) {
                        lineColor = Colors.orange; 
                      } else {
                        lineColor = Colors.purple; 
                      }
                    } else {
                      lineColor = Colors.purple; 
                    }

                    return Polyline(
                      points: [current['latlng'] as LatLng, next['latlng'] as LatLng],
                      strokeWidth: 8.0,
                      color: lineColor,
                    );
                  }).whereType<Polyline>().toList(), 
                ),
                MarkerLayer(
                  markers: [
                    if (currentPosition != null)
                      Marker(
                        point: currentPosition!,
                        child: Icon(
                          Icons.my_location,
                          color: Colors.black,
                          size: screenWidth * 0.09, 
                        ),
                      ),
                  ],
                ),
              ],
            ),
          Positioned(
            top: screenHeight * 0.05, 
            right: screenWidth * 0.05,
            child: IconButton(
              icon: Icon(Icons.close, size: screenWidth * 0.1, color: Colors.black,), 
              onPressed: () {
                Navigator.pop(context); 
              },
            ),
          ),
          if (!_destinationReached)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: screenHeight * 0.15, 
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // color: Colors.white,
                  color: Theme.of(context).colorScheme.onPrimary,
                  shape: BoxShape.rectangle,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.formattedTime ?? "",
                      style: TextStyle(
                        fontSize: screenWidth * 0.08, 
                        fontWeight: FontWeight.bold,
                        // color: Colors.black,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.distances[selectedRouteKey]!,
                          style: TextStyle(
                            fontSize: screenWidth * 0.06, 
                            fontWeight: FontWeight.bold,
                            // color: Colors.black,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        SizedBox(width: screenWidth * 0.08),
                        Text(
                          widget.times[selectedRouteKey]!,
                          style: TextStyle(
                            fontSize: screenWidth * 0.06, 
                            fontWeight: FontWeight.bold,
                            // color: Colors.black,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: screenHeight * 0.02), 
                  ],
                ),
              ),
            ),
          if (_destinationReached)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: screenHeight * 0.15, 
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // color: Colors.white,
                  color: Theme.of(context).colorScheme.onPrimary,
                  shape: BoxShape.rectangle,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      LanguageConfig.getLocalizedString(languageCode, 'destinationReached'),
                      style: TextStyle(
                        fontSize: screenWidth * 0.08, 
                        fontWeight: FontWeight.bold,
                        // color: Colors.black,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.02), 
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}