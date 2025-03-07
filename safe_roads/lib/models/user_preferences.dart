import 'package:flutter/material.dart';

class UserPreferences with ChangeNotifier {
  bool _lowRisk = false;  
  String _riskAlertDistance = "100 m";
  String _rerouteAlertDistance = "250 m";
  bool _changeRoute = true;  

  bool get lowRisk => _lowRisk;
  String get riskAlertDistance => _riskAlertDistance;
  String get rerouteAlertDistance => _rerouteAlertDistance;
  bool get changeRoute => _changeRoute;

  void updateLowRisk(bool newValue) {
    _lowRisk = newValue;
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
  
  void updateChangeRoute(bool newValue) {
    _changeRoute = newValue;
    notifyListeners();
  }
}
