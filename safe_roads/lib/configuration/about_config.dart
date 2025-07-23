import 'package:flutter/material.dart';
import 'package:safe_roads/configuration/language_config.dart';

class AboutConfig {
  // UI constants
  static const double maxContentWidth = 600.0;
  static const double borderRadius = 12.0;
  static const double boxShadowBlur = 6.0;
  static const Offset boxShadowOffset = Offset(0, 4);
  static const double logoHeightFactor = 0.25;
  static const double bottomLogoHeightFactor = 0.0745;
  static const double horizontalPaddingFactor = 0.05;
  static const double verticalSpacingFactor = 0.02;
  static const double textBottomPaddingFactor = 0.015;
  static const double tileHorizontalPaddingFactor = 0.04;
  static const double logoSpacingFactor = 0.04;

  // About sections
  static List<Map<String, String>> getAboutSections(String languageCode) {
    return [
      {
        "title": LanguageConfig.getLocalizedString(languageCode, 'why'),
        "body": LanguageConfig.getLocalizedString(languageCode, 'whyBody'),
      },
      {
        "title": LanguageConfig.getLocalizedString(languageCode, 'how'),
        "body": LanguageConfig.getLocalizedString(languageCode, 'howBody'),
      },
      {
        "title": LanguageConfig.getLocalizedString(languageCode, 'who'),
        "body": LanguageConfig.getLocalizedString(languageCode, 'whoBody'),
      },
      {
        "title": LanguageConfig.getLocalizedString(languageCode, 'probabilityLegendTitle'),
        "body": "__legend__", // special marker to insert the legend widget
      },
    ];
  }
}