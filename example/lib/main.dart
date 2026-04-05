import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sint/sint.dart';
import 'package:sint_sentinel/sint_sentinel.dart';

import 'package:neomage/core/agent/neomage_system_prompt.dart';
import 'package:neomage/neomage_routes.dart';
import 'package:neomage/localization/app_translations.dart';
import 'package:neomage/root_binding.dart';
import 'package:neomage/ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await SintSentinel.init(config: SentinelConfig.production());
  SintSentinel.logger.i('neomage starting...');
  await NeomageSystemPrompt.load();
  SintSentinel.logger.i('personality modules loaded');
  runApp(const NeomageApp());
}

class NeomageApp extends StatelessWidget {
  const NeomageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SentinelApp(
      config: SentinelConfig.production(),
      child: SintMaterialApp(
        title: 'Neomage',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        translations: AppTranslations(),
        locale: const Locale('es'),
        fallbackLocale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('es')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        initialRoute: NeomageRouteConstants.root,
        sintPages: NeomageRoutes.getAppRoutes(),
        binds: RootBinding().dependencies(),
      ),
    );
  }
}
