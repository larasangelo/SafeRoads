import 'package:flutter/material.dart';

class UserPreferences with ChangeNotifier {
  bool _reRoute = false;  // Ensure it's non-null
  String _riskAlertDistance = "100 m";
  String _rerouteAlertDistance = "250 m";

  bool get reRoute => _reRoute;
  String get riskAlertDistance => _riskAlertDistance;
  String get rerouteAlertDistance => _rerouteAlertDistance;

  void updateReRoute(bool newValue) {
    _reRoute = newValue;
    notifyListeners();
  }

  void updateRiskAlertDistance(String newValue) {
    _riskAlertDistance = newValue;
    notifyListeners();
  }

  void updateRerouteAlertDistance(String newValue) {
    _rerouteAlertDistance = newValue;
    notifyListeners();
  }
}
