import 'package:flutter/material.dart';

import 'ui/home_page.dart';

void main() => runApp(const FiveStateDemoApp());

class FiveStateDemoApp extends StatelessWidget {
  const FiveStateDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI に旅の相談',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'NotoSansJP',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD9A441),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}
