import 'dart:async';
import 'dart:convert';
// import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
// import 'package:path_provider/path_provider.dart';
import 'package:safe_roads/configuration/home_config.dart';
import 'package:safe_roads/configuration/language_config.dart';
import 'package:safe_roads/controllers/profile_controller.dart';
import 'package:safe_roads/main.dart';
import 'package:safe_roads/models/user_preferences.dart';
import 'package:safe_roads/notifications.dart';
import 'package:safe_roads/pages/loading_navigation.dart';
import 'package:provider/provider.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin  {
  final MapController _mapController = MapController();
  LocationData? _currentLocation;
  LatLng? _destinationLocation;
  Map<String, List<Map<String, dynamic>>> _routesWithPoints = HomeConfig.defaultRoutesWithPoints;
  final TextEditingController _addressController = TextEditingController();
  List<Map<String, dynamic>> _suggestions = []; // Stores autocomplete suggestions
  Timer? _debounce; // To avoid over calling the API
  LatLng _currentCenter = HomeConfig.defaultCenter;
  double _currentZoom = HomeConfig.defaultZoom;
  bool destinationSelected = HomeConfig.defaultDestinationSelected;
  String? selectedDestination = HomeConfig.defaultSelectedDestination;
  Map<String, String> _distances = HomeConfig.defaultDistances;
  Map<String, String> _times = HomeConfig.defaultTimes;
  Map<String, String> _distancesAtMaxRisk = HomeConfig.defaultDistancesAtMaxRisk;
  bool setDestVis = HomeConfig.defaultSetDestVis;
  bool _isFetchingRoute = HomeConfig.defaultIsFetchingRoute;
  bool _cancelFetchingRoute = HomeConfig.defaultCancelFetchingRoute;
  final ProfileController _profileController = ProfileController();
  Map<String, dynamic> userPreferences = HomeConfig.defaultUserPreferences;
  String _selectedRouteKey = HomeConfig.defaultRouteKey;
  double _boxHeight = HomeConfig.defaultBoxHeight;
  double mediumLowRisk = HomeConfig.mediumLowRisk;
  double mediumRisk = HomeConfig.mediumRisk;
  double mediumHighRisk = HomeConfig.mediumHighRisk;
  double highRisk = HomeConfig.highRisk;
  Timer? _locationUpdateTimer;
  http.Client? _httpClient; // Declare an http client

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
    _setupAutocompleteListener();
    // Wait for preferences to load, then fetch routes
    Provider.of<UserPreferences>(context, listen: false)
        .initializePreferences()
        .then((_) => fetchUserPreferences());  // Ensure you fetch after preferences are loaded
    _mapController.mapEventStream.listen((event) {
        setState(() {}); // Update UI dynamically when the map moves
      });
    Future.delayed(Duration.zero, () async {
      final notifications = Notifications();
      if(mounted){ 
        notifications.setContext(context); // Save the context
        await notifications.setupFirebaseMessaging(context, null); // Set up FCM
      }
    });

    //TODO: METER ISTO COMENTÁRIO QUANDO SE ESTÁ A FAZER OS TESTES

    // Periodically update location every 30 seconds
    // _locationUpdateTimer = Timer.periodic(Duration(seconds: 30), (_) => _updateCurrentLocation());
  }

  Future<void> _requestLocationPermission() async {
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

    _currentLocation = await location.getLocation();
    setState(() {
      if (_currentLocation != null) {
        _mapController.move(
          // LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
          // const LatLng(38.902464, -9.163266), // Test with coordinates of Ribas de Baixo
          // const LatLng(37.08000502817415, -8.113855290887736), // Test with coordinates of Edificio Portugal
          // const LatLng(41.7013562, -8.1685668), // Current location for testing in the North (type: são bento de sexta freita)
          // const LatLng(41.641963, -7.949505), // Current location for testing in the North (type: minas da borralha)
          const LatLng(38.756546, -9.155300), //Current location for testing at FCUL
          13.0,
        );
      }
    });
  }

  Future<void> _updateCurrentLocation() async {
    Location location = Location();
    try {
      final newLocation = await location.getLocation();

      // Only move the map if no route is being fetched and there are no routes displayed
      if (!_isFetchingRoute && _routesWithPoints.isEmpty && mounted) {
        setState(() {
          _currentLocation = newLocation;
          _mapController.move(
            LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
            _currentZoom,
          );
        });
      } else {
        // Still update current location silently
        if (mounted) {
          setState(() {
            _currentLocation = newLocation;
          });
        }
      }
    } catch (e) {
      print("Error getting updated location: $e");
    }
  }

  Future<void> _fetchRoute(LatLng start, LatLng end) async {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    try {
      setState(() {
        _isFetchingRoute = true; // Show the progress bar
        _cancelFetchingRoute = false; // Reset the cancellation flag
      });

      // Access the updated values from the UserPreferences provider
      final userPreferences = Provider.of<UserPreferences>(context, listen: false);
      bool lowRisk = userPreferences.lowRisk;
      List<Object?> selectedSpecies = userPreferences.selectedSpecies;

      print("lowRisk: $lowRisk");
      print("HOME selectedSpecies: $selectedSpecies");

      _httpClient = http.Client();

      final response = await _httpClient!.post( 
        Uri.parse('https://ecoterra.rd.ciencias.ulisboa.pt/route'),
        // Uri.parse('http://192.168.1.82:3001/route'),
        // Uri.parse('http://10.101.121.11:3001/route'),    // Para testar na uni
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "start": {"lat": start.latitude, "lon": start.longitude},
          "end": {"lat": end.latitude, "lon": end.longitude},
          "lowRisk": lowRisk,
          "selectedSpecies": selectedSpecies,
        }),
      );

      // After the request, if we still have the client, close it
      // This ensures resources are released, even if not cancelled.
      _httpClient?.close();
      _httpClient = null; // Clear the client reference

      if (_cancelFetchingRoute) {
        // If cancellation was requested while waiting for response,
        // ensure UI is reset and return.
        _resetRouteUI(); // Call a new function to encapsulate UI reset
        return;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        Map<String, List<Map<String, dynamic>>> routesWithSegments = {};
        Map<String, String> distances = {};
        Map<String, String> times = {};
        Map<String, bool> hasRisk = {};
        Map<String, double> maxRiskValue = {};
        Map<String, String> distanceAtMaxRisk = {};


        data.forEach((key, routeData) {
          List<Map<String, dynamic>> segments = [];
          if (routeData['segments'] is List) {
            segments = (routeData['segments'] as List).map((segmentMap) {
              return {
                'start': LatLng(segmentMap['start']['lat'], segmentMap['start']['lon']),
                'end': LatLng(segmentMap['end']['lat'], segmentMap['end']['lon']),
                'raster_value': segmentMap['raster_value'],
                'species': List<String>.from(segmentMap['species'] ?? []),
                'time_to_next_seconds': (segmentMap['time_to_next_seconds'] as num?)?.toDouble() ?? 0.0,
                'segment_distance': segmentMap['segment_distance'],
              };
            }).toList();
          } else {
            print("Warning: 'segments' key not found or not a List for route $key");
            return;
          }

          routesWithSegments[key] = segments;
          distances[key] = routeData['distance'];
          times[key] = routeData['time'];
          hasRisk[key] = routeData['hasRisk'];
          maxRiskValue[key] = (routeData['maxRiskValue'] as num?)?.toDouble() ?? 0.0;
          distanceAtMaxRisk[key] = routeData['distanceAtMaxRisk'] as String? ?? '0 meters';

        });

        print("routesWithSegments: $routesWithSegments");
        print("maxRiskValue: $maxRiskValue");
        print("distanceAtMaxRisk: $distanceAtMaxRisk");

        navigationBarKey.currentState?.toggleNavigationBar(false);

        setState(() {
          _routesWithPoints = routesWithSegments;
          _distances = distances;
          _times = times;
          _isFetchingRoute = false;
          _selectedRouteKey = _routesWithPoints.keys.first;
          _distancesAtMaxRisk = distanceAtMaxRisk;
        });
        _adjustMapToBounds();

      } else {
        throw Exception("${LanguageConfig.getLocalizedString(languageCode, 'failFetchingRoute')}: ${response.body}");
      }
    } catch (e) {
      if (e is http.ClientException && e.message == 'Connection closed before full header was received') {
        // This is often the exception thrown when the client is closed prematurely
        print("Route fetching was cancelled.");
      } else if (!_cancelFetchingRoute) { // Only log if not explicitly cancelled by user
        print("${LanguageConfig.getLocalizedString(languageCode, 'errorFetchingRoute')} $e");
      }
      setState(() {
        _isFetchingRoute = false; // Hide the progress bar
      });
    } finally {
      // Ensure the client is closed even if an error occurs
      _httpClient?.close();
      _httpClient = null;
    }
  }

  void _resetRouteUI() {
    setState(() {
      _routesWithPoints.clear();
      _distances.clear(); 
      _times.clear();   
      _distancesAtMaxRisk.clear();    
      _selectedRouteKey = ""; 
      destinationSelected = false;
      selectedDestination = "";
      _destinationLocation = null;
      _addressController.text = "";
      _suggestions.clear();
      setDestVis = true;
      _isFetchingRoute = false;
    });
  }

  void _adjustMapToBounds() {
    if (_routesWithPoints.isNotEmpty) {
      // Collect all unique LatLng points from all route segments
      final List<LatLng> allPoints = [];

      for (var routeSegments in _routesWithPoints.values) {
        for (final segment in routeSegments) {
          // Add start point of the segment
          if (segment['start'] is LatLng) {
            allPoints.add(segment['start'] as LatLng);
          }
          // Add end point of the segment
          if (segment['end'] is LatLng) {
            allPoints.add(segment['end'] as LatLng);
          }
        }
      }

      if (allPoints.length < 2) {
        // If there are less than 2 points, maybe center on the first point if it exists
        // or simply return without adjusting the map.
        if (allPoints.isNotEmpty) {
          _animatedMapMove(allPoints.first, 15.0); // A default zoom
        }
        return;
      }

      final bounds = _calculateBounds(allPoints);

      // Calculate center of bounds
      final centerLat = (bounds.northEast.latitude + bounds.southWest.latitude) / 2;
      final centerLng = (bounds.northEast.longitude + bounds.southWest.longitude) / 2;
      final center = LatLng(centerLat, centerLng);

      // Estimate zoom level that fits the bounds
      final zoom = _getZoomLevelToFitBounds(bounds);

      // Animate to center and zoom
      _animatedMapMove(center, zoom);
    }
  }

  double _getZoomLevelToFitBounds(LatLngBounds bounds) {
    final mapSize = MediaQuery.of(context).size;
    final mapWidth = mapSize.width;
    final mapHeight = mapSize.height;

    const padding = 25.0;

    final effectiveWidth = mapWidth - 2 * padding;
    final effectiveHeight = mapHeight - 2 * padding;

    final latDiff = (bounds.northEast.latitude - bounds.southWest.latitude).abs();
    final lngDiff = (bounds.northEast.longitude - bounds.southWest.longitude).abs();

    // Convert lat/lng to radians
    final latFraction = latDiff / 180;
    final lngFraction = lngDiff / 360;

    final latZoom = _zoomForFraction(latFraction, effectiveHeight);
    final lngZoom = _zoomForFraction(lngFraction, effectiveWidth);

    return latZoom < lngZoom ? latZoom : lngZoom;
  }

  double _zoomForFraction(double fraction, double screenPx) {
    const tileSize = 256.0;
    final zoom = (log(screenPx / tileSize / fraction) / ln2).clamp(0.0, 22.0);
    return zoom;
  }

  Future<LatLng?> _getCoordinatesFromAddress(String address) async {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    try {
      final response = await http.post(
        Uri.parse('https://ecoterra.rd.ciencias.ulisboa.pt/geocode'),
        // Uri.parse('http://192.168.1.82:3001/geocode'),
        // Uri.parse('http://10.101.121.11:3001/geocode'), // Para testar na uni
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"address": address}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final lat = data['lat'];
        final lon = data['lon'];
        return LatLng(lat, lon);
      } else {
        print("Error: ${jsonDecode(response.body)['error']}");
      }
    } catch (e) {
      print("${LanguageConfig.getLocalizedString(languageCode, 'errorFetchingCoordinates')} : $e");
    }
    return null;
  }

  void _setupAutocompleteListener() {
    _addressController.addListener(() {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () {
        String query = _addressController.text;

        // If the user modifies the text, reset the destinationSelected flag
        if (destinationSelected && query != selectedDestination) {
          setState(() {
            destinationSelected = false;
          });
        }

        // Fetch suggestions if query length is sufficient
        if (query.length > 2) {
          _fetchSearchSuggestions(query);
        } else {
          // Clear suggestions if text is too short
          setState(() {
            _suggestions.clear();
          });
        }
      });
    });
  }

  DateTime? _lastSnackbarTime;

  Future<void> _fetchSearchSuggestions(String query) async {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
  
    try {
      final response = await http
          .get(
            Uri.parse('https://ecoterra.rd.ciencias.ulisboa.pt/search?query=${Uri.encodeComponent(query)}&limit=5&country=Portugal&lang=en'),
            // Uri.parse('http://192.168.1.82:3001/search?query=${Uri.encodeComponent(query)}&limit=5&lang=en'),
            // Uri.parse('http://10.101.121.11:3001/search?query=${Uri.encodeComponent(query)}&limit=5&lang=en'), // testar na uni
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // print(data);
       final seenFormattedStrings = <String>{};
        List<Map<String, dynamic>> suggestions = [];

        for (var feature in data['features']) {
          final props = feature['properties'];

          final suggestion = {
            'name': props['name'],
            'locality': props['locality'] ?? '',
            'city': props['city'] ?? '',
            'county': props['county'] ?? '',
            'country': props['country'] ?? '',
          };

          // Construct the full UI string used to identify duplicates
          final formatted = [
            suggestion['name'],
            suggestion['locality'],
            suggestion['city'],
            suggestion['county'],
            suggestion['country']
          ]
              .where((part) => part != null && part.toString().trim().isNotEmpty)
              .join(', ');

          // Only add if it's not already in the set
          if (!seenFormattedStrings.contains(formatted)) {
            seenFormattedStrings.add(formatted);
            suggestions.add(suggestion);
          }
        }

        setState(() {
          _suggestions = suggestions;
        });
      } else {
        print("${LanguageConfig.getLocalizedString(languageCode, 'errorFetchingSuggestions')}: ${response.reasonPhrase}");
      }
    } on TimeoutException catch (_) {
      if (mounted) {
        final now = DateTime.now();
        if (_lastSnackbarTime == null || now.difference(_lastSnackbarTime!) > Duration(seconds: 20)) {
          _lastSnackbarTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(LanguageConfig.getLocalizedString(languageCode, 'timeoutError')),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      print("${LanguageConfig.getLocalizedString(languageCode, 'errorFetchingSuggestions')}: $e");
    }
  }

  Future<void> _setDestination() async {
    if (_addressController.text.isNotEmpty) {
      String address = _addressController.text.trim();
      // Check if "Portugal" is already in the address (case-insensitive)
      if (!address.toLowerCase().contains('portugal')) {
        address += ', Portugal';
      }
      final LatLng? destination = await _getCoordinatesFromAddress(address);

      if (destination != null) {
        // Smoothly move the map to the destination
        _animatedMapMove(destination, 15.0); // Zoom level 15 for closer view
        setState(() {
          _destinationLocation = destination;
          _suggestions.clear();
        });

        if (_currentLocation != null) {
          await _fetchRoute(
            // LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
            // const LatLng(38.902464, -9.163266), // Current location for testing Ribas de Baixo
            // const LatLng(37.08000502817415, -8.113855290887736), // Test with coordinates of Edificio Portugal
            // const LatLng(41.7013562, -8.1685668), // Current location for testing in the North (type: são bento de sexta freita)
            // const LatLng(41.641963, -7.949505), // Current location for testing in the North (type: minas da borralha)
            const LatLng(38.756546, -9.155300), //Current location for testing at FCUL
            destination,
          );
        }
      }
    }
  }

  // Function to re-adjust the zoom when a route is set
  LatLngBounds _calculateBounds(List<LatLng> points) {
    if (points.isEmpty) {
      throw Exception("Cannot calculate bounds for an empty route.");
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (LatLng point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    // Calculate the approximate range
    double latRange = maxLat - minLat;
    double lngRange = maxLng - minLng;

    // Determine buffer dynamically based on the route's size
    double buffer = (latRange + lngRange) * 0.15; // 15% of total span
    double bottomBuffer = buffer * 4; // Extra buffer at the bottom

    return LatLngBounds(
      LatLng(minLat - bottomBuffer, minLng - buffer), // Bottom-left corner
      LatLng(maxLat + buffer, maxLng + buffer), // Top-right corner
    );
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    final latTween = Tween<double>(
        begin: _currentCenter.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(
        begin: _currentCenter.longitude, end: destLocation.longitude);
    final zoomTween = Tween<double>(begin: _currentZoom, end: destZoom);

    final controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    final Animation<double> animation =
        CurvedAnimation(parent: controller, curve: Curves.fastOutSlowIn);

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.dispose();
      } else if (status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });
    controller.forward();
  }

  Future<void> fetchUserPreferences() async {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    try {
      final preferences = await _profileController.fetchUserProfile();
      if (mounted) {
        setState(() {
          userPreferences = preferences;
        });
      }
    } catch (e) {
      print("${LanguageConfig.getLocalizedString(languageCode, 'errorFetchingSuggestions')}: $e");
    }
  }

  double _calculateScreenX(LatLng latLng, {double offsetXFactor = 0.05}) {
    final bounds = _mapController.camera.visibleBounds;
    final width = MediaQuery.of(context).size.width;
    double zoomFactor = 1 / _mapController.camera.zoom.clamp(1.0, 20.0); // Normalize zoom

    double x = ((latLng.longitude - bounds.west) / (bounds.east - bounds.west)) * width;
    return x + (width * offsetXFactor * zoomFactor); // Adjust offset dynamically
  }

  double _calculateScreenY(LatLng latLng, {double offsetYFactor = -0.05}) {
    final bounds = _mapController.camera.visibleBounds;
    final height = MediaQuery.of(context).size.height;
    double zoomFactor = 1 / _mapController.camera.zoom.clamp(1.0, 20.0); // Normalize zoom

    double y = ((bounds.north - latLng.latitude) / (bounds.north - bounds.south)) * height;
    return y + (height * offsetYFactor * zoomFactor); // Adjust offset dynamically
  }

  String? calculateArrivalTime(String travelTime) {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
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

      // if (totalMinutes == 0) {
      //   print(LanguageConfig.getLocalizedString(languageCode, 'invalidTime'));
      //   return null;
      // }

      DateTime arrivalTime = now.add(Duration(minutes: totalMinutes));

      // Format the time in 24-hour format (e.g., 13:45)
      String formattedTime = "${arrivalTime.hour.toString().padLeft(2, '0')}:${arrivalTime.minute.toString().padLeft(2, '0')}";

      return formattedTime;
    } catch (e) {
      print("${LanguageConfig.getLocalizedString(languageCode, 'errorFetchingRoute')}: $e");
    }
    return null;
  }

  void _reCenter() {
    if (_currentLocation != null) {
      _mapController.moveAndRotate(
        // LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
        // LatLng(38.902464, -9.163266), // Test with coordinates of Ribas de Baixo
        // LatLng(37.08000502817415, -8.113855290887736), // Test with coordinates of Edificio Portugal
        // LatLng(41.7013562, -8.1685668), // Current location for testing in the North (type: são bento de sexta freita)
        // const LatLng(41.641963, -7.949505), // Current location for testing in the North (type: minas da borralha)
        const LatLng(38.756546, -9.155300), //Current location for testing at FCUL //TODO: PARA TESTES PLANEAMENTO DEVE ESTAR ESTA OPÇÃO ATIVA
        HomeConfig.defaultZoom, // initialZoom
        0.0, // Reset rotation to 0 degrees
      );
      // print("HomeConfig.defaultZoom: ${HomeConfig.defaultZoom}");
    }
  }

  Widget _buildInfoBox(BuildContext context, int i) {
    var entry = _routesWithPoints.entries.elementAt(i);
    var routeSegments = entry.value;

    if (routeSegments.isEmpty) return const SizedBox.shrink();

    var midSegmentIndex = routeSegments.length ~/ 2;
    if (midSegmentIndex >= routeSegments.length) midSegmentIndex = routeSegments.length - 1;
    if (midSegmentIndex < 0) midSegmentIndex = 0;

    LatLng midPoint = routeSegments[midSegmentIndex]['start'] as LatLng;

    double offsetDirection = (i % 2 == 0) ? -1.0 : 1.0;
    double screenX = _calculateScreenX(midPoint, offsetXFactor: 0.08 * offsetDirection);
    double screenY = _calculateScreenY(midPoint, offsetYFactor: 0.08 * offsetDirection);

    bool isSelectedRoute = entry.key == _selectedRouteKey;
    bool isAdjustedRoute = entry.key == 'adjustedRoute';

    Color boxColor = isSelectedRoute
        ? Colors.purple.withValues(alpha: 0.8)
        : Colors.grey.withValues(alpha: 0.6);
    Color textColor = isSelectedRoute ? Colors.white : Colors.black;

    double iconSize = MediaQuery.of(context).size.width * 0.04;
    double padding = MediaQuery.of(context).size.width * 0.022;
    double fontSize = MediaQuery.of(context).size.width * 0.032;

    return Positioned(
      left: screenX,
      top: screenY,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedRouteKey = entry.key;
          });
        },
        child: Container(
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: boxColor,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isAdjustedRoute)
                Icon(Icons.star, color: Colors.yellow, size: iconSize),
              Text(
                "${_times[entry.key]}",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  fontSize: fontSize,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _locationUpdateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Ensure the state is kept alive.
    String languageCode = Provider.of<UserPreferences>(context).languageCode;

    final userPreferences = Provider.of<UserPreferences>(context, listen: false);
    bool lowRisk = userPreferences.lowRisk; // This gives you the updated value

    final selectedTime = _times[_selectedRouteKey];
    // print("selectedTime: $selectedTime");

    final String? arrivalTime = selectedTime != null
        ? calculateArrivalTime(selectedTime)
        : null;

    return 
      Scaffold(
        body: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
              initialCenter: const LatLng(0, 0),
              initialZoom: 12.0,
              onPositionChanged: (position, hasGesture) {
                _currentCenter = position.center;
                _currentZoom = position.zoom;
              },
            ),
              children: [
                TileLayer(
                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  subdomains: const ['a', 'b', 'c'],
                ),
                if (_routesWithPoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      // --- Other Routes (Not Selected) ---
                      ..._routesWithPoints.entries.expand<Polyline>((entry) {
                        if (entry.key == _selectedRouteKey) return [];

                        final routeSegments = entry.value;
                        if (routeSegments.isEmpty) return [];

                        final List<LatLng> points = [];

                        // Add the start point of the first segment
                        if (routeSegments.first['start'] is LatLng) {
                          points.add(routeSegments.first['start'] as LatLng);
                        }

                        // Add the end point of each segment
                        for (final segment in routeSegments) {
                          if (segment['end'] is LatLng) {
                            points.add(segment['end'] as LatLng);
                          }
                        }

                        if (points.length < 2) return [];

                        return [
                          Polyline(
                            points: points,
                            strokeWidth: 8.0,
                            color: const Color.fromRGBO(171, 145, 242, 0.9),
                          ),
                          Polyline(
                            points: points,
                            strokeWidth: 4.0,
                            color: const Color.fromRGBO(211, 173, 253, 0.9),
                          ),
                        ];
                      }),

                      // --- SELECTED ROUTE with dynamic color and unified border ---
                      if (_routesWithPoints.containsKey(_selectedRouteKey)) ...() {
                        final selectedRouteSegments = _routesWithPoints[_selectedRouteKey]!;

                        final List<Polyline> selectedPolylines = [];

                        final List<LatLng> selectedRouteAllPoints = [];
                        if (selectedRouteSegments.isNotEmpty) {
                          if (selectedRouteSegments.first['start'] is LatLng) {
                            selectedRouteAllPoints.add(selectedRouteSegments.first['start'] as LatLng);
                          }
                          for (final segment in selectedRouteSegments) {
                            if (segment['end'] is LatLng) {
                              selectedRouteAllPoints.add(segment['end'] as LatLng);
                            }
                          }
                        }

                        if (selectedRouteAllPoints.length >= 2) {
                          selectedPolylines.add(
                            Polyline(
                              points: selectedRouteAllPoints,
                              strokeWidth: 8.0,
                              color: Colors.black.withValues(alpha:0.8),
                            ),
                          );
                        }

                        for (final segment in selectedRouteSegments) {
                          final startPoint = segment['start'] as LatLng;
                          final endPoint = segment['end'] as LatLng;

                          Color lineColor;
                          final raster = segment['raster_value'];

                          if (raster != null) {
                            if (raster > highRisk) {
                              lineColor = Colors.red;
                            } else if (raster > mediumHighRisk) {
                              lineColor = Colors.deepOrangeAccent;
                            } else if (raster > mediumRisk) {
                              lineColor = Colors.orange;
                            } else if (raster > mediumLowRisk) {
                              lineColor = Colors.yellow;
                            } else {
                              lineColor = Colors.purple;
                            }
                          } else {
                            lineColor = Colors.purple;
                          }

                          selectedPolylines.add(
                            Polyline(
                              points: [startPoint, endPoint],
                              strokeWidth: 4.0,
                              color: lineColor,
                            ),
                          );
                        }

                        return selectedPolylines;
                      }(),
                    ],
                  ),
                  if (_currentLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        // point: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
                        // point: LatLng(38.902464, -9.163266), // Test with coordinates of Ribas de Baixo
                        // point: LatLng(37.08000502817415, -8.113855290887736), // Test with coordinates of Edificio Portugal
                        // point: LatLng(41.7013562, -8.1685668), // Current location for testing in the North (type: são bento de sexta freita)
                        // point: const LatLng(41.641963, -7.949505), // Current location for testing in the North (type: minas da borralha)
                        point: LatLng(38.756546, -9.155300), //Current location for testing at FCUL
                        child: Image(
                          image: const AssetImage("assets/icons/pin.png"),
                          width: MediaQuery.of(context).size.width * 0.11,
                        ),
                      ),
                    ],
                  ),
                if (_destinationLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _destinationLocation!,
                        child: Image(
                          image: const AssetImage("assets/icons/pin_final.png"),
                          width: MediaQuery.of(context).size.width * 0.11, 
                          height: MediaQuery.of(context).size.width * 0.11,
                        ),
                      ),
                    ],
                  ),
                  Stack(
                    children: [
                      // First render all UNSELECTED info boxes
                      for (var i = 0; i < _routesWithPoints.entries.length; i++)
                        if (_routesWithPoints.entries.elementAt(i).value.isNotEmpty &&
                            _routesWithPoints.entries.elementAt(i).key != _selectedRouteKey)
                          _buildInfoBox(context, i),

                      // Then render the SELECTED info box last (on top)
                      for (var i = 0; i < _routesWithPoints.entries.length; i++)
                        if (_routesWithPoints.entries.elementAt(i).key == _selectedRouteKey)
                          _buildInfoBox(context, i),
                    ],
                  ),

            Positioned(
              top: MediaQuery.of(context).size.height * 0.05, 
              left: MediaQuery.of(context).size.width * 0.025, 
              right: MediaQuery.of(context).size.width * 0.025, 
              child: Column(
                children: [
             
                  TextField(
                    controller: _addressController,
                    readOnly: destinationSelected,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(50.0),
                      ),
                      labelText: LanguageConfig.getLocalizedString(languageCode, 'enterDestination'),
                      filled: true,
                      // fillColor: Colors.white,
                      prefixIcon: Icon(Icons.search, size: MediaQuery.of(context).size.width * 0.06), 
                      suffixIcon: IconButton(
                        icon: Icon(Icons.close, size: MediaQuery.of(context).size.width * 0.06), 
                        onPressed: () {
                          navigationBarKey.currentState?.toggleNavigationBar(true);

                          // Crucially, close the http client to cancel the request
                          _httpClient?.close();
                          _httpClient = null; // Clear the client reference

                          // Reset the map state and UI elements
                          setState(() {
                            _cancelFetchingRoute = true; // Set this flag
                            _resetRouteUI(); // Call to reset UI
                          });

                          // Center the map on the user's current location
                          if (_currentLocation != null) {
                            _mapController.move(
                              // LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
                              // LatLng(38.902464, -9.163266), // Test with coordinates of Ribas de Baixo
                              // LatLng(37.08000502817415, -8.113855290887736), // Test with coordinates of Edificio Portugal
                              // LatLng(41.7013562, -8.1685668), // Current location for testing in the North (type: são bento de sexta freita)
                              // const LatLng(41.641963, -7.949505), // Current location for testing in the North (type: minas da borralha)
                              const LatLng(38.756546, -9.155300), //Current location for testing at FCUL
                              13.0, // Adjust zoom level as needed
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  if (_isFetchingRoute) // Fetching a route and doesn't have a route
                    LinearProgressIndicator(
                      value: null, // Indeterminate progress
                      // backgroundColor: Colors.grey[200],
                      // color: Colors.black,
                    ), 
                  const SizedBox(height: 8.0),
                  if (_suggestions.isNotEmpty && !destinationSelected)
                    MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: Container(
                        color: Theme.of(context).colorScheme.onPrimary,
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _suggestions.length,
                          itemBuilder: (context, index) {
                            final suggestion = _suggestions[index];
                            return ListTile(
                              title: Text(
                                suggestion['name'] ?? LanguageConfig.getLocalizedString(languageCode, 'country'),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: MediaQuery.of(context).size.width * 0.04,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  suggestion['locality'],
                                  suggestion['city'],
                                  suggestion['county'],
                                  suggestion['country'] ?? LanguageConfig.getLocalizedString(languageCode, 'country'),
                                ]
                                    .where((part) => part != null && part.toString().trim().isNotEmpty)
                                    .join(', '),
                                style: TextStyle(
                                  fontSize: MediaQuery.of(context).size.width * 0.03,
                                ),
                              ),
                              onTap: () {
                                _addressController.text = [
                                  suggestion['name'],
                                  suggestion['city'],
                                  suggestion['country']
                                ].where((part) => part != null && part.isNotEmpty).join(', ');

                                FocusScope.of(context).unfocus(); // Dismiss the keyboard

                                setState(() {
                                  _suggestions.clear();
                                  destinationSelected = true;
                                  selectedDestination = _addressController.text;
                                  setDestVis = false;
                                });
                                _setDestination();
                              },
                            );
                          },
                          separatorBuilder: (context, index) => Divider(
                            color: Colors.grey[300],
                            thickness: 1,
                            height: 1,
                          ),
                        ),
                      ),
                    ),

                  if (_routesWithPoints.isEmpty && setDestVis && _addressController.text.isNotEmpty)
                    ElevatedButton(
                      onPressed: () {
                        _setDestination();
                        setState(() {
                          setDestVis = false;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.secondary,
                        padding: EdgeInsets.symmetric(
                          vertical: MediaQuery.of(context).size.height * 0.02, 
                          horizontal: MediaQuery.of(context).size.width * 0.05, 
                        ),
                      ),
                      child: Text(
                        LanguageConfig.getLocalizedString(languageCode, 'setDestination'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSecondary,
                          fontSize: MediaQuery.of(context).size.width * 0.035, 
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              bottom: MediaQuery.of(context).size.width * 0.05,
              right: MediaQuery.of(context).size.width * 0.05,
              child: FloatingActionButton(
                onPressed: _reCenter,
                // mini: true, // Make it a smaller button
                backgroundColor: Theme.of(context).colorScheme.secondary,
                child: Icon(Icons.gps_fixed, color: Theme.of(context).colorScheme.onSecondary),
              ),
            ),
            //button when 
            if (_routesWithPoints.isNotEmpty)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: _boxHeight,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    // color: Colors.white,
                    color: Theme.of(context).colorScheme.onPrimary,
                    shape: BoxShape.rectangle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey,
                        spreadRadius: 5,
                        blurRadius: 7,
                        offset: Offset(0, 5), // changes position of shadow
                      ),
                    ],
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(30.0),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_routesWithPoints[_selectedRouteKey] != null)
                        ...() {
                          final selectedRoute = _routesWithPoints[_selectedRouteKey]!;
                          bool hasHighRisk = selectedRoute.any((point) => point['raster_value'] > highRisk);
                          bool hasMediumHighRisk = selectedRoute.any((point) =>
                              point['raster_value'] > mediumHighRisk && point['raster_value'] <= highRisk);
                          bool hasMediumRisk = selectedRoute.any((point) =>
                              point['raster_value'] > mediumRisk && point['raster_value'] <= mediumHighRisk);
                          bool hasMediumLowRisk = selectedRoute.any((point) =>
                              point['raster_value'] > mediumLowRisk && point['raster_value'] <= mediumRisk);

                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            setState(() {
                              _boxHeight = (hasHighRisk || hasMediumRisk || hasMediumHighRisk || hasMediumLowRisk)
                                  ? MediaQuery.of(context).size.height * HomeConfig.adjustedRiskBoxHeight
                                  : MediaQuery.of(context).size.height * HomeConfig.defaultRiskBoxHeight;
                            });
                          });

                          String buildMessage(String key, Set<String> species, String? distance) {
                            final speciesText = species.map((s) => LanguageConfig.getLocalizedString(languageCode, s)).join(', ');
                            final distanceText = distance != null && distance.isNotEmpty
                                ? " ${LanguageConfig.getLocalizedString(languageCode, 'in')} $distance"
                                : "";
                            return "${LanguageConfig.getLocalizedString(languageCode, key)} $speciesText$distanceText";
                          }

                          String? riskDistance = _distancesAtMaxRisk[_selectedRouteKey];


                          if (hasHighRisk) {
                            Set<String> speciesList = selectedRoute
                                .where((point) => point['raster_value'] > highRisk)
                                .expand((point) => List<String>.from(point['species']))
                                .toSet();

                            return [
                              Flexible(
                                child: _buildRiskMessage(
                                  buildMessage('highProbability', speciesList, riskDistance),
                                  Colors.red,
                                  context,
                                ),
                              ),
                              SizedBox(height: MediaQuery.of(context).size.height * 0.03),
                            ];
                          } else if (hasMediumHighRisk) {
                            Set<String> speciesList = selectedRoute
                                .where((point) =>
                                    point['raster_value'] > mediumHighRisk && point['raster_value'] <= highRisk)
                                .expand((point) => List<String>.from(point['species']))
                                .toSet();

                            return [
                              Flexible(
                                child: _buildRiskMessage(
                                  buildMessage('mediumHighProbability', speciesList, riskDistance),
                                  Colors.deepOrangeAccent,
                                  context,
                                ),
                              ),
                              SizedBox(height: MediaQuery.of(context).size.height * 0.03),
                            ];
                          } else if (hasMediumRisk) {
                            Set<String> speciesList = selectedRoute
                                .where((point) =>
                                    point['raster_value'] > mediumRisk && point['raster_value'] <= mediumHighRisk)
                                .expand((point) => List<String>.from(point['species']))
                                .toSet();

                            return [
                              Flexible(
                                child: _buildRiskMessage(
                                  buildMessage('mediumProbability', speciesList, riskDistance),
                                  const Color.fromRGBO(224, 174, 41, 1),
                                  context,
                                ),
                              ),
                              SizedBox(height: MediaQuery.of(context).size.height * 0.03),
                            ];
                          } else if (hasMediumLowRisk) {
                            Set<String> speciesList = selectedRoute
                                .where((point) =>
                                    point['raster_value'] > mediumLowRisk && point['raster_value'] <= mediumRisk)
                                .expand((point) => List<String>.from(point['species']))
                                .toSet();

                            return [
                              Flexible(
                                child: _buildRiskMessage(
                                  buildMessage('mediumLowProbability', speciesList, riskDistance),
                                  Colors.yellow,
                                  context,
                                ),
                              ),
                              SizedBox(height: MediaQuery.of(context).size.height * 0.03),
                            ];
                          }
                          return [];
                        }(),
                      if (_routesWithPoints.isNotEmpty)
                       Center(
                         child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).size.width * 0.05),
                          child: Column(
                            children: [
                              // MAIN ROW: Left image column + Right route info column
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,  // Align content at the start of the row
                                children: [
                                  // LEFT COLUMN - Image
                                  SizedBox(
                                    width: MediaQuery.of(context).size.width * 0.16,  // Width of the image column
                                    child: Center(
                                      child: Image(
                                        image: _selectedRouteKey == 'adjustedRoute'
                                            ? const AssetImage("assets/icons/frog_green.png")
                                            : (_routesWithPoints.containsKey('adjustedRoute')
                                                ? const AssetImage("assets/icons/frog_orange.png")
                                                : const AssetImage("assets/icons/frog_green.png")),
                                        width: MediaQuery.of(context).size.width * 0.14,  // Adjust image size
                                      ),
                                    ),
                                  ),
                         
                                  SizedBox(width: MediaQuery.of(context).size.width * 0.03), // Space between the image and text columns
                         
                                  // RIGHT COLUMN - Route Info
                                  Expanded(
                                    child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Arrival Time
                                      Text(
                                        "${LanguageConfig.getLocalizedString(languageCode, 'arrivalTime')} ${calculateArrivalTime(_times[_selectedRouteKey]!) ?? LanguageConfig.getLocalizedString(languageCode, 'unknown')}",
                                        style: TextStyle(
                                          fontSize: MediaQuery.of(context).size.width * 0.045,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),

                                      const SizedBox(height: 4),

                                      // Comment below arrival time (dynamic cost comparison)
                                      Builder(
                                        builder: (context) {
                                          if (_selectedRouteKey == 'adjustedRoute') {
                                            return Text(
                                              LanguageConfig.getLocalizedString(languageCode, 'bestToAvoidRoadkill'),
                                              style: TextStyle(
                                                fontSize: MediaQuery.of(context).size.width * 0.03,
                                                color: Colors.grey[700],
                                              ),
                                            );
                                          }

                                          if (_routesWithPoints.containsKey('adjustedRoute') && _routesWithPoints.containsKey('defaultRoute')) {
                                            double calculateRiskAwareCost(List<Map<String, dynamic>> segments) {
                                              return segments.fold(0.0, (sum, segment) {
                                                final double distance = (segment['segment_distance'] ?? 0.0).toDouble();
                                                final double risk = (segment['raster_value'] ?? 0.0).toDouble();
                                                return sum + (distance * (1 + risk * 4));
                                              });
                                            }

                                            final adjustedCost = calculateRiskAwareCost(_routesWithPoints['adjustedRoute']!);
                                            final selectedCost = calculateRiskAwareCost(_routesWithPoints[_selectedRouteKey]!);

                                            print("adjustedCost: $adjustedCost");
                                            print("selectedCost: $selectedCost");

                                            if (adjustedCost > 0) {
                                              final costFactor = selectedCost / adjustedCost;
                                              final template = LanguageConfig.getLocalizedString(languageCode, 'routeCostMultiplier');
                                              final message = template.replaceAll('{x}', costFactor.toStringAsFixed(2));
                                              return Text(
                                                message,
                                                style: TextStyle(
                                                  fontSize: MediaQuery.of(context).size.width * 0.03,
                                                  color: Colors.grey[700],
                                                ),
                                              );
                                            }
                                          }

                                          // Default fallback message
                                          return Text(
                                            LanguageConfig.getLocalizedString(languageCode, 'bestToAvoidRoadkill'),
                                            style: TextStyle(
                                              fontSize: MediaQuery.of(context).size.width * 0.03,
                                              color: Colors.grey[700],
                                            ),
                                          );
                                        },
                                      ),

                                      SizedBox(height: MediaQuery.of(context).size.height * 0.01),

                                      // Distance + Duration row
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            _distances[_selectedRouteKey] ?? LanguageConfig.getLocalizedString(languageCode, 'unknown'),
                                            style: TextStyle(
                                              fontSize: MediaQuery.of(context).size.width * 0.036,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const SizedBox(
                                            height: 15,
                                            child: VerticalDivider(
                                              color: Colors.grey,
                                              width: 1,
                                              thickness: 1,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _times[_selectedRouteKey] ?? LanguageConfig.getLocalizedString(languageCode, 'unknown'),
                                            style: TextStyle(
                                              fontSize: MediaQuery.of(context).size.width * 0.036,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  ),
                                  SizedBox(width: MediaQuery.of(context).size.width * 0.03), 

                                  // Conditionally display the Switch Route Button if 'adjustedRoute' exists
                                  if (_routesWithPoints.containsKey('adjustedRoute') && !lowRisk)
                                    Column(
                                      children: [
                                        ElevatedButton(
                                          onPressed: () {
                                            setState(() {
                                              final keys = _routesWithPoints.keys.toList();
                                              int currentIndex = keys.indexOf(_selectedRouteKey);
                                              _selectedRouteKey = keys[(currentIndex + 1) % keys.length];
                                            });
                                          },
                                          style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
                                          child: Text(
                                            LanguageConfig.getLocalizedString(languageCode, 'switchRoute'),
                                            style: TextStyle(
                                              fontSize: MediaQuery.of(context).size.width * 0.040,
                                              color: Theme.of(context).colorScheme.onPrimary,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                         
                              SizedBox(height: MediaQuery.of(context).size.height * 0.020), 
                         
                              // BOTTOM ROW: Start button
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  ElevatedButton(
                                    onPressed: () {
                                      if (_routesWithPoints.containsKey(_selectedRouteKey)) {
                                        List<Map<String, dynamic>> selectedRoute = _routesWithPoints[_selectedRouteKey] ?? [];

                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => LoadingNavigationPage(
                                              _routesWithPoints,
                                              _selectedRouteKey,
                                              selectedRoute,
                                              _distances,
                                              _times,
                                              arrivalTime,
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                     style: ElevatedButton.styleFrom(
                                        backgroundColor: _selectedRouteKey == 'adjustedRoute' ||
                                                !_routesWithPoints.containsKey('adjustedRoute')
                                            ? Colors.green
                                            : const Color.fromRGBO(224, 174, 41, 1),
                                      ),
                                    child: Text(
                                      LanguageConfig.getLocalizedString(languageCode, 'start'),
                                      style: TextStyle(
                                        fontSize: MediaQuery.of(context).size.width * 0.045,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                       )
                    ]
                  ),
                ),
              ),
            ]),
          ],
        ),
      );
  }
}

Widget _buildRiskMessage(String text, Color color, BuildContext context) {
  double screenWidth = MediaQuery.of(context).size.width;

  String imagePath;
  if (color == Colors.red) {
    imagePath = "assets/icons/warning_red.png";
  } else if (color == Colors.deepOrangeAccent) {
    imagePath = "assets/icons/warning_deepOrange.png";
  } else if (color == Color.fromRGBO(224, 174, 41, 1)) {
    imagePath = "assets/icons/warning_orange.png";
  } else if (color == Colors.yellow) {
    imagePath = "assets/icons/warning_yellow.png";
  } else{
    imagePath = "assets/icons/warning_yellow.png";
  }

  return Padding(
    padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image(
          image: AssetImage(imagePath),
          width: screenWidth * 0.14,
        ),
        SizedBox(width: screenWidth * 0.05),
        Expanded( // Wrap the Text widget with Expanded
          child: Text(
            text,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: screenWidth * 0.045,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}
