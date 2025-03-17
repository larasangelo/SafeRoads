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

  bool lowRisk = true;
  bool changeRoute = true;
  bool notifications = true;
  bool tolls = false;
  String measure = "km";
  String riskAlertDistance = "100 m";
  String rerouteAlertDistance = "250 m";

  String username = "Loading...";
  String country = "Loading...";
  int level = 1;
  int distance = 0;
  int targetDistance = 200;
  int totalKm = 0;
  int places = 0;
  String avatar = 'assets/profile_images/avatar_1.jpg';

  List<Map<String, dynamic>> speciesOptions = [
    {"name": "Amphibians", "icon": Icons.water},
    {"name": "Reptiles", "icon": Icons.grass},
    {"name": "Hedgehogs", "icon": Icons.pets},
  ];
  List<String> selectedSpecies = ["Amphibians"];

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
          lowRisk = userProfile['lowRisk'] as bool;
          changeRoute = userProfile['changeRoute'] as bool;
          username = userProfile['username'] ?? "Unknown";
          country = userProfile['country'] ?? "Unknown";
          tolls = userProfile['tolls'] as bool;
          measure = userProfile['measure'] ?? "km";
          riskAlertDistance = userProfile['riskAlertDistance'] ?? "100 m";
          rerouteAlertDistance = userProfile['rerouteAlertDistance'] ?? "250 m";
          level = userProfile['level'] as int;
          distance = userProfile['distance'] as int;
          targetDistance = userProfile['targetDistance'] as int;
          totalKm = userProfile['totalKm'] as int;
          places = userProfile['places'] as int;
          avatar = userProfile['avatar'] ?? "assets/profile_images/avatar_1.jpg";
          selectedSpecies = userProfile['selectedSpecies'] ?? ["Amphibians"];
        });
      }
    } catch (e) {
      print("Error fetching user profile: $e");
    }
  }

  // Update the preference globally using Provider
  Future<void> updateLowRisk(bool newValue) async {
    // Use Provider to update the lowRisk value
    context.read<UserPreferences>().updateLowRisk(newValue);
  }

  Future<void> updateRiskAlertDistance(String newValue) async {
    // Use Provider to update the riskAlertDistance value
    context.read<UserPreferences>().updateRiskAlertDistance(newValue);
  }

  Future<void> updateRerouteAlertDistance(String newValue) async {
    // Use Provider to update the rerouteAlertDistance value
    context.read<UserPreferences>().updateRerouteAlertDistance(newValue);
  }

  Future<void> updateChangeRoute(bool newValue) async {
    // Use Provider to update the changeRoute value
    context.read<UserPreferences>().updateChangeRoute(newValue);
  }

  Future<void> updateSelectedSpecies(List<String> newSelectedSpecies) async {
    // Use Provider to update the selectedSpecies value
    context.read<UserPreferences>().updateSelectedSpecies(newSelectedSpecies);
    print("Entra no updateSelectedSpecies");
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
              buildSpeciesGrid(),
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
          _buildSwitchTile("Allow notifications", notifications, (bool newValue) async {
            await handleNotificationPermission();
            await checkNotificationPermissions();
            updatePreference("notifications", notifications);
          }),
          const Divider(),
          _buildSwitchTile("Only low risk route", lowRisk, (bool newValue) {
            updateLowRisk(newValue);
            setState(() {
              lowRisk = newValue;
            });
            updatePreference("lowRisk", newValue);
          }),
          const Divider(),
          _buildSwitchTile("Change route automatically", changeRoute, (bool newValue) {
            updateChangeRoute(newValue);
            setState(() {
              changeRoute = newValue;
            });
            updatePreference("changeRoute", newValue);
          }),
          const Divider(),
          buildRiskNotificationDropdown(),
          const Divider(),
          buildRerouteNotificationDropdown(),
          // const Divider(),
          // _buildSwitchTile("Allow tolls", tolls, (bool newValue) {
          //   setState(() {
          //     tolls = newValue;
          //   });
          //   updatePreference("tolls", newValue);
          // }),
          // const Divider(),
          // buildMeasureDropdown(),
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

  buildRiskNotificationDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: ListTile(
        title: Row(
          children: [
            const Text("Risk alert distance"),
            const SizedBox(width: 5), // Small spacing between text and icon
            IconButton(
              icon: const Icon(Icons.info_outline, color: Colors.grey),
              tooltip: "What is this?",
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Text("Risk Alert Distance Info"),
                      content: const Text(
                        "This setting determines the distance at which you will receive a notification "
                        "about upcoming risk zones. Choose a smaller distance for precise alerts or "
                        "a larger distance for early warnings.",
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text("OK"),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
        trailing: DropdownButton<String>(
          value: riskAlertDistance,
          items: const [
            DropdownMenuItem(value: "100 m", child: Text("100 m")),
            DropdownMenuItem(value: "500 m", child: Text("500 m")),
            DropdownMenuItem(value: "1 km", child: Text("1 km")),
          ],
          onChanged: (String? newValue) {
            setState(() {
              riskAlertDistance = newValue!;
            });
            updateRiskAlertDistance(newValue!);
            updatePreference("riskAlertDistance", riskAlertDistance);
          },
        ),
      ),
    );
  }

  buildRerouteNotificationDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: ListTile(
        title: Row(
          children: [
            const Text("Re-route alert distance"),
            const SizedBox(width: 5), // Small spacing between text and icon
            IconButton(
              icon: const Icon(Icons.info_outline, color: Colors.grey),
              tooltip: "What is this?",
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Text("Re-route Alert Distance Info"),
                      content: const Text(
                        "This setting determines the distance at which you will receive a notification "
                        "about upcoming Re-route opportunities. Choose a smaller distance for precise alerts or "
                        "a larger distance for early warnings.",
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text("OK"),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
        trailing: DropdownButton<String>(
          value: rerouteAlertDistance,
          items: const [
            DropdownMenuItem(value: "250 m", child: Text("250 m")),
            DropdownMenuItem(value: "500 m", child: Text("500 m")),
            DropdownMenuItem(value: "1 km", child: Text("1 km")),
          ],
          onChanged: (String? newValue) {
            setState(() {
              rerouteAlertDistance = newValue!;
            });
            updateRerouteAlertDistance(newValue!);
            updatePreference("rerouteAlertDistance", rerouteAlertDistance);
          },
        ),
      ),
    );
  }

  Widget buildSpeciesGrid() {
    final selectedSpecies = context.watch<UserPreferences>().selectedSpecies; // Watch provider state

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Select Species for Alerts",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18.0),
        ),
        Wrap(
          spacing: 8.0,
          children: speciesOptions.map((species) {
            bool isSelected = selectedSpecies.contains(species["name"]);
            return ChoiceChip(
              label: Text(species["name"]),
              avatar: Icon(
                species["icon"],
                color: isSelected ? Colors.white : Colors.black,
              ),
              selected: isSelected,
              onSelected: (selected) async {
                List<String> updatedSelection = List.from(selectedSpecies);
                if (selected) {
                  updatedSelection.add(species["name"]);
                } else {
                  updatedSelection.remove(species["name"]);
                }

                updatePreference("selectedSpecies", updatedSelection);
                await updateSelectedSpecies(updatedSelection); // Updates provider
              },
            );
          }).toList(),
        ),
      ],
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
