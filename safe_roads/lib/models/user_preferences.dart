import 'package:flutter/material.dart';
import 'package:safe_roads/controllers/profile_controller.dart';

class UserPreferences with ChangeNotifier {
  final ProfileController _profileController = ProfileController();

  bool _lowRisk = false;
  String _riskAlertDistance = "100 m";
  String _rerouteAlertDistance = "250 m";
  bool _changeRoute = true;

  bool get lowRisk => _lowRisk;
  String get riskAlertDistance => _riskAlertDistance;
  String get rerouteAlertDistance => _rerouteAlertDistance;
  bool get changeRoute => _changeRoute;

  UserPreferences() {
    loadPreferences();
  }

  Future<void> loadPreferences() async {
    try {
      final userProfile = await _profileController.fetchUserProfile();
      _lowRisk = userProfile['lowRisk'] ?? false;
      _riskAlertDistance = userProfile['riskAlertDistance'] ?? "100 m";
      _rerouteAlertDistance = userProfile['rerouteAlertDistance'] ?? "250 m";
      _changeRoute = userProfile['changeRoute'] ?? true;
      notifyListeners();
    } catch (e) {
      print("Error loading user preferences: $e");
    }
  }

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
