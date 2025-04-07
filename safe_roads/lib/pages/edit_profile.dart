import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:safe_roads/configuration/language_config.dart';
import 'package:safe_roads/configuration/profile_config.dart';
import 'package:safe_roads/controllers/profile_controller.dart';
import 'package:safe_roads/models/user_preferences.dart';

class EditProfile extends StatefulWidget {
  const EditProfile({super.key});

  @override
  State<EditProfile> createState() => _EditProfileState();
}

class _EditProfileState extends State<EditProfile> {
  String username = ProfileConfig.defaultUsername;
  String email = ProfileConfig.defaultEmail;
  String country = ProfileConfig.defaultCountry;
  String selectedImage = ProfileConfig.defaultAvatar;

  final ProfileController _profileController = ProfileController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _countryController = TextEditingController();
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final List<String> availableImages = ProfileConfig.availableAvatars;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    fetchUserProfile();
  }

  Future<void> fetchUserProfile() async {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    try {
      final profileData = await _profileController.fetchUserProfile();
      print(profileData);
      setState(() {
        username = profileData['username']!;
        email = profileData['email']!;
        country = profileData['country']!;
        selectedImage = profileData['avatar']!;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${LanguageConfig.getLocalizedString(languageCode, 'errorFetchingProfile')}: $e")),
      );
    }
  }

  Future<void> updateProfile() async {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    try {
      await _profileController.updateUser(
        context: context,
        username: _usernameController.text.trim().isNotEmpty
            ? _usernameController.text.trim()
            : username,
        email: email,
        country: _countryController.text.trim().isNotEmpty
            ? _countryController.text.trim()
            : country,
        avatar: selectedImage,
      );

      // Change password if both fields are filled
      if (_currentPasswordController.text.isNotEmpty &&
          _newPasswordController.text.isNotEmpty) {
        await _profileController.changePassword(
          _currentPasswordController.text.trim(),
          _newPasswordController.text.trim(),
        );

        if (!mounted) return; // Ensure the widget is still mounted before using context

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageConfig.getLocalizedString(languageCode, 'passwordUpdated'))),
        );
      } else {
        if (!mounted) return; // Ensure the widget is still mounted before using context

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageConfig.getLocalizedString(languageCode, 'profileUpdated'))),
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return; // Ensure the widget is still mounted before using context

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${LanguageConfig.getLocalizedString(languageCode, 'errorUpdatingProfile')}: $e")),
      );
    }
  }

  void _showImagePicker() {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  LanguageConfig.getLocalizedString(languageCode, 'selectProfile'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: availableImages.length,
                  itemBuilder: (context, index) {
                    final isSelected = availableImages[index] == selectedImage;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedImage = availableImages[index];
                        });
                        Navigator.pop(context);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: isSelected
                              ? Border.all(color: Colors.green, width: 3.0)
                              : null,
                          borderRadius: BorderRadius.circular(60),
                        ),
                        child: CircleAvatar(
                          radius: 50,
                          backgroundImage: AssetImage(availableImages[index]),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageConfig.getLocalizedString(languageCode, 'editProfile')),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20.0),
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundImage: AssetImage(selectedImage),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _showImagePicker,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(8.0),
                            child: const Icon(
                              Icons.edit,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40.0),
                Text(LanguageConfig.getLocalizedString(languageCode, 'enterUsername'), style: const TextStyle(fontSize: 18.0)),
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: username,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    filled: true,
                    fillColor: Colors.grey[200],
                  ),
                ),
                const SizedBox(height: 20.0),
                Text(LanguageConfig.getLocalizedString(languageCode, 'enterEmail'), style: const TextStyle(fontSize: 18.0)),
                TextFormField(
                  enabled: false,
                  decoration: InputDecoration(
                    labelText: email,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    filled: true,
                    fillColor: Colors.grey[200],
                  ),
                ),
                const SizedBox(height: 20.0),
                Text(LanguageConfig.getLocalizedString(languageCode, 'enterCountry'), style: const TextStyle(fontSize: 18.0)),
                TextFormField(
                  controller: _countryController,
                  decoration: InputDecoration(
                    labelText: country,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    filled: true,
                    fillColor: Colors.grey[200],
                  ),
                ),
                const SizedBox(height: 20.0),
                Text(LanguageConfig.getLocalizedString(languageCode, 'currentPass'), style: const TextStyle(fontSize: 18.0)),
                TextFormField(
                  controller: _currentPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: LanguageConfig.getLocalizedString(languageCode, 'enterCurrent'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    filled: true,
                    fillColor: Colors.grey[200],
                  ),
                ),
                const SizedBox(height: 20.0),
                Text(LanguageConfig.getLocalizedString(languageCode, 'newPass'), style: const TextStyle(fontSize: 18.0)),
                TextFormField(
                  controller: _newPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: LanguageConfig.getLocalizedString(languageCode, 'enterNew'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    filled: true,
                    fillColor: Colors.grey[200],
                  ),
                ),
                const SizedBox(height: 30.0),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: updateProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                    ),
                    child: Text(
                      LanguageConfig.getLocalizedString(languageCode, 'update'),
                      style: const TextStyle(fontSize: 18, color: Colors.white),
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
