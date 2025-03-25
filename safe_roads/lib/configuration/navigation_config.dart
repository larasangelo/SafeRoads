import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:safe_roads/notifications.dart';

class NavigationConfig {

  static final Notifications notifications = Notifications();
  static double bearing = 0.0; // For map rotation
  static final MapController mapController = MapController();
  static bool isFirstLocationUpdate = true;
  static String estimatedArrivalTime = "??:??"; // To display the arrival time
  static bool isAnimating = false; // To prevent overlapping animations
  static bool destinationReached = false;
  static Set<LatLng> notifiedZones = {}; // Track notified risk zones
  static bool inRiskZone = false;
  static bool keepRoute = true;
  static Set<LatLng> passedSegments = {}; // Store segments already passed
  static int consecutiveOffRouteCount = 0; // Track how many times user is "off-route"
  static int offRouteThreshold = 7; // Require 7 consecutive off-route detections
  static bool lastOnRouteState = true; // Track last known on-route state
  static bool startRiskNotificationSent = false; // Track if the initial notification was sent
  static List<dynamic> notifiedDivergences = [];
  static bool firstRiskDetected = false;
  static String defaultTime = "0 min";
  static double cameraZoom = 19.0;
  static double threshold = 0.0001;
  static int animationSteps = 20;
  static int timePerStep = 50;

  static double routeDeviationThreshold = 50.0;
  static bool isOnRoute = false;
  static double highestUpcomingRisk = 0;
  static double currentRiskLevel = 0;
  static Set<LatLng> detectedRiskZones = {};  
  static Map<LatLng, double> upcomingRisks = {}; // Store multiple risk points

  static double mediumRisk = 0.3;
  static double highRisk = 0.5;

  static double pointsCloseThreshold = 30.0;
  static int reRouteReSend = 30;

}