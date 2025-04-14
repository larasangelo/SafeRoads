import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:safe_roads/configuration/about_config.dart';
import 'package:safe_roads/configuration/language_config.dart';
import 'package:safe_roads/models/user_preferences.dart';

class About extends StatelessWidget {
  const About({super.key});

  @override
  Widget build(BuildContext context) {
    final String languageCode = Provider.of<UserPreferences>(context).languageCode;
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;

    // Dynamic values from screen size and config
    final horizontalPadding = screenWidth * AboutConfig.horizontalPaddingFactor;
    final verticalSpacing = screenHeight * AboutConfig.verticalSpacingFactor;
    final logoHeight = screenHeight * AboutConfig.logoHeightFactor;
    final bottomLogoHeight = screenHeight * AboutConfig.bottomLogoHeightFactor;
    final tilePadding = screenWidth * AboutConfig.tileHorizontalPaddingFactor;
    final textPaddingBottom = screenHeight * AboutConfig.textBottomPaddingFactor;
    final logoSpacing = screenWidth * AboutConfig.logoSpacingFactor;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AboutConfig.maxContentWidth),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(horizontalPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Top Logo
                  Padding(
                    padding: EdgeInsets.only(bottom: verticalSpacing),
                    child: Image.asset(
                      'assets/logos/SafeRoads_logo.png',
                      height: logoHeight,
                      fit: BoxFit.contain,
                    ),
                  ),

                  // Section dropdowns
                  ...AboutConfig.getAboutSections(languageCode).map((section) {
                    return Padding(
                      padding: EdgeInsets.only(bottom: verticalSpacing),
                      child: Container(
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
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            dividerColor: Colors.transparent,
                            splashColor: Colors.transparent,
                          ),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.symmetric(horizontal: tilePadding),
                            title: Text(
                              section["title"]!,
                              style: theme.textTheme.headlineSmall!.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            children: [
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  tilePadding,
                                  0,
                                  tilePadding,
                                  textPaddingBottom,
                                ),
                                child: Text(
                                  LanguageConfig.getLocalizedString(languageCode, section['body']!),
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),

                  // Bottom logos
                  SizedBox(height: verticalSpacing),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: screenWidth * 0.02, 
                    children: [
                      Image.asset(
                        'assets/logos/FCUL_logo.png',
                        height: bottomLogoHeight,
                        fit: BoxFit.contain,
                      ),
                      SizedBox(width: logoSpacing),
                      Image.asset(
                        'assets/logos/lasige_logo.png',
                        height: bottomLogoHeight,
                        fit: BoxFit.contain,
                      ),
                      SizedBox(width: logoSpacing),
                      Image.asset(
                        'assets/logos/ce3c_logo_black.png',
                        height: bottomLogoHeight,
                        fit: BoxFit.contain,
                      ),
                    ],
                  ),
                  SizedBox(height: verticalSpacing * 0.8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}