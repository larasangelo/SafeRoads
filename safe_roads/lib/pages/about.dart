import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:safe_roads/configuration/about_config.dart';
import 'package:safe_roads/models/user_preferences.dart';

class About extends StatelessWidget {
  const About({super.key});

  @override
  Widget build(BuildContext context) {
    // Get language preference from UserPreferences
    String languageCode = Provider.of<UserPreferences>(context).languageCode;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AboutConfig.padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: AboutConfig.getAboutSections(languageCode).map((section) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section["title"]!,
                      style: const TextStyle(
                        fontSize: AboutConfig.titleFontSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10.0),
                    Container(
                      height: AboutConfig.containerHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AboutConfig.borderRadius),
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.3),
                            blurRadius: AboutConfig.boxShadowBlur,
                            offset: AboutConfig.boxShadowOffset,
                          ),
                        ],
                      ),
                      child: const Center(
                        // child: Image.network(
                        //   section["image"]!,
                        //   fit: BoxFit.contain,
                        //   height: AboutConfig.imageHeight,
                        // ),
                      ),
                    ),
                    const SizedBox(height: AboutConfig.sectionSpacing),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
