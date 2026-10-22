import 'package:flutter/material.dart';

import '../screens/home_screen.dart';

class SheetMusicRookieApp extends StatelessWidget {
  const SheetMusicRookieApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff315b4c);
    return MaterialApp(
      title: 'Sheet Music Rookie',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xfff7f4ed),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: Color(0xfffffdf8),
          margin: EdgeInsets.zero,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
