import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
  bool isNavigationActive = NavigationConfig.isNavigationActive;
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
  final bool _destinationReached = NavigationConfig.destinationReached;
  final int _destinationThresholdMeters = NavigationConfig.destinationThresholderMeters;
  Set<Map<String, dynamic>> notifiedZones = NavigationConfig.notifiedZones; // Track notified risk zones
  bool inRiskZone = NavigationConfig.inRiskZone;
  DateTime? lastWarningTime; // Move this outside the function to persist the value
  bool keepRoute = NavigationConfig.keepRoute;
  Set<Map<String, dynamic>> passedSegments = NavigationConfig.passedSegments; // Store segments already passed
  int consecutiveOffRouteCount = NavigationConfig.consecutiveOffRouteCount; // Track how many times user is "off-route"
  int offRouteThreshold = NavigationConfig.offRouteThreshold; // Require 7 consecutive off-route detections
  bool lastOnRouteState = NavigationConfig.lastOnRouteState; // Track last known on-route state
  bool startRiskNotificationSent = NavigationConfig.startRiskNotificationSent; // Track if the initial notification was sent
  List<dynamic> notifiedDivergences = NavigationConfig.notifiedDivergences;
  bool firstRiskDetected = NavigationConfig.firstRiskDetected;
  bool enteringNewRiskZone = NavigationConfig.enteringNewRiskZone;
  bool isOnRoute = NavigationConfig.isOnRoute;
  double highestUpcomingRisk = NavigationConfig.highestUpcomingRisk;
  double currentRiskLevel = NavigationConfig.currentRiskLevel;
  Set<Map<String, dynamic>> detectedRiskZones = NavigationConfig.detectedRiskZones;  
  Map<Map<String, dynamic>, double> upcomingRisks = NavigationConfig.upcomingRisks; // Store multiple risk points
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  bool _destinationReachedNotif = false;
  StreamSubscription<CompassEvent>? _compassSubscription;
  double? _lastBearing;
  String _remainingTimeFormatted = '';
  String _remainingDistanceFormatted = '';
  bool _isMapCentered = true;

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
    // Keep screen awake while navigation is active
    WakelockPlus.enable();
    NavigationConfig.isNavigationActive = true;
    _setNavigationStatus(true);
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
    _startCompassListener(); //TODO: ESTAR EM COMENTÁRIO PARA O EMULADOR
    
    // print("enteringNewRiskZone: $enteringNewRiskZone");
    // print("NavigationConfig.enteringNewRiskZone: ${NavigationConfig.enteringNewRiskZone}");
    // print("NavigationConfig.upcomingRisks: ${NavigationConfig.upcomingRisks}");

    print("Navigation init isNavigationActive: ${NavigationConfig.isNavigationActive}");

    super.initState();
    selectedRouteKey = widget.selectedRouteKey; // Set initial route from Home.dart
    routeCoordinates = widget.routesWithPoints[selectedRouteKey] ?? [];

    location = Location();
    _mapController = MapController();
    
    _mapController.mapEventStream.listen((MapEvent mapEvent) {
      if (mapEvent is MapEventMoveEnd) { // This covers both pan and zoom end events
        if (_isMapCentered) {
          setState(() {
            _isMapCentered = false;
          });
        }
      }
    });

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

        // Calculate raw bearing first
        double rawBearing = 0.0;
        if (currentPosition != null) { // Use currentPosition as start for bearing calc
          rawBearing = _calculateBearing(currentPosition!, newPosition);
        }

        // Apply smoothing
        bearing = _smoothBearing(rawBearing); // Assign the smoothed bearing

        // Only update previousPosition if not currently animating,
        // and trigger animation if needed.
        if (previousPosition != null && !isAnimating) {
          _animateMarker(previousPosition!, newPosition);
          _updateRouteProgress();
        } else {
          setState(() {
            previousPosition = currentPosition;
            currentPosition = newPosition;
            // bearing is already updated above
            _updateRouteProgress();
          });
        }

        // Handle the first location update to set initial map view
        if (NavigationConfig.isFirstLocationUpdate) { // Use NavigationConfig's flag
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (currentPosition != null) {
              // _mapController.moveAndRotate(currentPosition!, NavigationConfig.cameraZoom, bearing);
              _mapController.move(currentPosition!, NavigationConfig.cameraZoom);
              NavigationConfig.isFirstLocationUpdate = false; // Update the flag
            }
          });
        }

        // // Important: Call _updateRouteProgress after currentPosition has definitively updated,
        // // especially after animation completes or if no animation occurs.
        // // If _animateMarker's completion callback calls setState to update `currentPosition`,
        // // then `_updateRouteProgress` should be called there to ensure it uses the final position.
        // // For simplicity here, we'll ensure it's called after the non-animated update,
        // // and assume _animateMarker's completion handles its own update.
        // if (!isAnimating) {
        //   // This line is potentially redundant if `_updateRouteProgress` is already called
        //   // within the `setState` block above, or if `_animateMarker` calls it on completion.
        //   // Make sure it's called exactly once per location update.
        //   _updateRouteProgress(); // Consider if this is truly needed here or if _animateMarker handles it.
        // }

        // Check for off-route or risk zones
        if (selectedRouteKey == "defaultRoute") {
          _checkReRoute();
        }
        _checkRiskZone();

        // Check if destination is reached
        // Get the last segment's end point
        if (routeCoordinates.isNotEmpty) {
          final LatLng destinationPoint = routeCoordinates.last['end'] as LatLng; // Use 'end' of the last segment
          if ((currentPosition!.latitude - destinationPoint.latitude).abs() < NavigationConfig.threshold &&
              (currentPosition!.longitude - destinationPoint.longitude).abs() < NavigationConfig.threshold) {
            setState(() {
              NavigationConfig.destinationReached = true; // Use NavigationConfig flag
            });

            if (_appLifecycleState != AppLifecycleState.resumed && !_destinationReachedNotif && mounted) {
              String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
              await http.post(
                Uri.parse('https://ecoterra.rd.ciencias.ulisboa.pt/send'), 
                // Uri.parse('http://192.168.1.82:3001/send'),
                // Uri.parse('http://10.101.121.11:3001/send'),    // Para testar na uni
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
                _destinationReachedNotif = true; // Use NavigationConfig flag
              });
            }
          }
        }
      }
    });
  }

  void _updateRouteProgress() {
    print("Entro no _updateRouteProgress");
    if (currentPosition == null || routeCoordinates.isEmpty) {
      NavigationConfig.estimatedArrivalTime = ""; // Clear time if no route/position
      _remainingDistanceFormatted = "0 m";
      return;
    }

    double totalRemainingDistance = 0.0;
    double totalRemainingTimeSeconds = 0.0; // To accumulate time from segments
    int currentSegmentIndex = -1; // The index of the segment the user is currently on or closest to

    // Find the current segment: Iterate through segments to find the one the user is on or closest to.
    for (int i = 0; i < routeCoordinates.length; i++) {
      final segment = routeCoordinates[i];
      final LatLng segmentStart = segment['start'] as LatLng; // Already cast to LatLng in _fetchRoute
      final LatLng segmentEnd = segment['end'] as LatLng;     // Already cast to LatLng in _fetchRoute

      // Use a small buffer distance to determine if the user is "on" or "near" the segment
      const double onSegmentThresholdMeters = 20.0; // Adjust as needed

      // Check if the current position is near this segment
      // This is a simplified check. For precise "on-route" detection,
      // you'd typically project the point onto the segment.
      final distToStart = const Distance().as(LengthUnit.Meter, currentPosition!, segmentStart);
      final distToEnd = const Distance().as(LengthUnit.Meter, currentPosition!, segmentEnd);
      final segmentLength = const Distance().as(LengthUnit.Meter, segmentStart, segmentEnd);

      // Simple check: if within threshold of either end and total length is reasonable
      if ((distToStart < onSegmentThresholdMeters || distToEnd < onSegmentThresholdMeters) &&
          (distToStart + distToEnd - segmentLength).abs() < onSegmentThresholdMeters * 2) {
        currentSegmentIndex = i;
        break; // Found the current segment
      }
    }

    // If we couldn't find a current segment, it means the user is off-route significantly,
    // or the route is very short/complex to match.
    // We'll calculate from the closest segment's start, or assume off-route.
    if (currentSegmentIndex == -1) {
      // Fallback: Find the closest segment's start point if not "on" any segment
      double minDistanceToAnySegmentStart = double.infinity;
      int closestSegmentStartIndex = -1;

      for (int i = 0; i < routeCoordinates.length; i++) {
        final segmentStart = routeCoordinates[i]['start'] as LatLng;
        final dist = const Distance().as(LengthUnit.Meter, currentPosition!, segmentStart);
        if (dist < minDistanceToAnySegmentStart) {
          minDistanceToAnySegmentStart = dist;
          closestSegmentStartIndex = i;
        }
      }
      currentSegmentIndex = closestSegmentStartIndex;
    }


    // If a current segment is identified (or a closest starting point)
    if (currentSegmentIndex != -1) {
      // Add the remaining distance/time for the current segment
      final currentSegment = routeCoordinates[currentSegmentIndex];
      // final LatLng segmentStart = currentSegment['start'] as LatLng;
      final LatLng segmentEnd = currentSegment['end'] as LatLng;
      final double timeToNextSeconds = (currentSegment['time_to_next_seconds'] as num?)?.toDouble() ?? 0.0;

      // Calculate remaining distance within the current segment.
      // This is a simplification: ideally, you'd project currentPosition onto the segment.
      // For now, we'll just sum up the distance from `currentPosition` to the end of the current segment,
      // and then add remaining segments.
      totalRemainingDistance += const Distance().as(LengthUnit.Meter, currentPosition!, segmentEnd);
      totalRemainingTimeSeconds += timeToNextSeconds;


      // Add distances and times for all subsequent segments
      for (int i = currentSegmentIndex + 1; i < routeCoordinates.length; i++) {
        final segment = routeCoordinates[i];
        final LatLng p1 = segment['start'] as LatLng;
        final LatLng p2 = segment['end'] as LatLng;
        final double segmentLength = const Distance().as(LengthUnit.Meter, p1, p2);
        final double segmentTimeToNext = (segment['time_to_next_seconds'] as num?)?.toDouble() ?? 0.0;

        totalRemainingDistance += segmentLength;
        totalRemainingTimeSeconds += segmentTimeToNext;
      }

      // --- Update passed segments for tracking ---
      NavigationConfig.passedSegments.clear(); // Clear previous passed segments
      for (int i = 0; i <= currentSegmentIndex; i++) {
        NavigationConfig.passedSegments.add(routeCoordinates[i]);
      }

    } else {
      // If no segment is found, the user is likely far off-route or reached destination.
      // Set remaining distance/time to zero.
      totalRemainingDistance = 0.0;
      totalRemainingTimeSeconds = 0.0;
      NavigationConfig.passedSegments.clear(); // No segments passed if not on route
    }

    // Destination reached check 
    if (routeCoordinates.isNotEmpty) {
      final LatLng finalDestination = routeCoordinates.last['end'] as LatLng;
      if (currentPosition != null && const Distance().as(LengthUnit.Meter, currentPosition!, finalDestination) < _destinationThresholdMeters) {
        setState(() {
          NavigationConfig.destinationReached = true;
        });
        totalRemainingDistance = 0.0; // Ensure 0 if destination reached
        totalRemainingTimeSeconds = 0.0;
      }
    }

    setState(() {
      _remainingDistanceFormatted = _formatDistance(totalRemainingDistance);
      _remainingTimeFormatted = _formatTime(totalRemainingTimeSeconds);
      NavigationConfig.estimatedArrivalTime = _remainingTimeFormatted; 
    });

    // Only move the map if it's supposed to be centered
    if (_isMapCentered && currentPosition != null) {
      // Ensure bearing is calculated before moving and rotating the map
      if (previousPosition != null && currentPosition != null) {
        bearing = _calculateBearing(previousPosition!, currentPosition!);
      }
      // _mapController.moveAndRotate(currentPosition!, NavigationConfig.cameraZoom, bearing); // Add bearing here
      _mapController.move(currentPosition!, NavigationConfig.cameraZoom); // Add bearing here

    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
  }

  String _formatTime(double seconds) {
    final Duration duration = Duration(seconds: seconds.round());
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitHours = twoDigits(duration.inHours);

    if (duration.inHours > 0) {
      return '$twoDigitHours h $twoDigitMinutes min';
    } else if (duration.inMinutes > 0) {
      return '$twoDigitMinutes min';
    } else {
      return '${duration.inSeconds} sec';
    }
  }

  Future<void> _setNavigationStatus(bool status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isNavigationActive', status);
    print("SharedPreferences: Navigation active set to $status");
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
        //   Uri.parse('https://ecoterra.rd.ciencias.ulisboa.pt/send'),
        //  Uri.parse('http://192.168.1.82:3001/send'),
        //  Uri.parse('http://10.101.121.11:3001/send'),    // Para testar na uni
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

  void _startCompassListener() {
    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      final double? heading = event.heading;
      if (heading == null || !mounted) return;

      setState(() {
        bearing = _smoothBearing(heading);
      });

      if (currentPosition != null && !isAnimating && _isMapCentered) {
        double adjustedBearing = (360 - bearing) % 360; // Invert direction

        _mapController.rotate(adjustedBearing);
      }
    });
  }

  double _smoothBearing(double newBearing) {
    if (_lastBearing == null) return newBearing;
    _lastBearing = (_lastBearing! * 0.8 + newBearing * 0.2);
    return _lastBearing!;
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

      // Only move the map during animation if it's supposed to be centered
      if (_isMapCentered) {
        _mapController.move(intermediatePosition, NavigationConfig.cameraZoom); // bearing handled by compass
      }
    }

    // Final position and animation end state
    if (!mounted) return; // Ensure widget is still mounted before finishing the animation
    setState(() {
      isAnimating = false;
      previousPosition = end; // Ensure the final position is set
    });
  }

  // Function to recenter the map
  void _recenterMap() {
    if (currentPosition != null) {
      setState(() {
        _isMapCentered = true;
      });
      // Ensure bearing is updated before recentering if it might have changed
      if (previousPosition != null && currentPosition != null) {
        bearing = _calculateBearing(previousPosition!, currentPosition!);
      }
      // _mapController.moveAndRotate(currentPosition!, NavigationConfig.cameraZoom, bearing); // Use moveAndRotate
      _mapController.move(currentPosition!, NavigationConfig.cameraZoom); // Add bearing here

    }
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
    if (currentPosition == null || _notifications.fcmToken == null || _notifications.fcmToken!.isEmpty) {
      return;
    }

    final userPreferences = Provider.of<UserPreferences>(context, listen: false);
    String riskAlertDistanceSetting = userPreferences.riskAlertDistance;

    double alertDistanceThreshold = _convertAlertDistance(riskAlertDistanceSetting);
    double routeDeviationThreshold = NavigationConfig.routeDeviationThreshold;
    const Distance distance = Distance();

    // Reset flags for the current check iteration
    isOnRoute = false;
    NavigationConfig.highestUpcomingRisk = 0;
    upcomingRisks.clear();
    detectedRiskZones.clear();

    // --- Determine Current Risk Level based on closest segment ---
    double closestDistToRoute = double.infinity;
    Map<String, dynamic>? currentSegment; // To hold the segment the user is currently on

    for (var segment in routeCoordinates) {
      if (segment['start'] is! LatLng || segment['end'] is! LatLng || segment['raster_value'] == null) {
        continue;
      }

      final LatLng segmentStart = segment['start'] as LatLng;
      final LatLng segmentEnd = segment['end'] as LatLng;

      double distToStart = distance(currentPosition!, segmentStart);
      double distToEnd = distance(currentPosition!, segmentEnd);
      double segmentLength = distance(segmentStart, segmentEnd);

      // More robust check for being "on" a segment: project point onto line segment
      // This is a simplified approach, a true projection can be complex.
      // For now, we'll continue with the "near start/end and sum of distances" method.
      bool isNearSegment = (distToStart < routeDeviationThreshold || distToEnd < routeDeviationThreshold) &&
          (distToStart + distToEnd - segmentLength).abs() < routeDeviationThreshold * 2;

      if (isNearSegment) {
        isOnRoute = true;
        // If multiple segments are "near", consider the one with the closest start point
        // or a more sophisticated 'closest segment to current position' logic.
        // For simplicity, we'll take the first one found that's "near enough"
        // or the one that minimizes the sum of distances to its start/end.
        // A better approach would be to find the closest point *on the line segment*.
        // For now, let's just pick the "nearest" segment that we are currently on/near.
        if (distToStart < closestDistToRoute) { // Or a more complex distance to segment logic
            closestDistToRoute = distToStart;
            currentSegment = segment;
        }
      }
    }

    if (currentSegment != null) {
      NavigationConfig.currentRiskLevel = (currentSegment['raster_value'] as num).toDouble();
    } else {
      // If not on any segment, set currentRiskLevel to 0 or a safe default
      NavigationConfig.currentRiskLevel = 0.0;
    }
    // --- End of Current Risk Level Determination ---

    // Loop through segments to find upcoming risks
    for (var segment in routeCoordinates) {
      if (segment['start'] is! LatLng || segment['end'] is! LatLng || segment['raster_value'] == null) {
        continue;
      }

      final LatLng segmentStart = segment['start'] as LatLng;
      double riskValue = (segment['raster_value'] as num).toDouble();

      double distToSegmentStart = distance(currentPosition!, segmentStart);
      bool withinAlertDistance = distToSegmentStart < alertDistanceThreshold;

      // Logic for upcoming high-risk zones
      if (withinAlertDistance && riskValue > NavigationConfig.mediumRisk) {
        // Add to upcoming risks if this segment is *ahead* of the current position.
        // A more robust check here would be to ensure the segment is indeed 'upcoming'
        // relative to `currentSegment` (e.g., its index in `routeCoordinates` is higher).
        // For simplicity, we'll keep the current approach of "within alert distance and risky".
        upcomingRisks[segment] = riskValue;
        detectedRiskZones.add(segment);
        if (riskValue > NavigationConfig.highestUpcomingRisk || NavigationConfig.highestUpcomingRisk == 0) {
          NavigationConfig.highestUpcomingRisk = riskValue;
        }
      }
    }

    // --- Off-route detection and notification ---
    if (isOnRoute) {
      NavigationConfig.consecutiveOffRouteCount = 0;
    } else {
      NavigationConfig.consecutiveOffRouteCount++;
    }

    bool confirmedOffRoute = NavigationConfig.consecutiveOffRouteCount >= NavigationConfig.offRouteThreshold;

    if (confirmedOffRoute && NavigationConfig.lastOnRouteState) {
      _sendOffRouteWarning();
    }
    NavigationConfig.lastOnRouteState = isOnRoute;

    String currentRiskCategory = getRiskCategory(NavigationConfig.currentRiskLevel);

    NavigationConfig.enteringNewRiskZone = false;

    // Process and notify for upcoming risks
    for (var entry in upcomingRisks.entries) {
      Map<String, dynamic> riskSegment = entry.key;
      double riskValue = entry.value;
      String upcomingRiskCategory = getRiskCategory(riskValue);

      List<dynamic> speciesList = (riskSegment['species'] is List) ? List<dynamic>.from(riskSegment['species']) : [];

      // Initial risk warning
      if (!NavigationConfig.firstRiskDetected && !NavigationConfig.startRiskNotificationSent && NavigationConfig.currentRiskLevel > NavigationConfig.mediumRisk && isOnRoute) {
        final LatLng notificationPoint = riskSegment['start'] as LatLng;
        _sendInitialRiskWarning(notificationPoint, NavigationConfig.currentRiskLevel, speciesList);
        NavigationConfig.startRiskNotificationSent = true;
        NavigationConfig.firstRiskDetected = true;
      }

      // Determine if entering a new, higher risk zone based on the specified transitions
      if ((currentRiskCategory == "Low" || currentRiskCategory == "Medium-Low") &&
              (upcomingRiskCategory == "Medium" || upcomingRiskCategory == "Medium-High" || upcomingRiskCategory == "High") ||
          (currentRiskCategory == "Medium" || currentRiskCategory == "Medium-High") &&
              upcomingRiskCategory == "High") {
        NavigationConfig.enteringNewRiskZone = true;
      }

      print("enteringNewRiskZone: ${NavigationConfig.enteringNewRiskZone}, highestUpcomingRisk: ${NavigationConfig.highestUpcomingRisk}, currentRiskLevel: ${NavigationConfig.currentRiskLevel}");

      if (!NavigationConfig.enteringNewRiskZone) continue; // Skip if not transitioning to a new risk

      Set<Map<String, dynamic>> connectedRiskZone = _findConnectedRiskZone(riskSegment, upcomingRiskCategory);

      print("Connected Risk Zone Size: ${connectedRiskZone.length}");

      bool anyNewSegmentInZone = false;
      for (var segmentInZone in connectedRiskZone) {
        if (!NavigationConfig.notifiedZones.contains(segmentInZone)) {
          anyNewSegmentInZone = true;
          break;
        }
      }

      if (anyNewSegmentInZone && riskValue > NavigationConfig.currentRiskLevel) {
        print("🔔 Sending notification for risk at segment (Risk Level: $riskValue, Current Risk Level: ${NavigationConfig.currentRiskLevel})");
        final LatLng notificationPoint = riskSegment['start'] as LatLng;
        _sendRiskWarning(notificationPoint, riskValue, speciesList);
        NavigationConfig.notifiedZones.addAll(connectedRiskZone);
      } else {
        print("⚠️ Risk already notified: Skipping notification for segment");
      }
    }

    // Update inRiskZone flag based on overall current risk
    NavigationConfig.inRiskZone = NavigationConfig.currentRiskLevel > NavigationConfig.mediumRisk;
  }

  // Determine risk category
  String getRiskCategory(double riskLevel) {
    if (riskLevel < NavigationConfig.mediumRisk) return "Low";
    if (riskLevel >= NavigationConfig.mediumRisk && riskLevel < NavigationConfig.highRisk) return "Medium";
    return "High";
  }

  String _getGroupedRiskCategory(double riskValue) {
    if (riskValue > NavigationConfig.highRisk) {
      return "High";
    } else if (riskValue > NavigationConfig.mediumHighRisk) {
      return "Medium_Group"; // Group Medium-High with Medium
    } else if (riskValue > NavigationConfig.mediumRisk) {
      return "Medium_Group"; // Group Medium with Medium-High
    } else if (riskValue > NavigationConfig.mediumLowRisk) {
      return "Low_Group"; // Group Medium-Low with Low
    } else {
      return "Low_Group"; // Default to Low Group
    }
  }

  Set<Map<String, dynamic>> _findConnectedRiskZone(Map<String, dynamic> startSegment, String riskCategory) {
    Set<Map<String, dynamic>> connectedZone = {};
    Queue<Map<String, dynamic>> queue = Queue();

    // Define the threshold based on the riskCategory
    double threshold;
    switch (riskCategory) {
      case "Low":
      case "Medium-Low": // These categories now fall under a "Low_Group" for thresholds
        threshold = NavigationConfig.mediumLowRisk; // Or adjust as needed for the lowest risk in the group
        break;
      case "Medium":
      case "Medium-High": // These categories now fall under a "Medium_Group" for thresholds
        threshold = NavigationConfig.mediumRisk; // Or adjust as needed for the lowest risk in the group
        break;
      case "High":
        threshold = NavigationConfig.highRisk;
        break;
      default:
        threshold = 0.0; // Default to including all, or handle as an error
    }

    // Determine the 'group' category of the starting segment
    final double startSegmentRiskValue = (startSegment['raster_value'] as num).toDouble();
    final String startSegmentGroupedCategory = _getGroupedRiskCategory(startSegmentRiskValue);


    // Initialize with the startSegment
    connectedZone.add(startSegment);
    queue.add(startSegment);

    // Find the index of the startSegment in the main routeCoordinates list
    int startIndex = routeCoordinates.indexOf(startSegment);
    if (startIndex == -1) {
      print("Error: Start segment not found in routeCoordinates.");
      return connectedZone;
    }

    // --- Traverse Forward ---
    for (int i = startIndex + 1; i < routeCoordinates.length; i++) {
      var segment = routeCoordinates[i];

      if (segment['start'] is! LatLng || segment['end'] is! LatLng || segment['raster_value'] == null) {
        break;
      }

      double riskValue = (segment['raster_value'] as num).toDouble();
      String segmentGroupedCategory = _getGroupedRiskCategory(riskValue); // Use the new grouped category helper

      // Condition to add to connectedZone:
      // 1. Risk value is at or above the threshold of the *starting* segment's category.
      // 2. The segment's *grouped* category is the same as the *starting segment's grouped category*.
      // This ensures continuity within "Medium_Group" but stops at "High" if starting in "Medium_Group".
      if (riskValue >= threshold) {
        if (segmentGroupedCategory == startSegmentGroupedCategory) {
          connectedZone.add(segment);
        } else {
          // If the category changes (e.g., Medium_Group to High, or vice-versa), stop
          break;
        }
      } else {
        // Stop if the risk value drops below the threshold for the starting category
        break;
      }
    }

    // --- Traverse Backward ---
    for (int i = startIndex - 1; i >= 0; i--) {
      var segment = routeCoordinates[i];

      if (segment['start'] is! LatLng || segment['end'] is! LatLng || segment['raster_value'] == null) {
        break;
      }

      double riskValue = (segment['raster_value'] as num).toDouble();
      String segmentGroupedCategory = _getGroupedRiskCategory(riskValue);

      if (riskValue >= threshold) {
        if (segmentGroupedCategory == startSegmentGroupedCategory) {
          connectedZone.add(segment);
        } else {
          break;
        }
      } else {
        break;
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

  void _sendRiskWarning(LatLng notificationPoint, double riskValue, List<dynamic> speciesList) async {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    
    NavigationConfig.firstRiskDetected = true;

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
      // body = "${LanguageConfig.getLocalizedString(languageCode, 'highRiskMsgBody')}: $speciesNames. ${LanguageConfig.getLocalizedString(languageCode, 'stayAlert')}";
      body = "${LanguageConfig.getLocalizedString(languageCode, 'highRiskMsgBody')}: $speciesNames.";
    } else {
      // This 'else' condition covers Medium-High, Medium, Medium-Low, and Low if needed.
      // Ensure NavigationConfig constants are used correctly for these ranges.
      title = "${LanguageConfig.getLocalizedString(languageCode, 'mediumRiskMsgTitle')}: $speciesNames ${LanguageConfig.getLocalizedString(languageCode, 'atRisk')}";
      // body = "${LanguageConfig.getLocalizedString(languageCode, 'mediumRiskMsgBody')}: $speciesNames. ${LanguageConfig.getLocalizedString(languageCode, 'caution')}";
      body = "${LanguageConfig.getLocalizedString(languageCode, 'mediumRiskMsgBody')}: $speciesNames.";
    }

    try {
      final response = await http.post(
        Uri.parse('https://ecoterra.rd.ciencias.ulisboa.pt/send'), 
        // Uri.parse('http://192.168.1.82:3001/send'), 
        // Uri.parse('http://10.101.121.11:3001/send'),    // Para testar na uni
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
      } else {
        print("Failed to send risk alert. Status code: ${response.statusCode}");
        print("Response body: ${response.body}");
      }
    } catch (e) {
      print("Error sending risk alert: $e");
    }
  }

  void _sendInitialRiskWarning(LatLng notificationPoint, double riskValue, List<dynamic> speciesList) async {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;

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
      // body = "${LanguageConfig.getLocalizedString(languageCode, 'warning')}: $speciesNames. ${LanguageConfig.getLocalizedString(languageCode, 'caution')}";
      body = "${LanguageConfig.getLocalizedString(languageCode, 'warning')}: $speciesNames.";
    } else {
      title = "${LanguageConfig.getLocalizedString(languageCode, 'mediumRiskMsgTitle')}: $speciesNames ${LanguageConfig.getLocalizedString(languageCode, 'atRisk')}";
      // body = "${LanguageConfig.getLocalizedString(languageCode, 'riskZoneHere')}: $speciesNames. ${LanguageConfig.getLocalizedString(languageCode, 'stayAlert')}";
      body = "${LanguageConfig.getLocalizedString(languageCode, 'riskZoneHere')}: $speciesNames.";
    }

    try {
      final response = await http.post(
        Uri.parse('https://ecoterra.rd.ciencias.ulisboa.pt/send'), 
        // Uri.parse('http://192.168.1.82:3001/send'), 
        // Uri.parse('http://10.101.121.11:3001/send'),    // Para testar na uni
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
        print("Initial risk alert sent successfully: $title");
      } else {
        print("Failed to send initial risk alert. Status code: ${response.statusCode}");
        print("Response body: ${response.body}");
      }
    } catch (e) {
      print("Error sending initial risk alert: $e");
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
        // Uri.parse('http://192.168.1.82:3001/send'),
        // Uri.parse('http://10.101.121.11:3001/send'),    // Para testar na uni
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

    final userPreferences = Provider.of<UserPreferences>(context, listen: false);
    String rerouteAlertDistance = userPreferences.rerouteAlertDistance;
    bool changeRoute = userPreferences.changeRoute;

    double alertThreshold = _convertAlertDistance(rerouteAlertDistance);

    // Ensure 'defaultRoute' and 'adjustedRoute' contain lists of segments
    List<Map<String, dynamic>> defaultRouteSegments = widget.routesWithPoints['defaultRoute'] ?? [];
    List<Map<String, dynamic>> adjustedRouteSegments = widget.routesWithPoints['adjustedRoute'] ?? [];

    if (defaultRouteSegments.isEmpty || adjustedRouteSegments.isEmpty) return;

    const Distance distance = Distance();

    // List to store the 'start' LatLng of the segments where divergence occurs
    List<LatLng> divergenceStartPoints = [];

    // Identify divergence segments. We'll iterate through the shorter of the two routes.
    // A divergence occurs when corresponding segments are sufficiently different.
    bool previouslyDiverged = false;
    for (int i = 0; i < min(defaultRouteSegments.length, adjustedRouteSegments.length); i++) {
      final defaultSegment = defaultRouteSegments[i];
      final adjustedSegment = adjustedRouteSegments[i];

      // Assuming 'start' and 'end' in segments are already LatLng objects
      final LatLng defaultSegmentStart = defaultSegment['start'] as LatLng;
      final LatLng adjustedSegmentStart = adjustedSegment['start'] as LatLng;
      final LatLng defaultSegmentEnd = defaultSegment['end'] as LatLng;
      final LatLng adjustedSegmentEnd = adjustedSegment['end'] as LatLng;

      // Check if the segments are "close" enough. This can be done by comparing their start points,
      bool areSegmentsClose = _arePointsClose(defaultSegmentStart, adjustedSegmentStart, threshold: NavigationConfig.pointsCloseThreshold) &&
                              _arePointsClose(defaultSegmentEnd, adjustedSegmentEnd, threshold: NavigationConfig.pointsCloseThreshold);


      if (!areSegmentsClose) {
        if (!previouslyDiverged) {
          // This is the first segment where divergence is detected
          divergenceStartPoints.add(defaultSegmentStart); // Use the start point of the default route's diverging segment
          previouslyDiverged = true; // Mark as diverged
        }
      } else {
        previouslyDiverged = false; // Mark as converged or still similar
      }
    }

    if (divergenceStartPoints.isEmpty) return; // No divergences found

    // Find the next upcoming divergence point that the user is approaching
    for (LatLng divergencePoint in divergenceStartPoints) {
      double distanceToDivergence = distance(currentPosition!, divergencePoint);

      // Check if the user is within alert distance and this divergence hasn't been notified
      if (distanceToDivergence < alertThreshold && !NavigationConfig.notifiedDivergences.contains(divergencePoint)) {
        _sendReRouteNotification(changeRoute);
        // Mark this specific LatLng point as notified, not the segment.
        NavigationConfig.notifiedDivergences.add(divergencePoint); // Add the LatLng point to the set
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
        // Uri.parse('http://192.168.1.82:3001/send'),
        // Uri.parse('http://10.101.121.11:3001/send'),    // Para testar na uni
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
      notifiedZones.clear(); // Clear notified zones for the new route
    });

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
   // Allow screen to sleep again when leaving
    WakelockPlus.disable();
    NavigationConfig.isNavigationActive = false;
    _setNavigationStatus(false);
    // Cancel location updates
    locationSubscription?.cancel();
    _mapController.dispose();
    _compassSubscription?.cancel();
    
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
                onMapReady: () {
                  // This code runs AFTER the map is rendered and ready for interaction
                  if (currentPosition != null) {
                    // _mapController.moveAndRotate(currentPosition!, NavigationConfig.cameraZoom, bearing);
                    _mapController.move(currentPosition!, NavigationConfig.cameraZoom);
                    // Also update the initial progress here
                    _updateRouteProgress();
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  tileProvider: NetworkTileProvider(
                    headers: {
                      'User-Agent': 'SafeRoads/1.0',
                    },
                  ),
                  userAgentPackageName: 'com.example.safe_roads',
                ),
                PolylineLayer(
                  polylines: [
                    // Draw the remaining (upcoming) segments of the selected route
                    // Only draw if there are segments in the routeCoordinates list
                    if (routeCoordinates.isNotEmpty)
                      ...List.generate(routeCoordinates.length, (index) {
                        final segment = routeCoordinates[index];
                        final LatLng startPoint = segment['start'] as LatLng;
                        final LatLng endPoint = segment['end'] as LatLng;

                        // Determine color based on raster value for upcoming segments
                        Color lineColor;
                        final raster = segment['raster_value'];
                        if (raster != null) {
                          if (raster > NavigationConfig.highRisk) {
                            lineColor = Colors.red;
                          } else if (raster > NavigationConfig.mediumHighRisk) { // Assuming you have this constant
                            lineColor = Colors.deepOrangeAccent;
                          } else if (raster > NavigationConfig.mediumRisk) {
                            lineColor = Colors.orange;
                          } else if (raster > NavigationConfig.mediumLowRisk) { // Assuming you have this constant
                            lineColor = Colors.yellow;
                          } else {
                            lineColor = Colors.purple; // Default for low/no risk
                          }
                        } else {
                          lineColor = Colors.purple; // Fallback if raster_value is null
                        }

                        return Polyline(
                          points: [startPoint, endPoint],
                          strokeWidth: 8.0, // Thickness for upcoming segments
                          color: lineColor,
                        );
                      }).whereType<Polyline>(), // Filter out any nulls
                  ],
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
           // Recenter Button
          if (!_isMapCentered)
            Positioned(
              bottom: screenHeight * 0.17, // Adjust position to be above the info bar
              right: screenWidth * 0.05,
              child: FloatingActionButton(
                onPressed: _recenterMap,
                // mini: true, // Make it a smaller button
                backgroundColor: Theme.of(context).colorScheme.secondary,
                child: Icon(Icons.gps_fixed, color: Theme.of(context).colorScheme.onSecondary),
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
                          _remainingDistanceFormatted,
                          style: TextStyle(
                            fontSize: screenWidth * 0.06, 
                            fontWeight: FontWeight.bold,
                            // color: Colors.black,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        SizedBox(width: screenWidth * 0.08),
                        Text(
                          _remainingTimeFormatted,
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