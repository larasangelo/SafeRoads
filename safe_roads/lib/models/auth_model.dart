import 'package:firebase_auth/firebase_auth.dart';

class AuthModel {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Comunication with Firebase for Register
  Future<User?> registerUser({
    required String email,
    required String password,
    required String username,
  }) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update user's display name
      await userCredential.user?.updateDisplayName(username);

      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? "An unknown error occurred.");
    }
  }

  // Comunication with Firebase for Login
  Future<User?> loginUser({required String email, required String password}) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? "An unknown error occurred.");
    }
  }

  Future<void> updateUser({
    required String email,
    // required String password,
    required String username,
  }) async {
    print("auth_model: $username, $email");

    final User? user = _auth.currentUser;

    if (user == null) {
      throw Exception("No user is currently signed in.");
    }

    try {
      // Update the password if provided
      // if (password.isNotEmpty) {
      //   await user.updatePassword(password);
      // }

      // Update display name
      if (username.isNotEmpty) {
        await user.updateDisplayName(username);
      }

      // Reload the user to apply changes
      await user.reload();
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? "Failed to update user.");
    }
  }


  // Logout
  Future<void> logout() async {
    await _auth.signOut();
  }
}
