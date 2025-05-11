import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:safe_roads/app_lifecycle_observer.dart';
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

  WidgetsBinding.instance.addObserver(AppLifecycleObserver());

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

// Ios background function
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  SharedPreferences preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  final log = preferences.getStringList('log') ?? <String>[];
  log.add(DateTime.now().toIso8601String());
  await preferences.setStringList('log', log);

  return true;
}

// OnStart function to update service state
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  SharedPreferences preferences = await SharedPreferences.getInstance();
  await preferences.setString("hello", "world");

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });
}