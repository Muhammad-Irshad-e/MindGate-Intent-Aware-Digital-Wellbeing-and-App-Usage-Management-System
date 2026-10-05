import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'presentation/navigation/main_navigation_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MindGateApp());
}

class MindGateApp extends StatelessWidget {
  const MindGateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MindGate',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const MainNavigationScreen(),
    );
  }
}
