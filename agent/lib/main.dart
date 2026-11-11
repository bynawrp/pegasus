import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_ui/pegasus_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: 'Pegasus',
        size: Size(1100, 700),
        minimumSize: Size(960, 600),
        center: true,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  runApp(const ProviderScope(child: PegasusAgentApp()));
}

class PegasusAgentApp extends StatelessWidget {
  const PegasusAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pegasus',
      debugShowCheckedModeBanner: false,
      theme: PegasusTheme.build(),
      home: const AgentShell(),
    );
  }
}
