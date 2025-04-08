import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:latlong2/latlong.dart';
import 'package:safe_roads/pages/navigation.dart'; 

class LoadingNavigationPage extends StatefulWidget {
  final Map<String, List<Map<String, dynamic>>> routesWithPoints;
  final String selectedRouteKey;
  final List<Map<String, dynamic>> routeCoordinates;
  final Map<String, String> distances;
  final Map<String, String> times;

  const LoadingNavigationPage(
    this.routesWithPoints,
    this.selectedRouteKey,
    this.routeCoordinates,
    this.distances,
    this.times,
    {super.key}
  );

  @override
  State<LoadingNavigationPage> createState() => _LoadingNavigationPageState();
}

class _LoadingNavigationPageState extends State<LoadingNavigationPage> {
  final Location location = Location();
  LatLng? currentPosition;

  @override
  void initState() {
    super.initState();
    _initializeAndNavigate();
  }

  Future<void> _initializeAndNavigate() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    // Location service
    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) return;
    }

    // Permissions
    permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return;
    }

    // Initial location
    final loc = await location.getLocation();
    currentPosition = LatLng(loc.latitude!, loc.longitude!);

    // Wait 3 extra seconds to simulate map load (optional)
    await Future.delayed(const Duration(seconds: 3));
    
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => NavigationPage(
          widget.routesWithPoints,
          widget.selectedRouteKey,
          widget.routeCoordinates,
          widget.distances,
          widget.times,
          initialPosition: currentPosition, // Pass the position
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: screenWidth * 0.1,
              height: screenWidth * 0.1,
              child: const CircularProgressIndicator(
                strokeWidth: 3,
              ),
            ),
            SizedBox(height: screenHeight * 0.03),
            Text(
              'Loading your route',
              style: TextStyle(
                fontSize: screenWidth * 0.05,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
