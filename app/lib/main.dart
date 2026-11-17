library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/workbench/presentation/workbench_page.dart';

void main() {
  runApp(const ProviderScope(child: AgentHitlWorkbenchApp()));
}

class AgentHitlWorkbenchApp extends StatelessWidget {
  const AgentHitlWorkbenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agent HITL Workbench',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
      ),
      home: const WorkbenchPage(),
    );
  }
}
