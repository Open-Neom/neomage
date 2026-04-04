import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sint/sint.dart';
import 'package:sint_sentinel/sint_sentinel.dart';

import 'claw_routes.dart';
import 'root_binding.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await SintSentinel.init(config: SentinelConfig.production());
  SintSentinel.logger.i('neom_claw starting...');
  runApp(const FlutterClawApp());
}

class FlutterClawApp extends StatelessWidget {
  const FlutterClawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SentinelApp(
      config: SentinelConfig.production(),
      child: SintMaterialApp(
        title: 'Neom Claw',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        initialRoute: ClawRouteConstants.root,
        sintPages: ClawRoutes.getAppRoutes(),
        binds: RootBinding().dependencies(),
      ),
    );
  }
}
