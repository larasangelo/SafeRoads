import 'package:latlong2/latlong.dart';

class HomeConfig {
  static const LatLng defaultCenter = LatLng(0, 0);
  static const double defaultZoom = 13.0;
  static const double defaultBoxHeight = 200;
  static const String defaultRouteKey = "";

  static Map<String, List<Map<String, dynamic>>> defaultRoutesWithPoints = {};
  static Map<String, String> defaultDistances = {};
  static Map<String, String> defaultTimes = {};
  static Map<String, String> defaultDistancesAtMaxRisk = {};

  static bool defaultDestinationSelected = false;
  static bool defaultSetDestVis = true;
  static bool defaultIsFetchingRoute = false;
  static bool defaultCancelFetchingRoute = false;

  static String? defaultSelectedDestination;
  static Map<String, dynamic> defaultUserPreferences = {};

  static const double defaultRiskBoxHeight = 0.3;
  static const double adjustedRiskBoxHeight = 0.4;

  static double mediumLowRisk = 0.2;
  static double mediumRisk = 0.3;
  static double mediumHighRisk = 0.5;
  static double highRisk = 0.6;
}
