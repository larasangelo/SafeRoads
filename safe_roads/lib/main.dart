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
import 'package:safe_roads/firebase_options.dart';
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

  // Notifications setup
  final Notifications notifications = Notifications();
  await notifications.setupNotificationChannels();
  
  // Explicitly request permissions
  await requestLocationPermissions();

  // Initialize background service
  await initializeService();

  runApp(
    MultiProvider( 
      providers: [
        ChangeNotifierProvider(create: (_) => UserPreferences()),
        ChangeNotifierProvider(create: (_) => NotificationPreferences()), 
      ], 
      child: MaterialApp(
        theme: monochromeTheme,           // Light theme
        darkTheme: monochromeDarkTheme,   // Dark theme
        themeMode: ThemeMode.system,      // Respect device setting
        initialRoute: '/welcome',
        // initialRoute: '/navigation',
        routes: {
          '/': (context) => const Loading(),
          '/home': (context) => const MapPage(),
          '/welcome': (context) => const WelcomePage(),
          '/login': (context) => const LoginPage(),
          '/register': (context) => const RegisterPage(),
          '/navigation': (context) => NavigationBarExample(key: navigationBarKey),
          '/editProfile': (context) => const EditProfile()
        },
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
}

GlobalKey<NavigationBarExampleState> navigationBarKey = GlobalKey<NavigationBarExampleState>();

// Function to initialize background service
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'my_foreground', // id
    'SafeRoads Foreground Service', // title
    description: 'This channel is used for important notifications.', // description
    importance: Importance.low, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

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
  final status3 = await Permission.locationAlways.request();

  if (status1.isGranted && status2.isGranted && status3.isGranted) {
    print("All location permissions granted");
  } else {
    print("Some permissions denied");
    print("WhenInUse: ${status1.isGranted}");
    print("Location: ${status2.isGranted}");
    print("Always: ${status3.isGranted}");

    if (status3.isPermanentlyDenied) {
      // Send user to app settings
      print("LocationAlways is permanently denied. Open settings.");
      await openAppSettings();
    }
  }
}

const double mediumRiskThreshold = 0.3;
const double highRiskThreshold = 0.5;
DateTime lastNotificationTime = DateTime.now().subtract(Duration(seconds: 30));

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  final plugin = FlutterLocalNotificationsPlugin();

  Timer? notificationTimer;

  Timer.periodic(const Duration(seconds: 20), (monitorTimer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    print("=== Checking motion status ===");

    try {
      final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
      print("onStart: Accessed isLoggedIn = ${prefs.getBool('isLoggedIn')}");

      if (!isLoggedIn) {
        print("User is not logged in. Skipping check.");
        return;
      }

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      double speed = position.speed;
      print("Speed: $speed m/s");

      bool isNavigationActive = prefs.getBool('isNavigationActive') ?? false;
      print("isNavigationActive: $isNavigationActive");

      bool isDriving = speed > 10.0;

      if (isDriving && notificationTimer == null && !isNavigationActive) {
        print("User is driving and not navigating. Starting notification timer.");

        notificationTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
          final selectedSpecies = prefs.getStringList('selectedSpecies') ?? [];
          print("selectedSpecies: $selectedSpecies");
          final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
          print("position: $position");
          final risk = await getRiskLevel(position.latitude, position.longitude, selectedSpecies);
          print("Risk: $risk");

          if (risk >= mediumRiskThreshold) {
            final now = DateTime.now();
            if (now.difference(lastNotificationTime).inSeconds >= 15) {
              print("=== Sending Risk Notification ===");
              lastNotificationTime = now;

              final level = risk >= highRiskThreshold ? "high" : "medium";

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
                'Wildlife Risk Alert',
                'You are in a $level risk zone for animal crossings.',
                const NotificationDetails(android: androidDetails),
              );
            }
          }
        });
      } else if (!isDriving && notificationTimer != null) {
        print("User stopped driving. Cancelling notification timer.");
        notificationTimer?.cancel();
        notificationTimer = null;
      }

    } catch (e) {
      print("Error in monitoring: $e");
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
      // Uri.parse('https://ecoterra.rd.ciencias.ulisboa.pt/raster'),
      // Uri.parse('http://192.168.1.82:3001/raster'),
      Uri.parse('http://10.101.121.11:3001/raster'), // testar na uni
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