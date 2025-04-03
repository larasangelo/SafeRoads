import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:safe_roads/configuration/language_config.dart';
import 'package:safe_roads/models/user_preferences.dart';
import 'package:safe_roads/pages/loading.dart';
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
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.pushNamed(context, '/welcome'); // Navigate to Welcome page
          },
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20.0), 
                // Welcome Text
                Text(
                  LanguageConfig.getLocalizedString(languageCode, 'welcome'),
                  style: const TextStyle(
                    fontSize: 28.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 40.0),
                // Email Input
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: LanguageConfig.getLocalizedString(languageCode, 'inputEmail'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    filled: true,
                    fillColor: Colors.grey[200],
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return LanguageConfig.getLocalizedString(languageCode, 'pleaseEmail');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20.0),
                // Password Input with Toggle Visibility
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: LanguageConfig.getLocalizedString(languageCode, 'userPass'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    filled: true,
                    fillColor: Colors.grey[200],
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
                const SizedBox(height: 10.0),
                // Forgot Password Link
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pushNamed(context, '/forgot-password'); // Navigate to forgot password page
                    },
                    child: Text(
                      LanguageConfig.getLocalizedString(languageCode, 'forgotPass'),
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30.0),
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

                        // Ensure the widget is still mounted before navigation
                        if (!context.mounted) return;

                        // Navigate based on login result
                        if (loginSuccess) {
                          Navigator.pushReplacementNamed(context, '/navigation');
                        } else {
                          Navigator.pushReplacementNamed(context, '/login');
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                    ),
                    child: Text(
                      LanguageConfig.getLocalizedString(languageCode, 'login'),
                      style: const TextStyle(fontSize: 18, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 20.0), 
                // Register Now Text
                Center(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pushNamed(context, '/register'); // Navigate to register page
                    },
                    child: RichText(
                      text: TextSpan(
                        text: LanguageConfig.getLocalizedString(languageCode, 'noAccount'),
                        style: const TextStyle(color: Colors.black, fontSize: 16),
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
