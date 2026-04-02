import 'package:flutter/material.dart';
import 'package:sint/sint.dart';

import 'claw_routes.dart';
import 'root_binding.dart';
import 'ui/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FlutterClawApp());
}

class FlutterClawApp extends StatelessWidget {
  const FlutterClawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SintMaterialApp(
      title: 'Flutter Claw',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      initialRoute: ClawRouteConstants.root,
      sintPages: ClawRoutes.getAppRoutes(),
      binds: RootBinding().dependencies(),
    );
  }
}
