import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:safe_roads/firebase_options.dart';
import 'package:safe_roads/pages/edit_profile.dart';
import 'package:safe_roads/pages/home.dart';
import 'package:safe_roads/pages/loading.dart';
import 'package:safe_roads/pages/login.dart';
import 'package:safe_roads/pages/navigation_bar.dart';
import 'package:safe_roads/pages/register.dart';
import 'package:safe_roads/pages/welcome.dart';

// For Background Messaging
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensures proper binding
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(MaterialApp(
    initialRoute: '/welcome',  //THIS IS THE RIGHT ONE
    // initialRoute: '/navigation', //FOR TESTING THE NAVIGATION
    routes: {
      '/': (context) => Loading(),
      '/home': (context) => const MapPage(),
      '/welcome': (context) => const WelcomePage(),
      '/login': (context) => const LoginPage(),
      '/register': (context) => const RegisterPage(),
      '/navigation': (context) => const NavigationBarExample(),
      '/editProfile': (context) => const EditProfile()
    },
  ));
}