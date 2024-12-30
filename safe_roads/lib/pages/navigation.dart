import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart'; // For coordinates
import 'package:location/location.dart';
import 'package:http/http.dart' as http;

class NavigationPage extends StatefulWidget {
  final List<LatLng> routeCoordinates;

  NavigationPage(this.routeCoordinates);

  @override
  _NavigationPageState createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  late Location location;
  LatLng? currentPosition;
  StreamSubscription<LocationData>? locationSubscription;

  @override
  void initState() {
    super.initState();
    location = Location();

    // Start tracking location
    locationSubscription = location.onLocationChanged.listen((LocationData loc) {
      setState(() {
        currentPosition = LatLng(loc.latitude!, loc.longitude!);
      });
      _sendPositionToServer(loc.latitude!, loc.longitude!);
    });
  }

  Future<void> _sendPositionToServer(double lat, double lon) async {
    try {
      await http.post(
        Uri.parse('http://yourserver.com/update-position'),
        body: {
          'userId': '123', // Example user ID
          'lat': lat.toString(),
          'lon': lon.toString(),
        },
      );
    } catch (e) {
      print("Error sending position: $e");
    }
  }

  @override
  void dispose() {
    locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Navigation")),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: currentPosition ?? widget.routeCoordinates.first,
              initialZoom: 19.0,
            ),
            children: [
              TileLayer(
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                subdomains: ['a', 'b', 'c'],
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: widget.routeCoordinates,
                    strokeWidth: 4.0,
                    color: Colors.blue,
                  ),
                ],
              ),
              if (currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: currentPosition!,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Stop navigation and return to the previous page
              },
              child: Text("Stop"),
            ),
          ),
        ],
      ),
    );
  }
}
