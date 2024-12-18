import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '../models/auth_model.dart';

class AuthController {
  final AuthModel _authModel = AuthModel();
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref();

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
    // It also gets an error if the password is less than 6 chars
    try {
      final user = await _authModel.registerUser(email: email, password: password, username: username);
      if (user != null) {
        await _databaseRef.child('users/${user.uid}/profile').set({
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

  Future<void> updateUser({
    required BuildContext context,
    required String username,
    required String email,
    required String country,
    // required String password,
  }) async {
    print("auth_controller: $username, $email, $country");
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showErrorDialog(context, "No user is currently signed in.");
      return;
    }

    if (username.isEmpty || email.isEmpty || country.isEmpty) {
      _showErrorDialog(context, "All fields are required.");
      return;
    }

    try {
      // Update the user's authentication details
      // await _authModel.updateUser(email: email, password: password, username: username);
      await _authModel.updateUser(email: email, username: username);


      // Update the user's profile in the database
      await _databaseRef.child('users/${user.uid}/profile').update({
        'username': username,
        'email': email,
        'location': country,
      });

      // Show success feedback
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile updated successfully!")),
      );
    } catch (e) {
      _showErrorDialog(context, e.toString());
    }
  }

}
