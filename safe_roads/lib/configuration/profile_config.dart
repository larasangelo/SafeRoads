import 'package:flutter/material.dart';


class ProfileConfig {
  // Default Preferences
  static const bool defaultLowRisk = true;
  static const bool defaultChangeRoute = true;
  static const bool defaultNotifications = true;
  static const bool defaultTolls = false;
  static const String defaultMeasure = "km";
  static const String defaultRiskAlertDistance = "250 m";
  static const String defaultRerouteAlertDistance = "250 m";

  // Default User Info
  static const String defaultUsername = "Loading...";
  static const String defaultEmail = "Loading...";
  static const String defaultCountry = "Loading...";
  static const String defaultAvatar = 'assets/profile_images/avatar_1.jpg';

  // Default Profile Statistics
  static const int defaultLevel = 1;
  static const int defaultDistance = 0;
  static const int defaultTargetDistance = 200;
  static const int defaultTotalKm = 0;
  static const int defaultPlaces = 0;

  // Available Profile Avatars
  static const List<String> availableAvatars = [
    'assets/profile_images/avatar_1.jpg',
    'assets/profile_images/avatar_2.jpg',
    'assets/profile_images/avatar_3.jpg',
    'assets/profile_images/avatar_4.jpg',
    'assets/profile_images/avatar_5.jpg',
    'assets/profile_images/avatar_6.jpg',
  ];

  // Species Options with Localization Support
  static const List<Map<String, dynamic>> speciesOptions = [
    {"key": "amphibians", "icon": ImageIcon(AssetImage("assets/icons/frog.png"))},
    {"key": "reptiles", "icon": ImageIcon(AssetImage('assets/icons/snake.png'))},
    {"key": "hedgehogs", "icon": ImageIcon(AssetImage('assets/icons/hedgehog.png'))},
  ];

  // Default Selected Species
  static const List<String> defaultSelectedSpecies = ["amphibians"];

  // Language Configurations
  static const String defaultLanguage = "en";
}
