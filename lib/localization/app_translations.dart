import 'package:sint/sint.dart';

import 'app_en_translations.dart';
import 'app_es_translations.dart';

/// Root translation aggregator for neomage.
///
/// Register in [SintMaterialApp] via `translations: AppTranslations()`.
/// Access any value with `NeomageTranslationConstants.key.tr`.
class AppTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
    'en': AppEnTranslations.keys,
    'es': AppEsTranslations.keys,
  };
}
