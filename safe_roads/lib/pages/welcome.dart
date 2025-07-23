import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:safe_roads/configuration/language_config.dart';
import 'package:safe_roads/models/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', false);
    });
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    double screenHeight = MediaQuery.of(context).size.height;
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage("assets/background.jpg"),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Column for logo and buttons
          Column(
            children: [
              SizedBox(height: screenHeight * 0.15), 

              // SafeRoads Logo in the lower-middle
              Center(
                child: Image.asset(
                  'assets/logos/SafeRoads_logo.png',  
                  width: screenWidth * 0.9,
                  height: screenHeight * 0.5, 
                ),
              ),
              // Buttons at the bottom
              const Spacer(),
              Padding(
                padding: EdgeInsets.all(screenWidth * 0.06), 
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Login Button
                    SizedBox(
                      width: double.infinity, 
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/login'); // Navigate to login page
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          padding: EdgeInsets.symmetric(vertical: screenHeight * 0.02), 
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.0),
                          ),
                        ),
                        child: Text(
                          LanguageConfig.getLocalizedString(languageCode, 'login'),
                          style: TextStyle(
                            fontSize: screenWidth * 0.05, // Dynamic font size
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.015), // Dynamic spacing
                    // Register Button
                    SizedBox(
                      width: double.infinity, // Full width
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/register'); // Navigate to register page
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: screenHeight * 0.02), 
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.0),
                          ),
                          side: const BorderSide(
                            width: 1,
                            color: Colors.black,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Text(
                          LanguageConfig.getLocalizedString(languageCode, 'register'),
                          style: TextStyle(
                            fontSize: screenWidth * 0.05, 
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}