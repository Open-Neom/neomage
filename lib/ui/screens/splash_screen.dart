import 'package:flutter/material.dart';
import 'package:sint/sint.dart';

import '../../claw_routes.dart';
import '../../data/auth/auth_service.dart';
import '../../utils/constants/neom_claw_assets.dart';
import '../controllers/chat_controller.dart';

/// Initial route — checks auth config and redirects.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final authService = AuthService();
    final hasConfig = await authService.hasValidConfig();

    if (!mounted) return;

    if (hasConfig) {
      final chat = Sint.find<ChatController>();
      final initialized = await chat.initialize();
      if (mounted) {
        Sint.offAllNamed(
          initialized ? ClawRouteConstants.chat : ClawRouteConstants.onboarding,
        );
      }
    } else {
      Sint.offAllNamed(ClawRouteConstants.onboarding);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              NeomClawAssets.appIcon,
              width: 120,
              height: 120,
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
