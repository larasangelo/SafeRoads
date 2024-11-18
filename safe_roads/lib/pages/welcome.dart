import 'package:flutter/material.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage("assets/IMG_8583.JPG"),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Buttons at the bottom
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Login Button
                  SizedBox(
                    width: double.infinity, // Full width
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushNamed(context, '/login'); // Navigate to login page
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                      ),
                      child: const Text(
                        "Login",
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Register Button
                  SizedBox(
                    width: double.infinity, // Full width
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pushNamed(context, '/register'); // Navigate to register page
                      },
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                        side: const BorderSide(
                          width: 1,
                          color: Colors.black,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: const Text(
                        "Register",
                        style: TextStyle(fontSize: 18, color: Colors.black),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )

        ],
      ),
    );
  }
}
