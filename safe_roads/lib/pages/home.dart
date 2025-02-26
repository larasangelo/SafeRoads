import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'package:safe_roads/controllers/profile_controller.dart';
import 'package:safe_roads/main.dart';
import 'package:safe_roads/models/user_preferences.dart';
import 'package:safe_roads/pages/navigation.dart';
import 'package:provider/provider.dart'; // Import the Provider package

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin  {
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final MapController _mapController = MapController();
  LocationData? _currentLocation;
  LatLng? _destinationLocation;
  Map<String, List<Map<String, dynamic>>> _routesWithPoints = {};
  final TextEditingController _addressController = TextEditingController();
  List<Map<String, dynamic>> _suggestions = []; // Stores autocomplete suggestions
  Timer? _debounce; // To avoid over calling the API
  LatLng _currentCenter = const LatLng(0, 0);
  double _currentZoom = 13.0;
  bool destinationSelected = false;
  String? selectedDestination;
  Map<String, String> _distances = {};
  Map<String, String> _times = {};
  Map<String, bool> _hasRisk = {}; 
  bool setDestVis = true;
  bool _isFetchingRoute = false;
  bool _cancelFetchingRoute = false;
  final ProfileController _profileController = ProfileController();
  Map<String, dynamic> userPreferences = {};
  String _selectedRouteKey = ""; // Default value, updated when routes are fetched
  double _boxHeight = 200;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
    _setupAutocompleteListener();
    fetchUserPreferences();
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
          const LatLng(41.7013562, -8.1685668), // Current location for testing in the North 
          13.0,
        );
      }
    });
  }

  Future<void> _fetchRoute(LatLng start, LatLng end) async {
    try {
      setState(() {
        _isFetchingRoute = true; // Show the progress bar
        _cancelFetchingRoute = false; // Reset the cancellation flag
      });

      // Access the updated value of 'reRoute' from the UserPreferences provider
      final userPreferences = Provider.of<UserPreferences>(context, listen: false);
      bool reRoute = userPreferences.reRoute; // This gives you the updated value
      print("reRoute: $reRoute");

      final response = await http.post(
        Uri.parse('http://192.168.1.82:3000/route'),
        // Uri.parse('http://10.101.121.132:3000/route'), // Para testar na uni
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "start": {"lat": start.latitude, "lon": start.longitude},
          "end": {"lat": end.latitude, "lon": end.longitude},
          "re_route": reRoute, // Use the updated value of reRoute
          // "re_route": userPreferences["re_route"], // Use the updated value of reRoute
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
              'raster_value': point['raster_value']
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
          _hasRisk = hasRisk;
          _boxHeight = _hasRisk[_selectedRouteKey] == true ? 220 : 180;
        });

        print("_boxHeight, $_boxHeight");

        // Adjust map view to fit all routes
        if (routesWithPoints.isNotEmpty) {
          List<LatLng> allPoints = routesWithPoints.values.expand((list) => list.map((p) => p['latlng'] as LatLng)).toList();
          LatLngBounds bounds = _calculateBounds(allPoints);
          _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(20)));
        }
      } else {
        throw Exception("Failed to fetch route: ${response.body}");
      }
    } catch (e) {
      if (!_cancelFetchingRoute) {
        print("Error fetching route: $e");
      }
      setState(() {
        _isFetchingRoute = false; // Hide the progress bar
      });
    }
  }

  Future<LatLng?> _getCoordinatesFromAddress(String address) async {
    try {
      final response = await http.post(
        Uri.parse('http://192.168.1.82:3000/geocode'),
        // Uri.parse('http://10.101.121.132:3000/geocode'), // Para testar na uni
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"address": address}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final lat = data['lat'];
        final lon = data['lon'];
        return LatLng(lat, lon);
      } else {
        // scaffoldMessengerKey.currentState?.showSnackBar(
        //   SnackBar(content: Text("Error: ${jsonDecode(response.body)['error']}")),
        // );
        print("Error: ${jsonDecode(response.body)['error']}");
      }
    } catch (e) {
      print("Error fetching coordinates: $e");
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
    try {
      final response = await http.get(
        Uri.parse('http://192.168.1.82:3000/search?query=${Uri.encodeComponent(query)}&limit=5&lang=en'),
        // Uri.parse('http://10.101.121.132:3000/search?query=${Uri.encodeComponent(query)}&limit=5&lang=en'), // Para testar na uni
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
        print("Error fetching suggestions: ${response.reasonPhrase}");
      }
    } catch (e) {
      print("Error fetching suggestions: $e");
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
            const LatLng(41.7013562, -8.1685668), // Current location for testing in the North 
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
    double buffer = (latRange + lngRange) * 0.1; // 10% of total span
    double bottomBuffer = buffer * 2; // Extra buffer at the bottom

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
    try {
      final preferences = await _profileController.fetchUserProfile();
      if (mounted) {
        setState(() {
          userPreferences = preferences;
        });
      }
    } catch (e) {
      print("Error fetching preferences: $e");
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
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: Scaffold(
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
                  const MarkerLayer(
                    markers: [
                      Marker(
                        // point: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
                        // point: LatLng(38.902464, -9.163266), // Test with coordinates of Ribas de Baixo
                        // point: LatLng(37.08000502817415, -8.113855290887736), // Test with coordinates of Edificio Portugal
                        point: LatLng(41.7013562, -8.1685668), // Current location for testing in the Nsorth 
                        child: Icon(Icons.location_pin, color: Colors.blue, size: 40),
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
                if (_routesWithPoints.isNotEmpty)
                  PolylineLayer(
                    polylines: _routesWithPoints.entries.expand<Polyline>((entry) {
                      final List<Map<String, dynamic>> routePoints = entry.value;
                      if (routePoints.length < 2) return [];

                      bool isSelectedRoute = entry.key == _selectedRouteKey;
                      double opacity = isSelectedRoute ? 1.0 : 0.1; // Lower opacity for unselected routes

                      return List.generate(routePoints.length - 1, (index) {
                        final current = routePoints[index];
                        final next = routePoints[index + 1];

                        if (current['latlng'] is! LatLng || next['latlng'] is! LatLng) return null;

                        // Have different colors for different Raster Values
                        Color lineColor;
                        if (current['raster_value'] > 3) {
                          lineColor = Colors.red.withOpacity(opacity);
                        } else if (current['raster_value'] > 2) {
                          lineColor = Colors.orange.withOpacity(opacity);
                        } else {
                          lineColor = Colors.purple.withOpacity(opacity);
                        }

                        return Polyline(
                          points: [current['latlng'] as LatLng, next['latlng'] as LatLng],
                          strokeWidth: 4.0,
                          color: lineColor,
                        );
                      }).whereType<Polyline>(); // Filter out null values
                    }).toList(),
                  ),
                  Stack(
                    children: [
                      // Add Info Boxes on Routes
                      for (var entry in _routesWithPoints.entries) 
                        if (entry.value.isNotEmpty)
                          Positioned(
                            left: _calculateScreenX(entry.value[entry.value.length ~/ 2]['latlng']),
                            top: _calculateScreenY(entry.value[entry.value.length ~/ 2]['latlng']),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                              ),
                              child: Column(
                                children: [
                                  Text("${_times[entry.key]}", style: const TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ),
            Positioned(
              top: 40.0,
              left: 10.0,
              right: 10.0,
              child: Column(
                children: [
                  if (_isFetchingRoute)       // Esta fetching a route E Nao tem a route
                  LinearProgressIndicator(
                    value: null, // Indeterminate progress
                    backgroundColor: Colors.grey[200],
                    color: Colors.blue,
                  ),  // Nao esta fetching a route E ja tem a route
                  TextField(
                    controller: _addressController,
                    decoration: InputDecoration(
                      labelText: "Enter Destination",
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close),
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
                              // const LatLng(38.902464, -9.163266), // Test with coordinates of Ribas de Baixo
                              // const LatLng(37.08000502817415, -8.113855290887736), // Test with coordinates of Edificio Portugal
                              const LatLng(41.7013562, -8.1685668), // Current location for testing in the North 
                              13.0, // Adjust zoom level as needed
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8.0),
                  if (_suggestions.isNotEmpty && !destinationSelected)
                    Container(
                      color: Colors.white,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _suggestions.length,
                        itemBuilder: (context, index) {
                          // Assuming _suggestions holds a list of maps with name, city, and country
                          final suggestion = _suggestions[index];
                          return 
                          ListTile(
                            title: Text(
                              suggestion['name'], // Name of the place
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              suggestion['city'] != null && suggestion['city']!.isNotEmpty
                                  ? '${suggestion['city']}, ${suggestion['country']}' // City and country
                                  : '${suggestion['country']}', // Only country
                              style: const TextStyle(fontSize: 12), // Smaller font size
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
                            }
                          );
                        },
                      ),
                    ),
                  if(_routesWithPoints.isEmpty && setDestVis)
                  ElevatedButton(
                    onPressed: () {
                      _setDestination();
                      setState(() {
                        setDestVis = false;
                      });
                    },
                    child: const Text("Set Destination"),
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
                  height: _boxHeight, // Adjusted height for messages
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
                      // Display risk message if applicable
                      if (_routesWithPoints[_selectedRouteKey] != null)
                        ...() {
                          bool hasHighRisk = _routesWithPoints[_selectedRouteKey]!
                              .any((point) => point['raster_value'] > 3);
                          bool hasMediumRisk = _routesWithPoints[_selectedRouteKey]!
                              .any((point) => point['raster_value'] > 2 && point['raster_value'] <= 3);

                          if (hasHighRisk) {
                            return [
                              _buildRiskMessage("High probability of encountering amphibians", Colors.red),
                              const SizedBox(height: 20),
                            ];
                          } else if (hasMediumRisk) {
                            return [
                              _buildRiskMessage("Medium probability of encountering amphibians", Colors.orange),
                              const SizedBox(height: 20),
                            ];
                          }
                          return [];
                        }(),

                      if (_routesWithPoints.length > 1) 
                        // More than one route exists - Show switchable format
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                children: [
                                  Text(
                                    _distances[_selectedRouteKey] ?? "Unknown",
                                    style: const TextStyle(fontSize: 25.0, color: Colors.black),
                                  ),
                                  const SizedBox(height: 10),
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
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    ),
                                    child: const Text(
                                      "Switch Route",
                                      style: TextStyle(fontSize: 18.0),
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                children: [
                                  Text(
                                    _times[_selectedRouteKey] ?? "Unknown",
                                    style: const TextStyle(fontSize: 25.0, color: Colors.black),
                                  ),
                                  const SizedBox(height: 10),
                                  ElevatedButton(
                                    onPressed: () {
                                      if (_routesWithPoints.containsKey(_selectedRouteKey)) {
                                        List<Map<String, dynamic>> selectedRoute = _routesWithPoints[_selectedRouteKey] ?? [];

                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => NavigationPage(
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
                                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                                    ),
                                    child: const Text(
                                      "Start",
                                      style: TextStyle(fontSize: 18.0),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      else 
                        // Only one route exists - Show simple format
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 180,
                            alignment: Alignment.center,
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
                                      _distances[_selectedRouteKey] ?? "Unknown",
                                      style: const TextStyle(fontSize: 25.0, color: Colors.black),
                                    ),
                                    const SizedBox(width: 50),
                                    Text(
                                      _times[_selectedRouteKey] ?? "Unknown",
                                      style: const TextStyle(fontSize: 25.0, color: Colors.black),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton(
                                  onPressed: () {
                                    if (_routesWithPoints.containsKey(_selectedRouteKey)) {
                                      List<Map<String, dynamic>> selectedRoute = _routesWithPoints[_selectedRouteKey] ?? [];

                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => NavigationPage(
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
                                  child: const Text(
                                    "Start",
                                    style: TextStyle(fontSize: 18.0),
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
      ),
    );
  }
}

Widget _buildRiskMessage(String text, Color color) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20.0),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center, // Centers content horizontally
      crossAxisAlignment: CrossAxisAlignment.center, // Aligns items properly
      children: [
        Icon(Icons.warning, color: color, size: 40),
        const SizedBox(width: 30),
        Expanded( // Ensures text wraps properly
          child: Text(
            text,
            textAlign: TextAlign.left, // Centers text
            softWrap: true, // Allows text to wrap instead of overflowing
            overflow: TextOverflow.visible, // Ensures visibility
            style: TextStyle(
              fontSize: 22.0,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}



