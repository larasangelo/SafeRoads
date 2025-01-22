import 'package:flutter/material.dart';
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
  }) async {
    if (username.isEmpty || email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showErrorDialog(context, "All fields are required.");
      return;
    }

    if (password != confirmPassword) {
      _showErrorDialog(context, "Passwords do not match.");
      return;
    }

    try {
      final user = await _authModel.registerUser(email: email, password: password, username: username);
      if (user != null) {
        await _userProfileRepository.updateUserProfile(user.uid, {
          'username': username,
          'email': email,
          'location': 'Portugal',
          'level': 1,
          'distance': 0,
          'targetDistance': 200,
          'totalKm': 0,
          'places': 0,
          'tolls': true,
          're_route': true,
          'measure': 'km',
          'avatar': 'assets/profile_images/avatar_1.jpg'
        });
      }
      Navigator.pushNamed(context, '/login');
    } catch (e) {
      _showErrorDialog(context, e.toString());
    }
  }

  // Login a user
  Future<void> loginUser({
    required BuildContext context,
    required String email,
    required String password,
  }) async {
    if (email.isEmpty || password.isEmpty) {
      _showErrorDialog(context, "Email and Password are required.");
      return;
    }

    try {
      await _authModel.loginUser(email: email, password: password);

      // Navigate to the home page after successful login
      Navigator.pushReplacementNamed(context, '/navigation');
    } catch (e) {
      _showErrorDialog(context, e.toString());
    }
  }

  Future<void> logout() async {
    await _authModel.logout();
  }

  // Show error dialog
  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Error"),
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
