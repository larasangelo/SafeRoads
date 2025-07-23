import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:safe_roads/configuration/language_config.dart';
import 'package:safe_roads/main.dart';
import 'package:safe_roads/models/user_preferences.dart';
import 'package:safe_roads/pages/loading.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../controllers/auth_controller.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final AuthController _authController = AuthController();

  bool _obscurePassword = true; // Controls password visibility
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    // WidgetsBinding.instance.addPostFrameCallback((_) async {
    //   final prefs = await SharedPreferences.getInstance();
    //   await prefs.setBool('isLoggedIn', false);
    // });
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    double screenHeight = MediaQuery.of(context).size.height;
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.primary),
          onPressed: () {
            Navigator.pushNamed(context, '/welcome'); // Navigate to Welcome page
          },
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(screenWidth * 0.06), 
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: screenHeight * 0.03), 
                // Welcome Text
                Text(
                  LanguageConfig.getLocalizedString(languageCode, 'welcome'),
                  style: TextStyle(
                    fontSize: screenWidth * 0.08,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: screenHeight * 0.05),
                // Email Input
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: LanguageConfig.getLocalizedString(languageCode, 'inputEmail'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    filled: true,
                    // fillColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return LanguageConfig.getLocalizedString(languageCode, 'pleaseEmail');
                    }
                    return null;
                  },
                ),
                SizedBox(height: screenHeight * 0.025),
                // Password Input with Toggle Visibility
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: LanguageConfig.getLocalizedString(languageCode, 'userPass'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    filled: true,
                    // fillColor: Theme.of(context).colorScheme.onPrimary,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword; // Toggle password visibility
                        });
                      },
                    ),
                  ),
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return LanguageConfig.getLocalizedString(languageCode, 'pleasePass');
                    }
                    return null;
                  },
                ),
                SizedBox(height: screenHeight * 0.015),
                // Forgot Password Link
                // Align(
                //   alignment: Alignment.centerRight,
                //   child: GestureDetector(
                //     onTap: () {
                //       Navigator.pushNamed(context, '/forgot-password'); // Navigate to forgot password page
                //     },
                //     child: Text(
                //       LanguageConfig.getLocalizedString(languageCode, 'forgotPass'),
                //       style: TextStyle(
                //         color: Colors.blue,
                //         fontSize: screenWidth * 0.04, 
                //         fontWeight: FontWeight.bold,
                //         decoration: TextDecoration.underline,
                //       ),
                //     ),
                //   ),
                // ),
                SizedBox(height: screenHeight * 0.03),
                // Login Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (_formKey.currentState!.validate()) {
                        // Navigate to loading screen
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const Loading()),
                        );

                        // Perform login
                        bool loginSuccess = await _authController.loginUser(
                          context: context,
                          email: _emailController.text.trim(),
                          password: _passwordController.text.trim(),
                        );

                        print("loginSuccess: $loginSuccess");
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('isLoggedIn', true);
                        print("Login: Saved isLoggedIn = ${prefs.getBool('isLoggedIn')}");

                        await initializeService();

                        // Ensure the widget is still mounted before navigation
                        if (!context.mounted) return;

                        // Navigate based on login result
                        if (loginSuccess) {
                          Navigator.pushReplacementNamed(context, '/navigation');
                        } else {
                          Navigator.pushReplacementNamed(context, '/login');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                LanguageConfig.getLocalizedString(languageCode, 'loginFailed'),
                              ),
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      padding: EdgeInsets.symmetric(vertical: screenHeight * 0.02), 
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                    ),
                    child: Text(
                      LanguageConfig.getLocalizedString(languageCode, 'login'),
                      style: TextStyle(fontSize: screenWidth * 0.05, color: Theme.of(context).colorScheme.onPrimary), 
                    ),
                  ),
                ),
                SizedBox(height: screenHeight * 0.025), 
                // Register Now Text
                Center(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pushNamed(context, '/register'); // Navigate to register page
                    },
                    child: RichText(
                      text: TextSpan(
                        text: LanguageConfig.getLocalizedString(languageCode, 'noAccount'),
                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: screenWidth * 0.04), 
                        children: [
                          TextSpan(
                            text: LanguageConfig.getLocalizedString(languageCode, 'registerNow'),
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}