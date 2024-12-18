import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safe_roads/controllers/auth_controller.dart';


class EditProfile extends StatefulWidget {  
  const EditProfile({Key? key}) : super(key: key);

  @override
  _EditProfileState createState() => _EditProfileState();
}
class _EditProfileState extends State<EditProfile> with WidgetsBindingObserver{

  String name = "Loading...";
  String username = "Loading...";
  String location = "Loading...";
  String email = "Loading...";

  final AuthController _authController = AuthController();

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _countryController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final _formKey = GlobalKey<FormState>();


  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    fetchUserProfile();
  }

  Future<void> fetchUserProfile() async {
    try {
      final User? user = _auth.currentUser;

      if (user != null) {
        final DataSnapshot snapshot = await _databaseRef.child('users/${user.uid}/profile').get();
        if (snapshot.exists) {
          final data = Map<String, dynamic>.from(snapshot.value as Map);
          setState(() {
            username = data['username'] ?? "Unknown";
            location = data['location'] ?? "Unknown";
            email = data['email'] ?? "Unknown";
          });
        }
      }
    } catch (e) {
      print("Error fetching user profile: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Edit Profile"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: const CircleAvatar(
                    radius: 60,
                    backgroundImage: AssetImage('assets/avatar_placeholder.png'),
                  ),
                ),
                const SizedBox(height: 40.0),
                Text("Username"),
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: "$username",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    filled: true,
                    fillColor: Colors.grey[200],
                  ),
                ),
                const SizedBox(height: 20.0),
                Text("Email"),
                TextFormField(
                  decoration: InputDecoration(
                    labelText: "$email",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    filled: true,
                    fillColor: Colors.grey[200],
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 20.0),
                Text("Country"),
                TextFormField(
                  controller: _countryController,
                  decoration: InputDecoration(
                    labelText: "$location",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    filled: true,
                    fillColor: Colors.grey[200],
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 20.0),
                Text("Password"),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: "Confirm password",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    filled: true,
                    fillColor: Colors.grey[200],
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 30.0),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      _authController.updateUser(
                        context: context,
                        username: _usernameController.text.trim(),
                        email: email,
                        country: _countryController.text.trim(),
                        password: _passwordController.text.trim(),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                    ),
                    child: const Text(
                      "Update",
                      style: TextStyle(fontSize: 18, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

    );
  }

}
