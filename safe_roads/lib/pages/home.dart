import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'package:safe_roads/configuration/home_config.dart';
import 'package:safe_roads/configuration/language_config.dart';
import 'package:safe_roads/controllers/profile_controller.dart';
import 'package:safe_roads/main.dart';
import 'package:safe_roads/models/user_preferences.dart';
import 'package:safe_roads/pages/loading_navigation.dart';
// import 'package:safe_roads/pages/navigation.dart';
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
  bool setDestVis = HomeConfig.defaultSetDestVis;
  bool _isFetchingRoute = HomeConfig.defaultIsFetchingRoute;
  bool _cancelFetchingRoute = HomeConfig.defaultCancelFetchingRoute;
  final ProfileController _profileController = ProfileController();
  Map<String, dynamic> userPreferences = HomeConfig.defaultUserPreferences;
  String _selectedRouteKey = HomeConfig.defaultRouteKey;
  double _boxHeight = HomeConfig.defaultBoxHeight;

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
          const LatLng(41.641963, -7.949505), // Current location for testing in the North (type: minas da borralha)
          13.0,
        );
      }
    });
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
      bool lowRisk = userPreferences.lowRisk; // This gives you the updated value
      List<Object?> selectedSpecies = userPreferences.selectedSpecies;

      print("lowRisk: $lowRisk");
      print("HOME selectedSpecies: $selectedSpecies");

      final response = await http.post(
        // Uri.parse('http://192.168.1.82:3000/route'),
        Uri.parse('http://10.101.121.183:3000/route'), // Para testar na uni
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "start": {"lat": start.latitude, "lon": start.longitude},
          "end": {"lat": end.latitude, "lon": end.longitude},
          "lowRisk": lowRisk, 
          "selectedSpecies": selectedSpecies,
        }),
      );

      if (_cancelFetchingRoute) return; // Exit if route-fetching is canceled

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Iterate through returned routes (defaultRoute and/or adjustedRoute)
        Map<String, List<Map<String, dynamic>>> routesWithPoints = {};
        Map<String, String> distances = {};
        Map<String, String> times = {};
        Map<String, bool> hasRisk = {}; 

        data.forEach((key, routeData) {
          List<Map<String, dynamic>> pointsWithRaster = (routeData['route'] as List).map((point) {
            return {
              'latlng': LatLng(point['lat'], point['lon']),
              'raster_value': point['raster_value'],
              'species': point['species'],
            };
          }).toList();

          routesWithPoints[key] = pointsWithRaster;
          distances[key] = routeData['distance'];
          times[key] = routeData['time'];
          hasRisk[key] = routeData['hasRisk'];
        });

        print(routesWithPoints['defaultRoute']);

        // Hide the navigation bar when the user gets the route
        navigationBarKey.currentState?.toggleNavigationBar(false);

        setState(() {
          _routesWithPoints = routesWithPoints;
          _distances = distances;
          _times = times;
          _isFetchingRoute = false; // Hide the progress bar
          _selectedRouteKey = _routesWithPoints.keys.first;
        });

        // Adjust map view to fit all routes
        if (routesWithPoints.isNotEmpty) {
          List<LatLng> allPoints = routesWithPoints.values.expand((list) => list.map((p) => p['latlng'] as LatLng)).toList();
          LatLngBounds bounds = _calculateBounds(allPoints);
          _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(25)));
        }
      } else {
        throw Exception("${LanguageConfig.getLocalizedString(languageCode, 'failFetchingRoute')}: ${response.body}");
      }
    } catch (e) {
      if (!_cancelFetchingRoute) {
        print("${LanguageConfig.getLocalizedString(languageCode, 'errorFetchingRoute')}: $e");
      }
      setState(() {
        _isFetchingRoute = false; // Hide the progress bar
      });
    }
  }

  Future<LatLng?> _getCoordinatesFromAddress(String address) async {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    try {
      final response = await http.post(
        // Uri.parse('http://192.168.1.82:3000/geocode'),
        Uri.parse('http://10.101.121.183:3000/geocode'), // Para testar na uni
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

  Future<void> _fetchSearchSuggestions(String query) async {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    try {
      final response = await http.get(
        // Uri.parse('http://192.168.1.82:3000/search?query=${Uri.encodeComponent(query)}&limit=5&lang=en'),
        Uri.parse('http://10.101.121.183:3000/search?query=${Uri.encodeComponent(query)}&limit=5&lang=en'), // Para testar na uni
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<Map<String, dynamic>> suggestions = (data['features'] as List).map((feature) {
          final props = feature['properties'];
          return {
            'name': props['name'],
            'city': props['city'] ?? '',
            'country': props['country'] ?? '',
          };
        }).toList();

        setState(() {
          _suggestions = suggestions;
        });
      } else {
        print("${LanguageConfig.getLocalizedString(languageCode, 'errorFetchingSuggestions')}: ${response.reasonPhrase}");
      }
    } catch (e) {
      print("${LanguageConfig.getLocalizedString(languageCode, 'errorFetchingSuggestions')}: $e");
    }
  }

  Future<void> _setDestination() async {
    if (_addressController.text.isNotEmpty) {
      final LatLng? destination = await _getCoordinatesFromAddress(_addressController.text);
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
            const LatLng(41.641963, -7.949505), // Current location for testing in the North (type: minas da borralha)
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
    double bottomBuffer = buffer * 3; // Extra buffer at the bottom

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

  @override
  Widget build(BuildContext context) {
    super.build(context); // Ensure the state is kept alive.
    String languageCode = Provider.of<UserPreferences>(context).languageCode;

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
                if (_currentLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        // point: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
                        // point: LatLng(38.902464, -9.163266), // Test with coordinates of Ribas de Baixo
                        // point: LatLng(37.08000502817415, -8.113855290887736), // Test with coordinates of Edificio Portugal
                        // point: LatLng(41.7013562, -8.1685668), // Current location for testing in the North (type: são bento de sexta freita)
                        point: LatLng(41.641963, -7.949505), // Current location for testing in the North (type: minas da borralha)
                        child: Icon(Icons.location_pin, color: Colors.black, size: MediaQuery.of(context).size.width * 0.11),
                      ),
                    ],
                  ),
                if (_destinationLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _destinationLocation!,
                        child: Icon(Icons.location_pin, color: Colors.red, size: MediaQuery.of(context).size.width * 0.11),
                      ),
                    ],
                  ),
                if (_routesWithPoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      // First, draw unselected routes (gray)
                      ..._routesWithPoints.entries.expand<Polyline>((entry) {
                        if (entry.key == _selectedRouteKey) return []; // Skip selected route for now
        
                        final List<Map<String, dynamic>> routePoints = entry.value;
                        if (routePoints.length < 2) return [];
        
                        return List.generate(routePoints.length - 1, (index) {
                          final current = routePoints[index];
                          final next = routePoints[index + 1];
        
                          if (current['latlng'] is! LatLng || next['latlng'] is! LatLng) return null;
        
                          return Polyline(
                            points: [current['latlng'] as LatLng, next['latlng'] as LatLng],
                            strokeWidth: 4.0,
                            color: Colors.grey.withOpacity(0.7), // Always gray for unselected routes
                          );
                        }).whereType<Polyline>(); // Remove null values
                      }),
        
                      // Now, draw the selected route last (so it's on top)
                      if (_routesWithPoints.containsKey(_selectedRouteKey))
                        ..._routesWithPoints[_selectedRouteKey]!.sublist(0, _routesWithPoints[_selectedRouteKey]!.length - 1).map((current) {
                          final next = _routesWithPoints[_selectedRouteKey]![_routesWithPoints[_selectedRouteKey]!.indexOf(current) + 1];
        
                          if (current['latlng'] is! LatLng || next['latlng'] is! LatLng) return null;
        
                          Color lineColor;
                          if (current['raster_value'] > 0.5) {
                            lineColor = Colors.red;
                          } else if (current['raster_value'] > 0.3) {
                            lineColor = Colors.orange;
                          } else {
                            lineColor = Colors.purple;
                          }
        
                          return Polyline(
                            points: [current['latlng'] as LatLng, next['latlng'] as LatLng],
                            strokeWidth: 4.0,
                            color: lineColor, // Selected route is colored
                          );
                        }).whereType<Polyline>(),
                    ],
                  ),
                  Stack(
                    children: [
                      // Add Info Boxes on Routes
                      for (var i = 0; i < _routesWithPoints.entries.length; i++) 
                        if (_routesWithPoints.entries.elementAt(i).value.isNotEmpty)
                          Builder(
                            builder: (context) {
                              var entry = _routesWithPoints.entries.elementAt(i);
                              var routePoints = entry.value;
                              var midPointIndex = routePoints.length ~/ 2;

                              // Get midpoint coordinates
                              LatLng midPoint = routePoints[midPointIndex]['latlng'];

                              // Compute dynamic offset to avoid overlap
                              double offsetDirection = (i % 2 == 0) ? -1.0 : 1.0; // Alternate sides
                              double screenX = _calculateScreenX(midPoint, offsetXFactor: 0.08 * offsetDirection);
                              double screenY = _calculateScreenY(midPoint, offsetYFactor: 0.08 * offsetDirection);

                              // Ensure selected route's box is more visible
                              bool isSelectedRoute = entry.key == _selectedRouteKey;
                              bool isAdjustedRoute = entry.key == 'adjustedRoute'; // Check if it's the adjusted route
                              Color boxColor = isSelectedRoute ? Colors.purple.withOpacity(0.8) : Colors.grey.withOpacity(0.6);
                              Color textColor = isSelectedRoute ? Colors.white : Colors.black;

                              // MediaQuery for dynamic sizing based on screen size
                              double iconSize = MediaQuery.of(context).size.width * 0.04; 
                              double padding = MediaQuery.of(context).size.width * 0.022; 
                              double fontSize = MediaQuery.of(context).size.width * 0.032; 

                              return Positioned(
                                left: screenX,
                                top: screenY,
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
                                      if (isAdjustedRoute) // Show an icon for the adjusted route
                                        Icon(Icons.star, color: Colors.yellow, size: iconSize),

                                      Text(
                                        "${_times[entry.key]}",
                                        style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: fontSize),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
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
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.search, size: MediaQuery.of(context).size.width * 0.06), 
                      suffixIcon: IconButton(
                        icon: Icon(Icons.close, size: MediaQuery.of(context).size.width * 0.06), 
                        onPressed: () {
                          navigationBarKey.currentState?.toggleNavigationBar(true);

                          // Reset the map state and UI elements
                          setState(() {
                            _cancelFetchingRoute = true; // Cancel the route-fetching process
                            _routesWithPoints.clear();
                            destinationSelected = false;
                            selectedDestination = "";
                            _destinationLocation = null;
                            _addressController.text = "";
                            _suggestions.clear();
                            setDestVis = true;
                            _isFetchingRoute = false;
                          });

                          // Center the map on the user's current location
                          if (_currentLocation != null) {
                            _mapController.move(
                              // LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
                              // LatLng(38.902464, -9.163266), // Test with coordinates of Ribas de Baixo
                              // LatLng(37.08000502817415, -8.113855290887736), // Test with coordinates of Edificio Portugal
                              // LatLng(41.7013562, -8.1685668), // Current location for testing in the North (type: são bento de sexta freita)
                              LatLng(41.641963, -7.949505), // Current location for testing in the North (type: minas da borralha)
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
                      backgroundColor: Colors.grey[200],
                      color: Colors.black,
                    ), 
                  const SizedBox(height: 8.0),
                  if (_suggestions.isNotEmpty && !destinationSelected)
                    Container(
                      color: Colors.white,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _suggestions.length,
                        itemBuilder: (context, index) {
                          final suggestion = _suggestions[index];
                          return ListTile(
                            title: Text(
                              suggestion['name'] ?? LanguageConfig.getLocalizedString(languageCode, 'country'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: MediaQuery.of(context).size.width * 0.045, 
                              ),
                            ),
                            subtitle: Text(
                              (suggestion['city'] != null && suggestion['city']!.isNotEmpty)
                                  ? '${suggestion['city']}, ${suggestion['country']}'
                                  : (suggestion['country'] ?? LanguageConfig.getLocalizedString(languageCode, 'country')),
                              style: TextStyle(
                                fontSize: MediaQuery.of(context).size.width * 0.035, 
                              ),
                            ),
                            onTap: () {
                              // When a suggestion is tapped, update the text field, clear suggestions, and set the destinationSelected flag
                              _addressController.text = suggestion['name'];
                              FocusScope.of(context).unfocus(); // Dismiss the keyboard
                              setState(() {
                                _suggestions.clear();
                                destinationSelected = true;
                                selectedDestination = _addressController.text;
                              });
                            },
                          );
                        },
                      ),
                    ),
                  if (_routesWithPoints.isEmpty && setDestVis)
                    ElevatedButton(
                      onPressed: () {
                        _setDestination();
                        setState(() {
                          setDestVis = false;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        padding: EdgeInsets.symmetric(
                          vertical: MediaQuery.of(context).size.height * 0.02, 
                          horizontal: MediaQuery.of(context).size.width * 0.05, 
                        ),
                      ),
                      child: Text(
                        LanguageConfig.getLocalizedString(languageCode, 'setDestination'),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: MediaQuery.of(context).size.width * 0.035, 
                        ),
                      ),
                    ),
                ],
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
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.rectangle,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(30.0),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_routesWithPoints[_selectedRouteKey] != null)
                        ...() {
                          bool hasHighRisk = _routesWithPoints[_selectedRouteKey]!
                              .any((point) => point['raster_value'] > 0.5);
                          bool hasMediumRisk = _routesWithPoints[_selectedRouteKey]!
                              .any((point) => point['raster_value'] > 0.3 && point['raster_value'] <= 0.5);

                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            setState(() {
                              _boxHeight = (hasHighRisk || hasMediumRisk)
                                  ? MediaQuery.of(context).size.height * HomeConfig.adjustedRiskBoxHeight
                                  : MediaQuery.of(context).size.height * HomeConfig.defaultRiskBoxHeight;
                            });
                          });

                          if (hasHighRisk) {
                            Set<String> speciesList = {};
                            for (var point in _routesWithPoints[_selectedRouteKey]!) {
                              if (point['raster_value'] > 0.5) {
                                speciesList.addAll(List<String>.from(point['species']));
                              }
                            }

                            List<String> translatedSpecies = speciesList.map(
                              (species) => LanguageConfig.getLocalizedString(languageCode, species),
                            ).toList();

                            return [
                              Flexible(
                                child: _buildRiskMessage(
                                  "${LanguageConfig.getLocalizedString(languageCode, 'highProbability')} ${translatedSpecies.join(', ')}",
                                  Colors.red,
                                  context,
                                ),
                              ),
                              SizedBox(height: MediaQuery.of(context).size.height * 0.02), 
                            ];
                          } else if (hasMediumRisk) {
                            Set<String> speciesList = {};
                            for (var point in _routesWithPoints[_selectedRouteKey]!) {
                              if (point['raster_value'] > 0.3 && point['raster_value'] <= 0.5) {
                                speciesList.addAll(List<String>.from(point['species']));
                              }
                            }

                            List<String> translatedSpecies = speciesList.map(
                              (species) => LanguageConfig.getLocalizedString(languageCode, species),
                            ).toList();

                            return [
                              Flexible(
                                child: _buildRiskMessage(
                                  "${LanguageConfig.getLocalizedString(languageCode, 'mediumProbability')} ${translatedSpecies.join(', ')}",
                                  Colors.orange,
                                  context,
                                ),
                              ),
                              SizedBox(height: MediaQuery.of(context).size.height * 0.02), 
                            ];
                          }
                          return [];
                        }(),
                      if (_routesWithPoints.length > 1)
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: MediaQuery.of(context).size.width * 0.1), 
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                children: [
                                  Text(
                                    _distances[_selectedRouteKey] ?? LanguageConfig.getLocalizedString(languageCode, 'unknown'),
                                    style: TextStyle(
                                      fontSize: MediaQuery.of(context).size.width * 0.065, 
                                      color: Colors.black,
                                    ),
                                  ),
                                  SizedBox(height: MediaQuery.of(context).size.height * 0.01), 
                                  ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        final keys = _routesWithPoints.keys.toList();
                                        int currentIndex = keys.indexOf(_selectedRouteKey);
                                        _selectedRouteKey = keys[(currentIndex + 1) % keys.length];
                                      });
                                      print(" key: $_selectedRouteKey");
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.black,
                                    ),
                                    child: Text(
                                      LanguageConfig.getLocalizedString(languageCode, 'switchRoute'),
                                      style: TextStyle(
                                        fontSize: MediaQuery.of(context).size.width * 0.05, 
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                children: [
                                  Text(
                                    _times[_selectedRouteKey] ?? LanguageConfig.getLocalizedString(languageCode, 'unknown'),
                                    style: TextStyle(
                                      fontSize: MediaQuery.of(context).size.width * 0.065, 
                                      color: Colors.black,
                                    ),
                                  ),
                                  SizedBox(height: MediaQuery.of(context).size.height * 0.01),
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
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: (_selectedRouteKey == "defaultRoute") ? Colors.red : Colors.green,
                                    ),
                                    child: Text(
                                      LanguageConfig.getLocalizedString(languageCode, 'start'),
                                      style: TextStyle(
                                        fontSize: MediaQuery.of(context).size.width * 0.05, 
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      else
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            height: MediaQuery.of(context).size.height * 0.15, 
                            width: double.infinity,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.rectangle,
                              borderRadius: BorderRadius.vertical(top: Radius.circular(30.0)),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _distances[_selectedRouteKey] ?? LanguageConfig.getLocalizedString(languageCode, 'unknown'),
                                      style: TextStyle(
                                        fontSize: MediaQuery.of(context).size.width * 0.065, 
                                        color: Colors.black,
                                      ),
                                    ),
                                    SizedBox(width: MediaQuery.of(context).size.width * 0.1), 
                                    Text(
                                      _times[_selectedRouteKey] ?? LanguageConfig.getLocalizedString(languageCode, 'unknown'),
                                      style: TextStyle(
                                        fontSize: MediaQuery.of(context).size.width * 0.065, 
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: MediaQuery.of(context).size.height * 0.02), 
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
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                  ),
                                  child: Text(
                                    LanguageConfig.getLocalizedString(languageCode, 'start'),
                                    style: TextStyle(
                                      fontSize: MediaQuery.of(context).size.width * 0.05, 
                                      color: Colors.white,
                                    ),
                                  ),
                                ),

                              ],
                            ),
                          ),
                        ),
                    ],
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

  return Padding(
    padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.06), 
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.warning, color: color, size: screenWidth * 0.08), 
        SizedBox(width: screenWidth * 0.04), 
        Expanded(
          child: Text(
            text,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: screenWidth * 0.06, 
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}