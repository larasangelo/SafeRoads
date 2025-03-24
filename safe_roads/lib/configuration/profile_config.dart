import 'package:flutter/material.dart';

class ProfileConfig {
  static const bool defaultLowRisk = true;
  static const bool defaultChangeRoute = true;
  static const bool defaultNotifications = true;
  static const bool defaultTolls = false;
  static const String defaultMeasure = "km";
  static const String defaultRiskAlertDistance = "250 m";
  static const String defaultRerouteAlertDistance = "250 m";

  static const String defaultUsername = "Loading...";
  static const String defaultCountry = "Loading...";
  static const int defaultLevel = 1;
  static const int defaultDistance = 0;
  static const int defaultTargetDistance = 200;
  static const int defaultTotalKm = 0;
  static const int defaultPlaces = 0;
  static const String defaultAvatar = 'assets/profile_images/avatar_1.jpg';

  static const List<Map<String, dynamic>> speciesOptions = [
    {"key": "amphibians", "icon": Icons.water},
    {"key": "reptiles", "icon": Icons.grass},
    {"key": "hedgehogs", "icon": Icons.pets},
  ];

  static const List<Object?> defaultSelectedSpecies = ["Amphibians"];
  static const String defaultLanguage = "en"; 
}
