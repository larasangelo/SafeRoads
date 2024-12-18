import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:notification_permissions/notification_permissions.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';


class Profile extends StatefulWidget {  
  const Profile({Key? key}) : super(key: key);

  @override
  _ProfileState createState() => _ProfileState();
}
class _ProfileState extends State<Profile> with WidgetsBindingObserver{

  bool re_route = true;
  bool notifications = true;
  bool tolls = false;
  String measure = "km";

  String name = "Loading...";
  String username = "Loading...";
  String location = "Loading...";
  int level = 1;
  int distance = 0;
  int targetDistance = 200;
  int totalKm = 0;
  int places = 0;


  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    checkNotificationPermissions();
    fetchUserProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Remove the observer
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Recheck permissions when the app returns to the foreground
      checkNotificationPermissions();
    }
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
            level = data['level'] ?? 1;
            distance = data['distance'] ?? 0;
            targetDistance = data['targetDistance'] ?? 200;
            totalKm = data['totalKm'] ?? 0;
            places = data['places'] ?? 0;
            tolls = data['tolls'] ?? true;
            re_route = data['re_route'] ?? true;
            measure = data['measure'] ?? "km";
          });
        }
      }
    } catch (e) {
      print("Error fetching user profile: $e");
    }
  }

  Future<void> checkNotificationPermissions() async {
    // Check the current notification permission status
    PermissionStatus status =
        await NotificationPermissions.getNotificationPermissionStatus();

    // Update the switch state based on the permission status
    setState(() {
      notifications = (status == PermissionStatus.granted);
    });
  }

  Future<void> handleNotificationPermission() async {
    PermissionStatus status =
        await NotificationPermissions.getNotificationPermissionStatus();

    if (status == PermissionStatus.denied || status == PermissionStatus.unknown) {
      await NotificationPermissions.requestNotificationPermissions();
    } else if (status == PermissionStatus.granted) {
      if (Platform.isAndroid) {
        final AndroidIntent intent = AndroidIntent(
          action: 'android.settings.APP_NOTIFICATION_SETTINGS',
          arguments: <String, dynamic>{
            'android.provider.extra.APP_PACKAGE': 'com.example.safe_roads', 
          },
        );
        await intent.launch();
      } else if (Platform.isIOS) {
        const url = 'app-settings:';
        if (await canLaunch(url)) {
          await launch(url);
        } else {
          throw 'Could not launch $url';
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 60,
                    backgroundImage: AssetImage('assets/avatar_placeholder.png'),
                  ),
                  const SizedBox(width: 16.0),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username,
                        style: const TextStyle(fontSize: 20.0),
                      ),
                      Text(
                        location,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24.0),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Lvl $level"),
                      Text("$distance/$targetDistance km"),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  LinearProgressIndicator(
                    value: distance / targetDistance,
                    backgroundColor: Colors.grey[300],
                    color: Theme.of(context).primaryColor,
                    minHeight: 18.0,
                  ),
                ],
              ),
              const SizedBox(height: 24.0),

              // Statistics
              const Text("Statistics", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18.0)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatisticCard("$totalKm", "Total km", Icons.flash_on),
                  _buildStatisticCard("$places", "Places", Icons.map),
                ],
              ),
              const SizedBox(height: 16.0),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {},
                  child: const Text("View route history >"),
                ),
              ),

              const SizedBox(height: 16.0),

              // Preferences
              const Text("Preferences", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18.0)),
              const SizedBox(height: 8.0),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.0),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.3),
                        blurRadius: 6.0,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10.0),
                        child: _buildSwitchTile(
                          "Allow re-routing",
                          re_route,
                          (bool newValue) {
                            setState(() {
                              re_route = newValue;
                            });
                          },
                        ),
                      ),
                      Divider(),
                      _buildSwitchTile(
                        "Allow notifications",
                        notifications,
                        (bool newValue) async {
                          await handleNotificationPermission();
                          checkNotificationPermissions();
                        },
                      ),
                      Divider(),
                      _buildSwitchTile(
                        "Allow tolls",
                        tolls,
                        (bool newValue) {
                          setState(() {
                            tolls = newValue;
                          });
                        },
                      ),
                      Divider(),
                      
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10.0),
                        child: ListTile(
                          title: Text("Unit of measure"),
                          trailing: DropdownButton<String>(
                            value: measure,
                            items: [
                              DropdownMenuItem(value: "km", child: Text("km")),
                              DropdownMenuItem(value: "mi", child: Text("mi")),
                            ],
                            onChanged: (String? newValue) {
                              setState(() {
                                measure = newValue!;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16.0),

              // Achievements
              // const Text("Achievements", style: TextStyle(fontWeight: FontWeight.bold)),
              // const SizedBox(height: 8.0),
              // ListView(
              //   shrinkWrap: true,
              //   physics: const NeverScrollableScrollPhysics(),
              //   children: const [
              //     ListTile(title: Text("Bla Achievement")),
              //     ListTile(title: Text("Bla Achievement")),
              //     ListTile(title: Text("Bla Achievement")),
              //   ],
              // ),

              // const SizedBox(height: 16.0),

              // Settings
              const Text("Settings", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18.0)),
              const SizedBox(height: 8.0),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.0),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.3),
                        blurRadius: 6.0,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10.0),
                        child: ListTile(
                          title: const Text("Edit profile"),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {},
                        ),
                      ),
                      Divider(),
                
                      ListTile(
                        title: const Text("Sign out", style: TextStyle(color: Colors.red)),
                        // trailing: const Icon(Icons.chevron_right),
                        onTap: () {},
                      ),
                      Divider(),
                
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10.0),
                        child: ListTile(
                          title: const Text("Delete account", style: TextStyle(color: Colors.red)),
                          // trailing: const Icon(Icons.chevron_right),
                          onTap: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatisticCard(String value, String label, IconData icon) {
    return Column(
      children: [
        Card(
          elevation: 2.0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(icon, color: Colors.orange, size: 45.0),
                const SizedBox(width: 8.0),
                Column(
                  children: [
                    Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18.0)),
                    const SizedBox(height: 4.0),
                    Text(label, style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchTile(String title, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }

}
