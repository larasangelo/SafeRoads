import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:safe_roads/firebase_options.dart';

// For Background Messaging
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  String? fcmToken;

  @override
  void initState() {
    super.initState();
    _setupFirebaseMessaging();
  }

  void _setupFirebaseMessaging() async {
    // Request permission for notifications only once when the app initializes
    NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print("Notification permission granted");

      // Get FCM token
      final token = await FirebaseMessaging.instance.getToken();
      print("FCM Token: $token");
      if (token != null) {
        setState(() {
          fcmToken = token;
        });
      }
    } else {
      print("Notification permission denied");
    }

    // Listen for messages when the app is in the foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("Foreground message received: ${message.notification?.title}");
      _showForegroundNotification(message);
    });
  }

  void _showForegroundNotification(RemoteMessage message) {
    if (message.notification != null) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text("${message.notification!.title}: ${message.notification!.body}"),
        ),
      );
    }
  }

  // Send notification to server when button is clicked
  void _sendNotification() async {
    if (fcmToken != null) {
      await sendTokenToServer(fcmToken!);
    } else {
      print("FCM Token not available.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: Scaffold(
        appBar: AppBar(title: const Text("Safe Roads")),
        body: Center(
          child: TextButton(
            onPressed: _sendNotification,  // Send notification on button click
            child: const Text("Try Post"),
          ),
        ),
      ),
    );
  }

  Future<void> sendTokenToServer(String fcmToken) async {
    const serverUrl = 'http://192.168.1.82:3000/send'; // Your server's URL
    try {
      final response = await http.post(
        Uri.parse(serverUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"fcmToken": fcmToken}),
      );
      if (response.statusCode == 200) {
        print("Notification sent successfully");
      } else {
        print("Failed to send notification: ${response.body}");
      }
    } catch (e) {
      print("Error sending token to server: $e");
    }
  }
}
