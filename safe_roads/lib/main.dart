import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:safe_roads/configuration/language_config.dart';
import 'package:safe_roads/firebase_options.dart';
import 'package:safe_roads/models/navigation_bar_visibility.dart';
import 'package:safe_roads/models/notification_preferences.dart';
import 'package:safe_roads/models/user_preferences.dart';
import 'package:safe_roads/monochrome_theme.dart';
import 'package:safe_roads/notifications.dart';
import 'package:safe_roads/pages/edit_profile.dart';
import 'package:safe_roads/pages/home.dart';
import 'package:safe_roads/pages/loading.dart';
import 'package:safe_roads/pages/login.dart';
import 'package:safe_roads/pages/navigation_bar.dart';
import 'package:safe_roads/pages/register.dart';
import 'package:safe_roads/pages/welcome.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

StreamSubscription<RemoteMessage>? foregroundSubscription;

// For Background Messaging
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'channel_id_1',
    'Default Notifications',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    icon: '@mipmap/ic_launcher',
  );

  const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.show(
    0,
    message.data['title'] ?? 'SafeRoads',
    message.data['body'] ?? 'You have a new notification',
    platformDetails,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  final Notifications notifications = Notifications();
  await notifications.setupNotificationChannels();

  await requestLocationPermissions();
  await initializeService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserPreferences()),
        ChangeNotifierProvider(create: (_) => NotificationPreferences()),
        ChangeNotifierProvider(create: (_) => NavigationBarVisibility()), 
      ],
      child: MyApp(),
    ),
  );
}

// Function to initialize background service
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  final isRunning = await service.isRunning();
  if (isRunning) {
    print("Service already running. Skipping start.");
    return;
  }

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'my_foreground', // id
    'SafeRoads Foreground Service', // title
    description: 'This channel is used for important notifications.', // description
    importance: Importance.low, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin(); // Corrected type here

  if (Platform.isIOS || Platform.isAndroid) {
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        iOS: DarwinInitializationSettings(),
        android: AndroidInitializationSettings('ic_bg_service_small'),
      ),
    );
  }

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'my_foreground',
      initialNotificationTitle: 'SafeRoads Service',
      initialNotificationContent: 'Initializing',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
  await service.startService();
  print("Passo pelo initializeService");
}

Future<void> requestLocationPermissions() async {
  print("Entro no requestLocationPermissions");
  final status1 = await Permission.locationWhenInUse.request();
  final status2 = await Permission.location.request();
  // final status3 = await Permission.locationAlways.request();

  // if (status1.isGranted && status2.isGranted && status3.isGranted) {
  if (status1.isGranted && status2.isGranted) {
    print("All location permissions granted");
  } else {
    print("Some permissions denied");
    print("WhenInUse: ${status1.isGranted}");
    print("Location: ${status2.isGranted}");
    // print("Always: ${status3.isGranted}");

    // if (status3.isPermanentlyDenied) {
    //   // Send user to app settings
    //   print("LocationAlways is permanently denied. Open settings.");
    //   await openAppSettings();
    // }
  }
}

const double mediumRiskThreshold = 0.3;
const double highRiskThreshold = 0.5;
DateTime lastNotificationTime = DateTime.now().subtract(Duration(seconds: 30));

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final plugin = FlutterLocalNotificationsPlugin();
  final prefs = await SharedPreferences.getInstance();

  // This listener will allow the main isolate to send commands (like stop)
  service.on('stopService').listen((event) {
    service.stopSelf();
    print("Background service received stop command and stopped.");
  });

  // Listen for the main app's disconnection.
  service.on('onDisconnect').listen((event) async {
    print("Background service: onDisconnect event received.");
    await prefs.reload();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    if (!isLoggedIn) {
      print("Background service: Main app disconnected and isLoggedIn is FALSE. Stopping service.");
      service.stopSelf();
    } else {
      print("Background service: Main app disconnected, but user is still logged in (isLoggedIn=true). Service will continue background checks.");
    }
  });

  Timer? notificationTimer;
  DateTime localLastNotificationTime = DateTime.now().subtract(const Duration(seconds: 30));

  Timer.periodic(const Duration(seconds: 20), (monitorTimer) async {
    await prefs.reload(); // Always reload to get the latest SharedPreferences state
    print("=== Background Check (onStart) ===");

    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final isAppInForeground = prefs.getBool('isAppInForeground') ?? true; // Default to true if not set

    // New Condition: Only proceed if logged in AND app is NOT in foreground
    if (!isLoggedIn) {
      print("User is not logged in. Background service is active, but not performing driving checks.");
      if (notificationTimer != null) {
        notificationTimer?.cancel();
        notificationTimer = null;
        print("Risk check timer cancelled as user is not logged in.");
      }
      return;
    }

    // Now, check if the app is in the foreground. If it is, we don't run the risk checks.
    if (isAppInForeground) {
      print("User is logged in, but app is in foreground. Skipping background risk checks.");
      if (notificationTimer != null) {
        notificationTimer?.cancel();
        notificationTimer = null;
        print("Risk check timer cancelled as app is in foreground.");
      }
      return;
    }

    // From this point onwards, we know the user IS logged in AND the app IS NOT in the foreground.
    print("User is logged in and app is in background. Performing background checks.");

    try {
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final speed = position.speed;
      final isDriving = speed > 10.0;

      final isNavigationActive = prefs.getBool('isNavigationActive') ?? false;

      if (isDriving && notificationTimer == null && !isNavigationActive) {
        print("User is driving without navigation. Starting risk check timer.");

        notificationTimer =
            Timer.periodic(const Duration(seconds: 15), (timer) async {
          final selectedSpecies = prefs.getStringList('selectedSpecies') ?? [];
          final languageCode = prefs.getString('languageCode') ?? 'en';
          final fcmToken = prefs.getString('fcmToken');

          final currentPosition = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high);
          final risk = await getRiskLevel(currentPosition.latitude,
              currentPosition.longitude, selectedSpecies);

          if (risk >= mediumRiskThreshold &&
              DateTime.now().difference(localLastNotificationTime).inSeconds >= 15 &&
              fcmToken != null) {
            print("User is on a Risk Zone");
            localLastNotificationTime = DateTime.now();
            final level = risk >= highRiskThreshold ? "high" : "medium";

            final title = LanguageConfig.getLocalizedString(
                languageCode, 'wildlifeRiskAlertTitle');
            final bodyKey = level == "high"
                ? 'wildlifeRiskAlertBodyHigh'
                : 'wildlifeRiskAlertBodyMedium';
            final body =
                LanguageConfig.getLocalizedString(languageCode, bodyKey);

            // Send push notification via server
            try {
              final response = await http.post(
              Uri.parse('https://ecoterra.rd.ciencias.ulisboa.pt/send'),
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({
                  "fcmToken": fcmToken,
                  "title": title,
                  "body": body,
                  "button": "false",
                  "changeRoute": "false",
                  "type": "risk"
                }),
              );

              if (response.statusCode == 200) {
                print("Push sent via API: ${response.body}");
              } else {
                print("Failed to send push via API: ${response.body}");
              }
            } catch (e) {
              print("Error sending push notification: $e");
            }

            // Also show local notification immediately in background
            const androidDetails = AndroidNotificationDetails(
              'risk_zone_channel',
              'Wildlife Risk Alerts',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              icon: '@mipmap/ic_launcher',
            );

            await plugin.show(
              0,
              title,
              body,
              const NotificationDetails(android: androidDetails),
            );
          }
        });
      } else if (!isDriving && notificationTimer != null) {
        print("User stopped driving. Stopping risk check timer.");
        notificationTimer?.cancel();
        notificationTimer = null;
      }
    } catch (e) {
      print("Error during background monitoring: $e");
    }
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final log = prefs.getStringList('log') ?? [];
  log.add(DateTime.now().toIso8601String());
  await prefs.setStringList('log', log);
  return true;
}

Future<double> getRiskLevel(double lat, double lon, List<String> selectedSpecies) async {
  try {
    final response = await http.post(
      Uri.parse('https://ecoterra.rd.ciencias.ulisboa.pt/raster'),
      // Uri.parse('http://192.168.1.82:3001/raster'),
      // Uri.parse('http://10.101.121.11:3001/raster'), // testar na uni
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'point': {'lat': lat, 'lon': lon}, 'selectedSpecies': selectedSpecies}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['risk_value'] as num?)?.toDouble() ?? 0.0;
    } else {
      print('Risk fetch failed: ${response.statusCode}');
      return 0.0;
    }
  } catch (e) {
    print('Risk fetch error: $e');
    return 0.0;
  }
}

// New MyApp class to handle app lifecycle
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initialize the foreground state when the app starts
    _setAppForegroundState(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Ensure to mark app as not in foreground when disposed (though detached handles termination)
    _setAppForegroundState(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    print('AppLifecycleState: $state'); // For debugging

    switch (state) {
      case AppLifecycleState.resumed:
        _setAppForegroundState(true);
        print("App is in foreground (resumed).");
        break;
      case AppLifecycleState.inactive:
        // On iOS, inactive means it's about to go to background or is interrupted.
        // On Android, it's often a transient state before paused.
        _setAppForegroundState(false); // Consider it not in foreground for checks
        print("App is inactive.");
        break;
      case AppLifecycleState.paused:
        _setAppForegroundState(false);
        print("App is in background (paused).");
        break;
      case AppLifecycleState.detached:
        // print("State is detached, calling _stopBackgroundServiceAndLogout.");
        print("State is detached");
        _setAppForegroundState(false); // Ensure it's marked as not in foreground
        // _stopBackgroundServiceAndLogout();
        break;
      case AppLifecycleState.hidden: // Only on Android API 34+
        _setAppForegroundState(false);
        print("App is hidden.");
        break;
    }
  }

  Future<void> _setAppForegroundState(bool isForeground) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isAppInForeground', isForeground);
    print("SharedPreferences: isAppInForeground set to $isForeground");
  }

  // Future<void> _stopBackgroundServiceAndLogout() async {
  //   final prefs = await SharedPreferences.getInstance();
  //   await prefs.setBool('isLoggedIn', false);
  //   final isLoggedInCheck = prefs.getBool('isLoggedIn');
  //   print("isLoggedIn set to $isLoggedInCheck in SharedPreferences on termination.");
  //   print("User logged out status updated due to app termination (detached state).");
  //   await Future.delayed(const Duration(milliseconds: 500));
  // }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: monochromeTheme,
      darkTheme: monochromeDarkTheme,
      themeMode: ThemeMode.system,
      home: FutureBuilder(
        future: SharedPreferences.getInstance(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Loading();
          }
          final prefs = snapshot.data as SharedPreferences;
          final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

          if (isLoggedIn) {
            return const NavigationBarExample();
          } else {
            return const WelcomePage();
          }
        },
      ),
      routes: {
        '/home': (context) => const MapPage(),
        '/welcome': (context) => const WelcomePage(),
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/navigation': (context) => NavigationBarExample(),
        '/editProfile': (context) => const EditProfile(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}