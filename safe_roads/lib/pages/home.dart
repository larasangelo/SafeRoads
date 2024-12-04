import 'dart:async';
import 'dart:convert';
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
  final MapController _mapController = MapController();
  LocationData? _currentLocation;
  LatLng? _destinationLocation;
  List<LatLng> _routePoints = []; // Stores points for the polyline
  final TextEditingController _addressController = TextEditingController();
  List<Map<String, dynamic>> _suggestions = []; // Stores autocomplete suggestions
  Timer? _debounce; // To avoid over calling the API


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
          LatLng(38.902464, -9.163266), // Test with coordinates of Ribas de Baixo
          13.0,
        );
      }
    });
  }

  Future<void> _fetchRoute(LatLng start, LatLng end) async {
    try {
      final response = await http.post(
        Uri.parse('http://192.168.56.1:3000/route'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "start": {"lat": start.latitude, "lon": start.longitude},
          "end": {"lat": end.latitude, "lon": end.longitude},
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<LatLng> points = (data['route'] as List).map((point) {
          return LatLng(point['lat'], point['lon']);
        }).toList();

        setState(() {
          _routePoints = points;
        });

        if (points.isNotEmpty) {
          // Calculate bounds and adjust map view
          LatLngBounds bounds = _calculateBounds(points);
          _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: EdgeInsets.all(20))); // Padding for better visibility
        }
      } else {
        throw Exception("Failed to fetch route: ${response.body}");
      }
    } catch (e) {
      print("Error fetching route: $e");
    }
  }

  Future<LatLng?> _getCoordinatesFromAddress(String address) async {
    try {
      final response = await http.post(
        Uri.parse('http://192.168.56.1:3000/geocode'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"address": address}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final lat = data['lat'];
        final lon = data['lon'];
        return LatLng(lat, lon);
      } else {
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text("Error: ${jsonDecode(response.body)['error']}")),
        );
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
        if (query.length > 2) {
          _fetchSearchSuggestions(query);
        } else {
          setState(() {
            _suggestions.clear(); // Clear if text is too short
          });
        }
      });
    });
  }



Future<void> _fetchSearchSuggestions(String query) async {
  try {
    final response = await http.get(
      Uri.parse('http://192.168.56.1:3000/search?query=${Uri.encodeComponent(query)}&limit=5&lang=en'),
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


  // 
  Future<void> _setDestination() async {
    if (_addressController.text.isNotEmpty) {
      final LatLng? destination = await _getCoordinatesFromAddress(_addressController.text);
      if (destination != null) {
        setState(() {
          _destinationLocation = destination;
        });

        if (_currentLocation != null) {
          await _fetchRoute(
            // LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
            LatLng(38.902464, -9.163266), // Test with coordinates of Ribas de Baixo
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

    return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: Scaffold(
        body: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(0, 0),
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
                        // point: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
                        point: LatLng(38.902464, -9.163266), // Test with coordinates of Ribas de Baixo
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
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
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
                    controller: _addressController,
                    decoration: InputDecoration(
                      labelText: "Enter Destination",
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8.0),
                  if (_suggestions.isNotEmpty)
                    Container(
                      color: Colors.white,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _suggestions.length,
                        itemBuilder: (context, index) {
                          // Assuming _suggestions holds a list of maps with name, city, and country
                          final suggestion = _suggestions[index];
                          return ListTile(
                            title: Text(
                              suggestion['name'], // Name of the place
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              '${suggestion['city']}, ${suggestion['country']}', // City and country
                              style: const TextStyle(fontSize: 12), // Smaller font size
                            ),
                            onTap: () {
                              // When tapped, set the selected address in the text field and clear suggestions
                              _addressController.text = suggestion['name'];
                              setState(() {
                                _suggestions.clear(); // Clear suggestions after selection
                              });
                            },
                          );
                        },
                      ),
                    ),
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
