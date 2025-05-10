import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:safe_roads/configuration/language_config.dart';
import 'package:safe_roads/models/user_preferences.dart';
import 'package:safe_roads/repositories/user_profile_repository.dart';
import '../models/auth_model.dart';

class AuthController {
  final AuthModel _authModel = AuthModel();
  final UserProfileRepository _userProfileRepository = UserProfileRepository();

  // Registering a new user
  Future<void> registerUser({
    required BuildContext context,
    required String username,
    required String email,
    required String password,
    required String confirmPassword,
  }) 
  async {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    if (username.isEmpty || email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showErrorDialog(context, LanguageConfig.getLocalizedString(languageCode, 'allFields'));
      return;
    }

    if (password != confirmPassword) {
      _showErrorDialog(context, LanguageConfig.getLocalizedString(languageCode, 'passNoMatch'));
      return;
    }

    try {
      final user = await _authModel.registerUser(email: email, password: password, username: username);
      if (user != null) {
        await _userProfileRepository.updateUserProfile(user.uid, {
          'lowRisk': false,
          'changeRoute': true,
          'tolls': true,
          'measure': 'km',
          'riskAlertDistance': "250 m",
          'rerouteAlertDistance': "250 m",
          'username': username,
          'country': 'Portugal',
          'email': email,
          'level': 1,
          'distance': 0,
          'totalKm': 0,
          'places': 0,
          'avatar': 'assets/profile_images/avatar_1.jpg',
          'selectedSpecies': ["amphibians"],
          'selectedLanguage': "en"
        });
      }
      if (context.mounted) {
        Navigator.pushNamed(context, '/login');
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorDialog(context, e.toString());
      }
    }
  }

  // Login a user
  Future<bool> loginUser({
    required BuildContext context,
    required String email,
    required String password,
  }) async {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    if (email.isEmpty || password.isEmpty) {
      _showErrorDialog(context, LanguageConfig.getLocalizedString(languageCode, 'emailAndPassRequired'));
      return false; // Return false if fields are empty
    }

    try {
      await _authModel.loginUser(email: email, password: password);

      // Login successful
      print("Login successful");
      return true;
    } catch (e) {
      if (context.mounted) {
        _showErrorDialog(context, e.toString());
      }
      return false; // Return false if login fails
    }
  }

  Future<void> logout() async {
    await _authModel.logout();
  }

  // Show error dialog
  void _showErrorDialog(BuildContext context, String message) {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(LanguageConfig.getLocalizedString(languageCode, 'error')),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }
}
