import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:notification_permissions/notification_permissions.dart';
import 'package:safe_roads/controllers/auth_controller.dart';
import 'package:safe_roads/controllers/profile_controller.dart';
import 'package:safe_roads/models/user_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

class Profile extends StatefulWidget {
  const Profile({super.key});

  @override
  _ProfileState createState() => _ProfileState();
}

class _ProfileState extends State<Profile> with WidgetsBindingObserver {
  final ProfileController _profileController = ProfileController();
  final AuthController _authController = AuthController();

  bool re_route = true;
  bool notifications = true;
  bool tolls = false;
  String measure = "km";

  String username = "Loading...";
  String country = "Loading...";
  int level = 1;
  int distance = 0;
  int targetDistance = 200;
  int totalKm = 0;
  int places = 0;
  String avatar = 'assets/profile_images/avatar_1.jpg';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    fetchUserProfile();
    checkNotificationPermissions();
  }

  // @override
  // void dispose() {
  //   WidgetsBinding.instance.removeObserver(this);
  //   super.dispose();
  // }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Recheck permissions when the app returns to the foreground
      checkNotificationPermissions();
      fetchUserProfile();
      print("entrei no didChangeAppLifecycleState");
    }
  }

  Future<void> fetchUserProfile() async {
    try {
      final userProfile = await _profileController.fetchUserProfile();
      if (mounted) {  // Check if the widget is still in the tree
        setState(() {
          re_route = userProfile['re_route'] as bool;
          username = userProfile['username'] ?? "Unknown";
          country = userProfile['country'] ?? "Unknown";
          tolls = userProfile['tolls'] as bool;
          measure = userProfile['measure'] ?? "km";
          level = userProfile['level'] as int;
          distance = userProfile['distance'] as int;
          targetDistance = userProfile['targetDistance'] as int;
          totalKm = userProfile['totalKm'] as int;
          places = userProfile['places'] as int;
          avatar = userProfile['avatar'] ?? "assets/profile_images/avatar_1.jpg";
        });
      }
    } catch (e) {
      print("Error fetching user profile: $e");
    }
  }

    // Update the preference globally using Provider
  Future<void> updateReRoute(bool newValue) async {
    // Use Provider to update the re_route value
    context.read<UserPreferences>().updateReRoute(newValue);
  }

  Future<void> _showSignOutConfirmation() async {
    final bool? shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Sign Out"),
        content: const Text("Sign out your account?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // Cancel
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true), // Confirm
            child: const Text("Sign Out", style: TextStyle(color: Colors.red),),
          ),
        ],
      ),
    );

    if (shouldSignOut == true) {
      await _authController.logout();
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> _showDeleteAccountDialog() async {
    final TextEditingController passwordController = TextEditingController();

    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Account"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Please enter your password to confirm account deletion."),
            const SizedBox(height: 16.0),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Password",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // Cancel
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true), // Confirm
            child: const Text(
              "Delete",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      final password = passwordController.text;
      if (password.isNotEmpty) {
        await _profileController.deleteUserAccount(context: context, password: password);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Password is required to delete your account.")),
        );
      }
    }
  }

   Future<void> checkNotificationPermissions() async {
    // Check the current notification permission status
    PermissionStatus status = await NotificationPermissions.getNotificationPermissionStatus();

    // Update the switch state based on the permission status
    if (mounted) {  // Check if the widget is still in the tree
      setState(() {
        notifications = (status == PermissionStatus.granted);
        // print("notifications: $notifications");
      });
    }
  }

  Future<void> handleNotificationPermission() async {
    PermissionStatus status = await NotificationPermissions.getNotificationPermissionStatus();

    if (status == PermissionStatus.denied || status == PermissionStatus.unknown) {
      await NotificationPermissions.requestNotificationPermissions();
    } else if (status == PermissionStatus.granted) {
      if (Platform.isAndroid) {
        const AndroidIntent intent = AndroidIntent(
          action: 'android.settings.APP_NOTIFICATION_SETTINGS',
          arguments: <String, dynamic>{
            'android.provider.extra.APP_PACKAGE': 'com.example.safe_roads', 
          },
        );
        await intent.launch();
      } else if (Platform.isIOS) {
        var url = Uri.parse('app-settings:');
        if (await canLaunchUrl(url)) {
          await launchUrl(url);
        } else {
          throw 'Could not launch $url';
        }
      }
    }

    // Check if the widget is mounted before calling setState()
    if (mounted) {
      checkNotificationPermissions();
    }
  }

  Future<void> updatePreference(String key, dynamic value) async {
    try {
      await _profileController.updateUserPreference(context: context, key: key, value: value);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to update preference: $e")),
      );
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
                  CircleAvatar(
                    radius: 60,
                    backgroundImage: AssetImage(avatar),
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
                        country,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24.0),
              buildProgressSection(),
              const SizedBox(height: 24.0),
              buildStatisticsSection(),
              const SizedBox(height: 16.0),
              buildPreferencesSection(),
              const SizedBox(height: 16.0),
              buildSettingsSection(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildProgressSection() {
    return Column(
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
    );
  }

  Widget buildStatisticsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
      ],
    );
  }

  Widget buildPreferencesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Preferences", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18.0)),
        const SizedBox(height: 8.0),
        buildPreferenceSwitches(),
      ],
    );
  }

  Widget buildPreferenceSwitches() {
    return Container(
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
          _buildSwitchTile("Allow re-routing", re_route, (bool newValue) {
            updateReRoute(newValue);
            setState(() {
              re_route = newValue;
            });
            updatePreference("re_route", newValue);
          }),
          const Divider(),
          _buildSwitchTile("Allow notifications", notifications, (bool newValue) async {
            await handleNotificationPermission();
            await checkNotificationPermissions();
            updatePreference("notifications", notifications);
          }),
          const Divider(),
          _buildSwitchTile("Allow tolls", tolls, (bool newValue) {
            setState(() {
              tolls = newValue;
            });
            updatePreference("tolls", newValue);
          }),
          const Divider(),
          buildMeasureDropdown(),
        ],
      ),
    );
  }


  buildMeasureDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: ListTile(
        title: const Text("Unit of measure"),
        trailing: DropdownButton<String>(
          value: measure,
          items: const [
            DropdownMenuItem(value: "km", child: Text("km")),
            DropdownMenuItem(value: "mi", child: Text("mi")),
          ],
          onChanged: (String? newValue) {
            setState(() {
              measure = newValue!;
            });
            updatePreference("measure", measure);
          },
        ),
      ),
    );
  }


  Widget buildSettingsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Settings", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18.0)),
        const SizedBox(height: 8.0),
        buildSettingsOptions(context),
      ],
    );
  }

  Widget buildSettingsOptions(BuildContext context) {
    return Container(
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
          buildSettingsItem("Edit profile", Icons.chevron_right, () async {
            final result = await Navigator.pushNamed(context, '/editProfile');
            if (result == true) {
              fetchUserProfile();
            }
          }),
          const Divider(),
          buildSettingsItem("Sign out", null, _showSignOutConfirmation, color: Colors.red),
          const Divider(),
          buildSettingsItem("Delete account", null, () => _showDeleteAccountDialog(), color: Colors.red,)
        ],
      ),
    );
  }

  Widget buildSettingsItem(String title, IconData? icon, VoidCallback onTap, {Color? color}) {
    return ListTile(
      title: Text(title, style: TextStyle(color: color)),
      trailing: icon != null ? Icon(icon) : null,
      onTap: onTap,
    );
  }

  Widget _buildStatisticCard(String value, String label, IconData icon) {
    return Card(
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
