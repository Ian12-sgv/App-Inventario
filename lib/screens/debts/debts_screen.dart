import 'package:flutter/material.dart';
import '../../ui/app_theme.dart';

class DebtsScreen extends StatelessWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
  appBar: AppBar(title: const Text('Tú')),
  body: const Center(
    child: Text(
      'Home (placeholder)',
      style: TextStyle(fontSize: 18, color: AppTheme.navy),
    ),
  ),
);

  }
}
