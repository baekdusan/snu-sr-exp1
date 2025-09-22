import 'package:flutter/material.dart';
import 'screens/permission_screen.dart';
import 'screens/chatbot_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 어시스턴트',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const PermissionScreen(),
      routes: {
        '/permission': (context) => const PermissionScreen(),
        '/chatbot': (context) => const ChatbotScreen(),
      },
    );
  }
}
