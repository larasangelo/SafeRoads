import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:safe_roads/configuration/language_config.dart';
import 'dart:async';
import 'package:safe_roads/models/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Notifications {
  static final Notifications _instance = Notifications._internal();
  factory Notifications() => _instance;
  Notifications._internal(); // Singleton pattern

  BuildContext? _latestContext;
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>(); // Defined once

  String? fcmToken;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final AndroidInitializationSettings androidInitializationSettings =
      const AndroidInitializationSettings('@mipmap/ic_launcher');

  VoidCallback? onSwitchRoute;
  VoidCallback? ignoreSwitchRoute;

  StreamSubscription<RemoteMessage>? _messageSubscription;
  final Map<String, Timer> _debounceTimers = {}; // Debounce timers per notification type
  final Duration _debounceDelay = const Duration(milliseconds: 500);

  // Keep track of currently displayed overlay entries
  final Set<OverlayEntry> _currentOverlays = {};

  void setContext(BuildContext context) {
    _latestContext = context;
  }

  Future<StreamSubscription<RemoteMessage>?> setupFirebaseMessaging(
      BuildContext? context,
      StreamSubscription<RemoteMessage>? existingSubscription) async {
    NotificationSettings settings =
        await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
      announcement: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print("Notification permission granted");
      fcmToken = await FirebaseMessaging.instance.getToken();
      print("FCM Token: $fcmToken");
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcmToken', fcmToken!);

      if (existingSubscription != null) {
        _messageSubscription = existingSubscription;
        _messageSubscription?.resume();
        return _messageSubscription;
      }

      _messageSubscription =
          FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print(
            "Foreground message received: ${message.data['title']} (Type: ${message.data['type']})");
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showForegroundNotification(message);
        });
      });

      return _messageSubscription;
    } else {
      print("Notification permission denied");
    }
    return null;
  }

  Future<void> setupNotificationChannels() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'channel_id_1',
      'High Importance Notifications',
      description: 'Channel for default notifications',
      importance: Importance.high,
      playSound: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  final AudioPlayer _audioPlayer = AudioPlayer();

  void playNotificationSound() async {
    try {
      await _audioPlayer.play(AssetSource('notification.mp3'));
      print("Notification sound is playing.");
      _audioPlayer.onPlayerComplete.listen((event) {
        print("Notification sound has finished playing.");
      });
    } catch (e) {
      print("Error playing sound: $e");
    }
  }

  void showForegroundNotification(RemoteMessage message) async {
    final String? notificationType = message.data['type'];
    if (notificationType == null) {
      _displayOverlay(message); // Display if no type is specified
      return;
    }

    if (_debounceTimers.containsKey(notificationType) &&
        (_debounceTimers[notificationType]?.isActive ?? false)) {
      print("Debouncing notification of type: $notificationType");
      return;
    }

    _debounceTimers[notificationType] = Timer(_debounceDelay, () {
      print(
          "Executing showForegroundNotification for type: $notificationType at: ${DateTime.now().millisecondsSinceEpoch}");
      _debounceTimers.remove(notificationType); // Allow next notification of this type after the delay
      _displayOverlay(message);
    });
  }

  void _displayOverlay(RemoteMessage message) async {
    if (_latestContext == null) {
      print("No valid context available to show notification.");
      return;
    }

    flutterLocalNotificationsPlugin.show(
      0,
      null,
      null,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'channel_id_1',
          'Default Notifications',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          icon: '@mipmap/ic_launcher',
          visibility: NotificationVisibility.secret,
          showWhen: false,
          shortcutId: "silent_notification",
        ),
      ),
    );
    // playNotificationSound();

    bool showButton = message.data['button'] == 'true';
    bool changeRoute = message.data['changeRoute'] == 'true';

    final overlay = Overlay.of(_latestContext!, rootOverlay: true);
    late OverlayEntry overlayEntry;
    bool isInteracted = false;
    late AnimationController animationController;

    overlayEntry = OverlayEntry(
      builder: (context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        String languageCode =
            Provider.of<UserPreferences>(context, listen: false).languageCode;

        print("Estou a entrar no OverLay (Type: ${message.data['type']})");

        return StatefulBuilder(
          builder: (context, setState) {
            animationController = AnimationController(
              vsync: Navigator.of(context),
              duration: const Duration(seconds: 6),
            );

            animationController.forward();

            return Positioned(
              top: showButton ? screenHeight * 0.1 : screenHeight * 0.65,
              left: screenWidth * 0.01,
              right: screenWidth * 0.01,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: EdgeInsets.all(screenWidth * 0.04),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onPrimary,
                    borderRadius: BorderRadius.circular(screenWidth * 0.03),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10.0,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message.data['title'] ?? 'Notification',
                        style: TextStyle(
                          fontSize: screenWidth * 0.05,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: screenHeight * 0.01),
                      Text(
                        message.data['body'] ?? '',
                        style: TextStyle(fontSize: screenWidth * 0.04),
                        textAlign: TextAlign.center,
                      ),
                      if (showButton) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            changeRoute
                                ? _buildAnimatedButton(
                                    context,
                                    screenWidth,
                                    screenHeight,
                                    languageCode,
                                    'reRouteButton',
                                    animationController,
                                    () {
                                      if (!isInteracted) {
                                        isInteracted = true;
                                        animationController.stop();
                                        onSwitchRoute?.call();
                                        _removeOverlay(overlayEntry);
                                      }
                                    },
                                  )
                                : _buildButton(
                                    context,
                                    screenWidth,
                                    screenHeight,
                                    languageCode,
                                    'reRouteButton',
                                    Theme.of(context).colorScheme.primary,
                                    Theme.of(context).colorScheme.onPrimary,
                                    () {
                                      if (!isInteracted) {
                                        isInteracted = true;
                                        animationController.stop();
                                        onSwitchRoute?.call();
                                        _removeOverlay(overlayEntry);
                                      }
                                    },
                                  ),
                            !changeRoute
                                ? _buildAnimatedButton(
                                    context,
                                    screenWidth,
                                    screenHeight,
                                    languageCode,
                                    'ignoreButton',
                                    animationController,
                                    () {
                                      if (!isInteracted) {
                                        isInteracted = true;
                                        animationController.stop();
                                        ignoreSwitchRoute?.call();
                                        _removeOverlay(overlayEntry);
                                      }
                                    },
                                  )
                                : _buildButton(
                                    context,
                                    screenWidth,
                                    screenHeight,
                                    languageCode,
                                    'ignoreButton',
                                    Theme.of(context).colorScheme.primary,
                                    Theme.of(context).colorScheme.onPrimary,
                                    () {
                                      if (!isInteracted) {
                                        isInteracted = true;
                                        animationController.stop();
                                        ignoreSwitchRoute?.call();
                                        _removeOverlay(overlayEntry);
                                      }
                                    },
                                  ),
                          ],
                        ),

                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    overlay.insert(overlayEntry);
    _currentOverlays.add(overlayEntry); // Keep track of the new overlay

    Future.delayed(const Duration(seconds: 5), () {
      if (_currentOverlays.contains(overlayEntry) && !isInteracted) {
        isInteracted = true;
        _removeOverlay(overlayEntry);
        if (changeRoute) {
          onSwitchRoute?.call();
        } else {
          ignoreSwitchRoute?.call();
        }
      }
    });
  }

  void _removeOverlay(OverlayEntry entry) {
    if (entry.mounted) {
      entry.remove();
    }
    _currentOverlays.remove(entry);
  }

  Widget _buildAnimatedButton(
    BuildContext context,
    double screenWidth,
    double screenHeight,
    String languageCode,
    String buttonKey,
    AnimationController animationController,
    VoidCallback onPressed,
  ) {
    const double buttonWidth = 0.3;
    const double buttonHeight = 0.06;

    return ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth: screenWidth * buttonWidth,
          maxHeight: screenHeight * buttonHeight),
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: animationController,
            builder: (context, child) {
              return Container(
                width: screenWidth * buttonWidth,
                height: screenHeight * buttonHeight,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white),
                  borderRadius: BorderRadius.circular(50),
                  gradient: LinearGradient(
                    colors: [
                      const Color.fromARGB(255, 62, 62, 62).withValues(alpha:0.5),
                      Colors.black.withValues(alpha:0.9),
                    ],
                    stops: [0.0, animationController.value],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              );
            },
          ),
          SizedBox(
            width: screenWidth * buttonWidth,
            height: screenHeight * buttonHeight,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
              ),
              child: Text(
                LanguageConfig.getLocalizedString(languageCode, buttonKey),
                style: TextStyle(fontSize: screenWidth * 0.045, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton(
    BuildContext context,
    double screenWidth,
    double screenHeight,
    String languageCode,
    String buttonKey,
    Color backgroundColor,
    Color textColor,
    VoidCallback onPressed,
  ) {
    const double buttonWidth = 0.3; // Use the same constants
    const double buttonHeight = 0.06;
    return ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth: screenWidth * buttonWidth,
          maxHeight: screenHeight * buttonHeight),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor, shadowColor: Colors.transparent),
        child: Text(
          LanguageConfig.getLocalizedString(languageCode, buttonKey),
          style: TextStyle(fontSize: screenWidth * 0.045, color: textColor),
        ),
      ),
    );
  }
}