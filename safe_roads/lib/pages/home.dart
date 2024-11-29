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
  List<LatLng> _routePoints = [];
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
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
          // LatLng(42.336388, -7.863333), // Test with coordinates of Coruña
          LatLng(38.902464, -9.163266), // Test with coordinates of Ribas de Baixo
          13.0,
        );
      }
    });
  }

  Future<void> _fetchRoute(LatLng start, LatLng end) async {
    try {
      final response = await http.post(
        Uri.parse('http://192.168.1.82:3000/route'),
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
          _mapController.move(points.first, 13.0);
        }
      } else {
        throw Exception("Failed to fetch route: ${response.body}");
      }
    } catch (e) {
      print("Error fetching route: $e");
    }
  }

  void _setDestination() async {
    if (_latController.text.isNotEmpty && _lngController.text.isNotEmpty) {
      final double lat = double.parse(_latController.text);
      final double lng = double.parse(_lngController.text);

      LatLng destination = LatLng(lat, lng);
      setState(() {
        _destinationLocation = destination;
      });

      if (_currentLocation != null) {
        await _fetchRoute(
          // LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
          // LatLng(42.336388, -7.863333), // Test with coordinates of Coruña
          LatLng(38.902464, -9.163266), // Test with coordinates of Ribas de Baixo
          destination,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: Scaffold(
        appBar: AppBar(title: const Text("Safe Roads")),
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
                  TextField(
                    controller: _latController,
                    decoration: const InputDecoration(
                      labelText: "Destination Latitude",
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8.0),
                  TextField(
                    controller: _lngController,
                    decoration: const InputDecoration(
                      labelText: "Destination Longitude",
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8.0),
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
