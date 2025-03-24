import 'package:flutter/material.dart';
import 'package:safe_roads/configuration/language_config.dart';

class AboutConfig {
  static const double containerHeight = 150.0;
  static const double imageHeight = 120.0;
  static const double borderRadius = 12.0;
  static const double boxShadowBlur = 6.0;
  static const Offset boxShadowOffset = Offset(0, 4);
  static const double padding = 16.0;
  static const double sectionSpacing = 20.0;
  static const double titleFontSize = 24.0;

  static List<Map<String, String>> getAboutSections(String languageCode) {
    return [
      {
        "title": LanguageConfig.getLocalizedString(languageCode, 'why'),
        "image": "https://upload.wikimedia.org/wikipedia/commons/e/e4/Tree_frog_%28Pacific%29_edit.jpg"
      },
      {
        "title": LanguageConfig.getLocalizedString(languageCode, 'how'),
        "image": "https://upload.wikimedia.org/wikipedia/commons/8/8b/Salamandra_salamandra_MHNT.jpg"
      },
      {
        "title": LanguageConfig.getLocalizedString(languageCode, 'who'),
        "image": "https://upload.wikimedia.org/wikipedia/commons/3/3f/Frog_on_rock.jpg"
      },
    ];
  }
}
