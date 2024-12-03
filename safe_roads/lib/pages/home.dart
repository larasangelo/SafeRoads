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
  final TextEditingController _addressController = TextEditingController();

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
        // Uri.parse('http://192.168.1.82:3000/route'),
        Uri.parse('http://192.168.56.1:3000/route'), // Replace with your backend URL
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
        print("points:  $points ");

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

    Future<LatLng?> _getCoordinatesFromAddress(String address) async {
    try {
      // print("inside the _getCoodinates");
      final response = await http.post(
        // Uri.parse('http://192.168.1.82:3000/geocode'), // Replace with your backend URL
        Uri.parse('http://192.168.56.1:3000/geocode'), // Replace with your backend URL
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
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text("Failed to fetch coordinates")),
      );
    }
    return null;
  }


  // void _setDestination() async {
  //   if (_latController.text.isNotEmpty && _lngController.text.isNotEmpty) {
  //     final double lat = double.parse(_latController.text);
  //     final double lng = double.parse(_lngController.text);

  //     LatLng destination = LatLng(lat, lng);
  //     setState(() {
  //       _destinationLocation = destination;
  //     });

  //     if (_currentLocation != null) {
  //       await _fetchRoute(
  //         // LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
  //         // LatLng(42.336388, -7.863333), // Test with coordinates of Coruña
  //         LatLng(38.902464, -9.163266), // Test with coordinates of Ribas de Baixo
  //         destination,
  //       );
  //     }
  //   }
  // }
    Future<void> _setDestination() async {
    if (_addressController.text.isNotEmpty) {
      final LatLng? destination = await _getCoordinatesFromAddress(_addressController.text);
      if (destination != null) {
        setState(() {
          _destinationLocation = destination;
        });

        if (_currentLocation != null) {
          await _fetchRoute(
            LatLng(38.902464, -9.163266), // Test with coordinates of Ribas de Baixo
            destination,
          );
        }
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
//                         points: [                 
//  LatLng(38.9024504,  -9.1632766 ),
//  LatLng( 38.9022349, -9.1631267 ),

//  LatLng( 38.9022349, -9.1631267 ),
//  LatLng( 38.9021135, -9.1630423 ),

//  LatLng( 38.9021135, -9.1630423 ),
//  LatLng( 38.9019865, -9.1629071 ),
//  LatLng( 38.9019334, -9.1628878 ),

//  LatLng( 38.9017845, -9.162898 ),
//  LatLng( 38.9019334, -9.1628878 ),

//  LatLng( 38.9017845, -9.162898 ),
//  LatLng( 38.9017386, -9.1628296 ),
//  LatLng( 38.9016852, -9.162745 ),
//  LatLng( 38.9016637, -9.16261 ),
//  LatLng( 38.9016488, -9.1624625 ),


//  LatLng( 38.9015804, -9.1622714 ),
//  LatLng( 38.9016488, -9.1624625 ),

//  LatLng( 38.9015804, -9.1622714 ),
//  LatLng( 38.9015246, -9.1623293 ),
//  LatLng( 38.9015246, -9.162517 ),

//  ],
                      
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
                  // TextField(
                  //   controller: _latController,
                  //   decoration: const InputDecoration(
                  //     labelText: "Destination Latitude",
                  //     filled: true,
                  //     fillColor: Colors.white,
                  //   ),
                  //   keyboardType: TextInputType.number,
                  // ),
                  // const SizedBox(height: 8.0),
                  // TextField(
                  //   controller: _lngController,
                  //   decoration: const InputDecoration(
                  //     labelText: "Destination Longitude",
                  //     filled: true,
                  //     fillColor: Colors.white,
                  //   ),
                  //   keyboardType: TextInputType.number,
                  // ),
                  TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: "Destination",
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    keyboardType: TextInputType.text,
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
