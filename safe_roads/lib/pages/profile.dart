import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:safe_roads/configuration/language_config.dart';
import 'package:safe_roads/controllers/auth_controller.dart';
import 'package:safe_roads/controllers/profile_controller.dart';
import 'package:safe_roads/models/user_preferences.dart';
import 'package:safe_roads/pages/alert_distance.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:safe_roads/configuration/profile_config.dart';


class Profile extends StatefulWidget {
  const Profile({super.key});

  @override
  State<Profile> createState() => _ProfileState();
}

class _ProfileState extends State<Profile> with WidgetsBindingObserver, AutomaticKeepAliveClientMixin{
  final ProfileController _profileController = ProfileController();
  final AuthController _authController = AuthController();

  bool lowRisk = ProfileConfig.defaultLowRisk;
  bool changeRoute = ProfileConfig.defaultChangeRoute;
  bool notifications = ProfileConfig.defaultNotifications;
  bool tolls = ProfileConfig.defaultTolls;
  String measure = ProfileConfig.defaultMeasure;
  String riskAlertDistance = ProfileConfig.defaultRiskAlertDistance;
  String rerouteAlertDistance = ProfileConfig.defaultRerouteAlertDistance;

  String username = ProfileConfig.defaultUsername;
  String country = ProfileConfig.defaultCountry;
  int level = ProfileConfig.defaultLevel;
  int distance = ProfileConfig.defaultDistance;
  int targetDistance = ProfileConfig.defaultTargetDistance;
  int totalKm = ProfileConfig.defaultTotalKm;
  int places = ProfileConfig.defaultPlaces;
  String avatar = ProfileConfig.defaultAvatar;

  List<Map<String, dynamic>> speciesOptions = ProfileConfig.speciesOptions;
  List<Object?> selectedSpecies = ProfileConfig.defaultSelectedSpecies;
  String selectedLanguage = ProfileConfig.defaultLanguage;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    fetchUserProfile();
    checkNotificationPermissions();
  }

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
          username = userProfile['username'] ?? ProfileConfig.defaultUsername;
          country = userProfile['country'] ?? ProfileConfig.defaultCountry;
          tolls = userProfile['tolls'] as bool;
          measure = userProfile['measure'] ?? ProfileConfig.defaultMeasure;
          riskAlertDistance = userProfile['riskAlertDistance'] ?? ProfileConfig.defaultRiskAlertDistance;
          rerouteAlertDistance = userProfile['rerouteAlertDistance'] ?? ProfileConfig.defaultRerouteAlertDistance;
          level = userProfile['level'] as int;
          distance = userProfile['distance'] as int;
          targetDistance = userProfile['targetDistance'] as int;
          totalKm = userProfile['totalKm'] as int;
          places = userProfile['places'] as int;
          avatar = userProfile['avatar'] ?? ProfileConfig.defaultAvatar;
          selectedSpecies = userProfile['selectedSpecies'] ?? ProfileConfig.defaultSelectedSpecies;
          selectedLanguage = userProfile['selectedLanguage'] ?? ProfileConfig.defaultLanguage;
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

  Future<void> updateSelectedSpecies(List<Object?> newSelectedSpecies) async {
    // Use Provider to update the selectedSpecies value
    context.read<UserPreferences>().updateSelectedSpecies(newSelectedSpecies);
  }

  Future<void> updateLanguage(String newValue) async {
    // Use Provider to update the rerouteAlertDistance value
    context.read<UserPreferences>().updateLanguage(newValue);
  }


  Future<void> _showSignOutConfirmation() async {
    final bool? shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(LanguageConfig.getLocalizedString(selectedLanguage, 'signOut')),
        content: Text(LanguageConfig.getLocalizedString(selectedLanguage, 'signOutConfirmation')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // Cancel
            child: Text(LanguageConfig.getLocalizedString(selectedLanguage, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true), // Confirm
            child: Text(LanguageConfig.getLocalizedString(selectedLanguage, 'signOut'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldSignOut == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', false);
      await _authController.logout(); // Assuming _authController handles Firebase logout or similar

      // Stop the background service explicitly on logout
      final service = FlutterBackgroundService();
      if (await service.isRunning()) {
        service.invoke("stopService"); // Send a message to the background isolate to stop itself
        print("Sent stop command to background service explicitly on user logout.");
      }

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> _showDeleteAccountDialog() async {
    final TextEditingController passwordController = TextEditingController();

    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(LanguageConfig.getLocalizedString(selectedLanguage, 'deleteAccount')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(LanguageConfig.getLocalizedString(selectedLanguage, 'enterPassword')),
            const SizedBox(height: 16.0),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: LanguageConfig.getLocalizedString(selectedLanguage, 'password'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // Cancel
            child: Text(LanguageConfig.getLocalizedString(selectedLanguage, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true), // Confirm
            child: Text(
              LanguageConfig.getLocalizedString(selectedLanguage, 'delete'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      final password = passwordController.text;
      if (password.isNotEmpty) {
        if (!mounted) return;
        await _profileController.deleteUserAccount(context: context, password: password);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageConfig.getLocalizedString(selectedLanguage, 'passwordRequired'))),
        );
      }
    }
  }

  Future<void> handleNotificationPermission() async {
    PermissionStatus status = await Permission.notification.status;

    if (status.isDenied || status.isRestricted || status.isPermanentlyDenied) {
      await Permission.notification.request();
    }

    if (Platform.isAndroid) {
      try {
        final intent = AndroidIntent(
          action: 'android.settings.APP_NOTIFICATION_SETTINGS',
          arguments: <String, dynamic>{
            'android.provider.extra.APP_PACKAGE': 'com.example.safe_roads', 
          },
        );
        await intent.launch();
      } catch (e) {
        print("Error launching Android notification settings: $e");
      }
    } else if (Platform.isIOS) {
      final url = Uri.parse('app-settings:');
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        print('Could not launch iOS settings');
      }
    }
  }

  Future<void> checkNotificationPermissions() async {
    await Future.delayed(const Duration(milliseconds: 500)); // Small delay to prevent race conditions

    PermissionStatus status = await Permission.notification.status;

    if (mounted) {
      setState(() {
        notifications = (status == PermissionStatus.granted);
      });
    }
  }

  Future<void> updatePreference(String key, dynamic value) async {
    try {
      await _profileController.updateUserPreference(context: context, key: key, value: value);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${LanguageConfig.getLocalizedString(selectedLanguage, 'updateFailed')}: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Get screen size to adjust layout
    double screenHeight = MediaQuery.of(context).size.height;
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(screenWidth * 0.05), 
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: screenWidth * 0.15,
                    backgroundImage: AssetImage(avatar),
                  ),
                  SizedBox(width: screenWidth * 0.04),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username,
                          style: TextStyle(fontSize: screenWidth * 0.05),
                        ),
                        Text(
                          country,
                          style: TextStyle(color: Colors.grey, fontSize: screenWidth * 0.04),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit, size: screenWidth * 0.06),
                    onPressed: () async {
                      final result = await Navigator.pushNamed(context, '/editProfile');
                      if (result == true) {
                        fetchUserProfile();
                      }
                    },
                    tooltip: LanguageConfig.getLocalizedString(selectedLanguage, 'editProfile'),
                  ),
                ],
              ),
              SizedBox(height: screenHeight * 0.03), 
              // buildProgressSection(),
              // const SizedBox(height: 24.0),
              // buildStatisticsSection(),
              // const SizedBox(height: 16.0),
              buildPreferencesSection(),
              SizedBox(height: screenHeight * 0.02), 
              // buildSpeciesGrid(),
              // SizedBox(height: screenHeight * 0.02), 
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
            Text(
              "Lvl $level",
              style: TextStyle(fontSize: MediaQuery.of(context).size.width * 0.04), 
            ),
            Text(
              "$distance/$targetDistance km",
              style: TextStyle(fontSize: MediaQuery.of(context).size.width * 0.04), 
            ),
          ],
        ),
        SizedBox(height: MediaQuery.of(context).size.height * 0.02), 
        LinearProgressIndicator(
          value: distance / targetDistance,
          // backgroundColor: Colors.grey[300],
          // color: Theme.of(context).primaryColor,
          minHeight: 18.0,
        ),
      ],
    );
  }

  Widget buildStatisticsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LanguageConfig.getLocalizedString(selectedLanguage, 'statistics'),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: MediaQuery.of(context).size.width * 0.05, 
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildStatisticCard(
              "$totalKm",
              LanguageConfig.getLocalizedString(selectedLanguage, 'totalKm'),
              Icons.flash_on,
            ),
            _buildStatisticCard(
              "$places",
              LanguageConfig.getLocalizedString(selectedLanguage, 'places'),
              Icons.map,
            ),
          ],
        ),
        SizedBox(height: MediaQuery.of(context).size.height * 0.02),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {},
            child: Text(
              LanguageConfig.getLocalizedString(selectedLanguage, 'viewRouteHistory'),
              style: TextStyle(fontSize: MediaQuery.of(context).size.width * 0.04), 
            ),
          ),
        ),
      ],
    );
  }

  Widget buildPreferencesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LanguageConfig.getLocalizedString(selectedLanguage, 'preferences'),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: MediaQuery.of(context).size.width * 0.05, 
          ),
        ),
        SizedBox(height: MediaQuery.of(context).size.height * 0.02), 
        buildPreferenceSwitches(),
      ],
    );
  }

  Widget buildPreferenceSwitches() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.0),
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            // color: Colors.grey.withValues(alpha: 0.3),
            blurRadius: 6.0,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildSwitchTile(
            LanguageConfig.getLocalizedString(selectedLanguage, 'allowNotifications'),
            notifications,
            (bool newValue) async {
              await handleNotificationPermission();
              await checkNotificationPermissions();
              updatePreference("notifications", notifications);
            },
          ),
          const Divider(),
          _buildSwitchTile(
            LanguageConfig.getLocalizedString(selectedLanguage, 'onlyLowRisk'),
            lowRisk,
            (bool newValue) {
              updateLowRisk(newValue);
              setState(() {
                lowRisk = newValue;
              });
              updatePreference("lowRisk", newValue);
            },
          ),
          const Divider(),
          _buildSwitchTile(
            LanguageConfig.getLocalizedString(selectedLanguage, 'changeRoute'),
            changeRoute,
            (bool newValue) {
              updateChangeRoute(newValue);
              setState(() {
                changeRoute = newValue;
              });
              updatePreference("changeRoute", newValue);
            },
          ),
          const Divider(),
          buildRiskNotificationDropdown(),
          const Divider(),
          buildRerouteNotificationDropdown(),
          const Divider(),
          buildLanguageDropdown(),
        ],
      ),
    );
  }

  Widget buildMeasureDropdown() {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).size.height * 0.02), 
      child: ListTile(
        title: Text(
          LanguageConfig.getLocalizedString(selectedLanguage, 'unitMeasure'),
          style: TextStyle(fontSize: MediaQuery.of(context).size.width * 0.04), 
        ),
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
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;

    return Padding(
      padding: EdgeInsets.only(bottom: screenHeight * 0.02), 
      child: ListTile(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AlertDistancePage(
                title: LanguageConfig.getLocalizedString(selectedLanguage, 'info'),
                chosen: LanguageConfig.getLocalizedString(selectedLanguage, 'riskAlertDistance'),
                info: LanguageConfig.getLocalizedString(selectedLanguage, 'riskAlertDistanceInfo'),
                selectedValue: riskAlertDistance,
                onValueChanged: (newValue) {
                  setState(() {
                    riskAlertDistance = newValue;
                  });
                  updateRiskAlertDistance(newValue);
                  updatePreference("riskAlertDistance", riskAlertDistance);
                },
              ),
            ),
          );
        },
        title: Text(
          LanguageConfig.getLocalizedString(selectedLanguage, 'riskAlertDistance'),
          style: TextStyle(fontSize: screenWidth * 0.04), 
        ),
        trailing: DropdownButton<String>(
          value: riskAlertDistance,
          items: const [
            DropdownMenuItem(value: "250 m", child: Text("250 m")),
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
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;

    return Padding(
      padding: EdgeInsets.only(bottom: screenHeight * 0.02), 
      child: ListTile(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AlertDistancePage(
                title: LanguageConfig.getLocalizedString(selectedLanguage, 'info'),
                chosen: LanguageConfig.getLocalizedString(selectedLanguage, 'reRouteAlertDistance'),
                info: LanguageConfig.getLocalizedString(selectedLanguage, 'reRouteAlertDistanceInfo'),
                selectedValue: rerouteAlertDistance,
                onValueChanged: (newValue) {
                  setState(() {
                    rerouteAlertDistance = newValue;
                  });
                  updateRerouteAlertDistance(newValue);
                  updatePreference("rerouteAlertDistance", rerouteAlertDistance);
                },
              ),
            ),
          );
        },
        title: Text(
          LanguageConfig.getLocalizedString(selectedLanguage, 'reRouteAlertDistance'),
          style: TextStyle(fontSize: screenWidth * 0.04), 
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

  Widget buildLanguageDropdown() {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;

    return Padding(
      padding: EdgeInsets.only(bottom: screenHeight * 0.02), 
      child: ListTile(
        title: Row(
          children: [
            Text(
              LanguageConfig.getLocalizedString(selectedLanguage, 'language'),
              style: TextStyle(fontSize: screenWidth * 0.04), 
            ),
          ],
        ),
        trailing: DropdownButton<String>(
          value: selectedLanguage,
          items: const [
            DropdownMenuItem(value: "en", child: Text("English")),
            DropdownMenuItem(value: "pt", child: Text("Português")),
            DropdownMenuItem(value: "es", child: Text("Español")),
          ],
          onChanged: (String? newValue) {
            setState(() {
              selectedLanguage = newValue!;
            });
            updateLanguage(newValue!);
            updatePreference("selectedLanguage", selectedLanguage);
          },
        ),
      ),
    );
  }

  Widget buildSpeciesGrid() {
    final selectedSpecies = context.watch<UserPreferences>().selectedSpecies; // Watch provider state
    double screenWidth = MediaQuery.of(context).size.width;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LanguageConfig.getLocalizedString(selectedLanguage, 'speciesForAlerts'),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: screenWidth * 0.05, 
          ),
        ),
        Wrap(
          spacing: screenWidth * 0.02, 
          children: speciesOptions.map((species) {
            bool isSelected = selectedSpecies.contains(species["key"]);
            return ChoiceChip(
              label: Text(
                LanguageConfig.getLocalizedString(selectedLanguage, species['key']),
                style: TextStyle(fontSize: screenWidth * 0.035), 
              ),
              avatar: ImageIcon(
                (species["icon"] as ImageIcon).image,
                // color: isSelected ? Colors.white : Colors.black,
              ),
              selected: isSelected,
              onSelected: (selected) async {
                List<Object?> updatedSelection = List.from(selectedSpecies);
                if (selected) {
                  updatedSelection.add(species["key"]);
                } else {
                  if (updatedSelection.length <= 1) return;
                  updatedSelection.remove(species["key"]);
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
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LanguageConfig.getLocalizedString(selectedLanguage, 'settings'),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: screenWidth * 0.05, 
          ),
        ),
        SizedBox(height: screenHeight * 0.01), 
        buildSettingsOptions(context),
      ],
    );
  }

  Widget buildSettingsOptions(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.0),
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            // color: Colors.grey.withValues(alpha: 0.3),
            blurRadius: 6.0,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          buildSettingsItem(
            LanguageConfig.getLocalizedString(selectedLanguage, 'editProfile'),
            Icons.chevron_right,
            () async {
              final result = await Navigator.pushNamed(context, '/editProfile');
              if (result == true) {
                fetchUserProfile();
              }
            },
          ),
          Divider(),
          buildSettingsItem(
            LanguageConfig.getLocalizedString(selectedLanguage, 'signOut'),
            null,
            _showSignOutConfirmation,
            color: Colors.red,
          ),
          Divider(),
          buildSettingsItem(
            LanguageConfig.getLocalizedString(selectedLanguage, 'deleteAccount'),
            null,
            () => _showDeleteAccountDialog(),
            color: Colors.red,
          ),
        ],
      ),
    );
  }

  Widget buildSettingsItem(String title, IconData? icon, VoidCallback onTap, {Color? color}) {
    double screenWidth = MediaQuery.of(context).size.width;

    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: screenWidth * 0.04,  
        ),
      ),
      trailing: icon != null ? Icon(icon) : null,
      onTap: onTap,
    );
  }

  Widget _buildStatisticCard(String value, String label, IconData icon) {
    double screenWidth = MediaQuery.of(context).size.width;

    return Card(
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      child: Padding(
        padding: EdgeInsets.all(screenWidth * 0.04), 
        child: Row(
          children: [
            Icon(icon, color: Colors.orange, size: screenWidth * 0.1),
            SizedBox(width: screenWidth * 0.02), 
            Column(
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: screenWidth * 0.045, 
                  ),
                ),
                SizedBox(height: screenWidth * 0.01), 
                Text(
                  label,
                  style: TextStyle(color: Colors.grey, fontSize: screenWidth * 0.035), 
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile(String title, bool value, ValueChanged<bool> onChanged) {
    double screenWidth = MediaQuery.of(context).size.width;

    return SwitchListTile(
      title: Text(
        title,
        style: TextStyle(
          fontSize: screenWidth * 0.04,  
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}