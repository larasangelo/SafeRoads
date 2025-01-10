import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'package:safe_roads/main.dart';
import 'package:safe_roads/pages/navigation.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin  {
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final MapController _mapController = MapController();
  // final Notifications _notifications = Notifications();
  // String? fcmToken;
  LocationData? _currentLocation;
  LatLng? _destinationLocation;
  List<LatLng> _routePoints = []; // Stores points for the polyline
  final TextEditingController _addressController = TextEditingController();
  List<Map<String, dynamic>> _suggestions = []; // Stores autocomplete suggestions
  Timer? _debounce; // To avoid over calling the API
  LatLng _currentCenter = const LatLng(0, 0);
  double _currentZoom = 13.0;
  bool destinationSelected = false;
  String? selectedDestination;
  String distance = "0";
  String time = "0";
  bool setDestVis = true;
  bool _isFetchingRoute = false;
  bool _cancelFetchingRoute = false;


  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
    _setupAutocompleteListener();
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
          const LatLng(38.902464, -9.163266), // Test with coordinates of Ribas de Baixo
          // const LatLng(37.08000502817415, -8.113855290887736), // Test with coordinates of Edificio Portugal
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

      final response = await http.post(
        Uri.parse('http://192.168.1.82:3000/route'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "start": {"lat": start.latitude, "lon": start.longitude},
          "end": {"lat": end.latitude, "lon": end.longitude},
        }),
      );

      final raster = await http.post(
        Uri.parse('http://192.168.1.82:3000/raster'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "point": {"lat": start.latitude, "lon": start.longitude},
        }),
      );

      if (raster.statusCode == 200) {
        final rasterData = jsonDecode(response.body);
        print("data, $rasterData");

      } else {
        print("Error fetching suggestions: ${response.reasonPhrase}");
      }

      if (_cancelFetchingRoute) return; // Exit if route-fetching is canceled

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<LatLng> points = (data['route'] as List).map((point) {
          return LatLng(point['lat'], point['lon']);
        }).toList();
        String totalDistanceKm = data['distance'];
        String totalTimeMinutes = data['time'];

        // Hide the navigation bar when the user gets the route
        navigationBarKey.currentState?.toggleNavigationBar(false);

        setState(() {
          _routePoints = points;
          distance = totalDistanceKm;
          time = totalTimeMinutes;
          _isFetchingRoute = false; // Hide the progress bar
        });

        if (points.isNotEmpty) {
          // Calculate bounds and adjust map view
          LatLngBounds bounds = _calculateBounds(points);
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
            const LatLng(38.902464, -9.163266), // Current location for testing Ribas de Baixo
            // const LatLng(37.08000502817415, -8.113855290887736), // Test with coordinates of Edificio Portugal
            destination,
          );

        }
      }
    }
  }

  // Function to re-adjust the zoom when a route is set
  LatLngBounds _calculateBounds(List<LatLng> points) {
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

    // Calculate the approximate distance in degrees
    double latRange = maxLat - minLat;
    double lngRange = maxLng - minLng;
    
    // Determine buffer based on the route's size
    double dynamicBuffer = (latRange + lngRange) * 0.1; // Adjust multiplier as needed
    
    // Add a larger buffer to the bottom for the overlay
    double bottomBuffer = dynamicBuffer * 2; // Double the buffer for the bottom if needed

    return LatLngBounds(
      LatLng(minLat - bottomBuffer, minLng - dynamicBuffer),
      LatLng(maxLat + dynamicBuffer, maxLng + dynamicBuffer),
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
                // TileLayer(
                //   urlTemplate: "http://192.168.1.82:3000/tiles/{z}/{x}/{y}.png",
                //   subdomains: const ['a', 'b', 'c'],
                //   // opacity: 0.6, // Adjust transparency
                // ),
                if (_currentLocation != null)
                  const MarkerLayer(
                    markers: [
                      Marker(
                        // point: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
                        point: LatLng(38.902464, -9.163266), // Test with coordinates of Ribas de Baixo
                        // point: LatLng(37.08000502817415, -8.113855290887736), // Test with coordinates of Edificio Portugal
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
                if (_routePoints.isNotEmpty)
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
                            _routePoints.clear();
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
                              const LatLng(38.902464, -9.163266), // Test with coordinates of Ribas de Baixo
                              // const LatLng(37.08000502817415, -8.113855290887736), // Test with coordinates of Edificio Portugal
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
                  if(_routePoints.isEmpty && setDestVis)
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
            if (_routePoints.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 150,
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          distance,
                          style: const TextStyle(
                            fontSize: 22.0,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(width: 30), // Add some spacing
                        Text(
                          time,
                          style: const TextStyle(
                            fontSize: 22.0,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20), // Add some spacing
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => NavigationPage(_routePoints, distance, time),
                          ),
                        );
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
    );
  }
}
