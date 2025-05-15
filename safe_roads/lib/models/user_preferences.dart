import 'package:flutter/material.dart';
import 'package:safe_roads/configuration/profile_config.dart';
import 'package:safe_roads/controllers/profile_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserPreferences with ChangeNotifier {
  final ProfileController _profileController = ProfileController();

  bool _lowRisk = ProfileConfig.defaultLowRisk;
  String _riskAlertDistance = ProfileConfig.defaultRiskAlertDistance;
  String _rerouteAlertDistance = ProfileConfig.defaultRerouteAlertDistance;
  bool _changeRoute = ProfileConfig.defaultChangeRoute;
  List<Object?> _selectedSpecies = ProfileConfig.defaultSelectedSpecies;
  String _languageCode = ProfileConfig.defaultLanguage; // Default language


  bool get lowRisk => _lowRisk;
  String get riskAlertDistance => _riskAlertDistance;
  String get rerouteAlertDistance => _rerouteAlertDistance;
  bool get changeRoute => _changeRoute;
  List<Object?> get selectedSpecies => _selectedSpecies;
  String get languageCode => _languageCode;

  UserPreferences() {
    initializePreferences();
  }

  Future<void> initializePreferences() async {
    await loadPreferences();
  }

  Future<void> loadPreferences() async {
    try {
      final userProfile = await _profileController.fetchUserProfile();
      _lowRisk = userProfile['lowRisk'] ?? ProfileConfig.defaultLowRisk;
      _riskAlertDistance = userProfile['riskAlertDistance'] ?? ProfileConfig.defaultRiskAlertDistance;
      _rerouteAlertDistance = userProfile['rerouteAlertDistance'] ?? ProfileConfig.defaultRerouteAlertDistance;
      _changeRoute = userProfile['changeRoute'] ?? ProfileConfig.defaultChangeRoute;
      _selectedSpecies = userProfile['selectedSpecies'] ?? ProfileConfig.defaultSelectedSpecies;
      _languageCode = userProfile['selectedLanguage'] ?? ProfileConfig.defaultLanguage;

      // Save selected species to SharedPreferences
      SharedPreferences preferences = await SharedPreferences.getInstance();
      await preferences.setStringList('selectedSpecies', List<String>.from(_selectedSpecies));
      
      print("USER_PREFERENCES loadPreferences: $_selectedSpecies");
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

  void updateSelectedSpecies(List<Object?> newSelectedSpecies) {
    _selectedSpecies = newSelectedSpecies;
    print("USER_PREFERENCES updateSelectedSpecies: $_selectedSpecies");
    notifyListeners();
  }

  void updateLanguage(String newLanguage) {
    _languageCode = newLanguage;
    notifyListeners();
  }
}
