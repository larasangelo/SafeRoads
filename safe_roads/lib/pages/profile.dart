import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    checkNotificationPermissions();
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
              // Profile Header
              Row(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundImage: AssetImage('assets/avatar_placeholder.png'), // Placeholder image
                  ),
                  const SizedBox(width: 16.0),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "O Seu Nome",
                        style: TextStyle(fontSize: 20.0),
                      ),
                      const Text(
                        "@o_seu_nome",
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 8.0),
                      Row(
                        children: const [
                          Icon(Icons.location_on, size: 16.0, color: Colors.grey),
                          SizedBox(width: 4.0),
                          Text("Portugal", style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24.0),

              // Level Bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Lvl 1"),
                      const Text("110/200 km"),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  LinearProgressIndicator(
                    value: 110 / 200,
                    backgroundColor: Colors.grey[300],
                    color: Theme.of(context).primaryColor,
                    minHeight: 18.0,
                    borderRadius: BorderRadius.all(
                      Radius.circular(10),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24.0),

              // Statistics
              const Text("Statistics", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18.0)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatisticCard("110", "Total km", Icons.flash_on),
                  _buildStatisticCard("3", "Places", Icons.map),
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
              _buildSwitchTile(
                "Allow re-routing",
                re_route,
                (bool newValue) {
                  setState(() {
                    re_route = newValue;
                  });
                },
              ),
              _buildSwitchTile(
                "Allow notifications",
                notifications,
                (bool newValue) async {
                  await handleNotificationPermission();
                  checkNotificationPermissions();
                },
              ),
              _buildSwitchTile(
                "Allow tolls",
                tolls,
                (bool newValue) {
                  setState(() {
                    tolls = newValue;
                  });
                },
              ),

              ListTile(
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
              ListTile(
                title: const Text("Edit profile"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              ),
              ListTile(
                title: const Text("Sign out"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              ),
              ListTile(
                title: const Text("Delete account"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
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
