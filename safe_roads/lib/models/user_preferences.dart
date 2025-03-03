import 'package:flutter/material.dart';

class UserPreferences with ChangeNotifier {
  bool _reRoute = false;  // Ensure it's non-null
  String _alertDistance = "100 m";

  bool get reRoute => _reRoute;
  String get alertDistance => _alertDistance;

  void updateReRoute(bool newValue) {
    _reRoute = newValue;
    notifyListeners();
  }

  void updateAlertDistance(String newValue) {
    _alertDistance = newValue;
    notifyListeners();
  }
}
