import 'package:firebase_database/firebase_database.dart';

class UserProfileRepository {
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref();

  Future<Map<String, dynamic>> fetchUserProfile(String uid) async {
    try {
      final snapshot = await _databaseRef.child('users/$uid/profile').get();
      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      } else {
        throw Exception("User profile not found.");
      }
    } catch (e) {
      throw Exception("Failed to fetch user profile: $e");
    }
  }

  Future<void> updateUserProfile(String uid, Map<String, dynamic> profileData) async {
    try {
      await _databaseRef.child('users/$uid/profile').update(profileData);
    } catch (e) {
      throw Exception("Failed to update user profile: $e");
    }
  }
}
