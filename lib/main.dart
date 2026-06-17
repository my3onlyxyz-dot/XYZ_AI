import 'dart:async';
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  // Jaring pengaman terakhir: kalau ada error async yang lolos dari
  // semua try-catch di RootService/HomeScreen, app tidak force-close,
  // errornya hanya dicetak ke console.
  runZonedGuarded(() {
    runApp(const SahrulControlApp());
  }, (error, stack) {
    debugPrint('Uncaught error (diredam, app tetap berjalan): $error');
  });
}

class SahrulControlApp extends StatelessWidget {
  const SahrulControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sahrul Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00E5FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        cardTheme: CardThemeData(
          color: const Color(0xFF12121A),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF1E1E2E), width: 1),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
