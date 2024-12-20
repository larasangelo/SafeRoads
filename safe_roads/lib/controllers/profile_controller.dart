import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class ProfileController {
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Fetch user profile
  Future<Map<String, String>> fetchUserProfile() async {
    final User? user = _auth.currentUser;

    if (user == null) {
      throw Exception("No user is currently signed in.");
    }

    final DataSnapshot snapshot = await _databaseRef.child('users/${user.uid}/profile').get();
    if (snapshot.exists) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      return {
        'username': data['username'] ?? "Unknown",
        'country': data['location'] ?? "Unknown",
        'email': data['email'] ?? "Unknown",
      };
    } else {
      throw Exception("User profile not found.");
    }
  }

  // Update user profile
  Future<void> updateUser({
    required String username,
    required String email,
    required String country,
  }) async {
    final User? user = _auth.currentUser;

    if (user == null) {
      throw Exception("No user is currently signed in.");
    }

    await _databaseRef.child('users/${user.uid}/profile').update({
      'username': username,
      'email': email,
      'location': country,
    });
  }
}
