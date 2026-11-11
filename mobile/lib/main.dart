import 'package:flutter/material.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

void main() {
  runApp(const PegasusApp());
}

class PegasusApp extends StatelessWidget {
  const PegasusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pegasus',
      debugShowCheckedModeBanner: false,
      theme: PegasusTheme.dark(),
      home: const Scaffold(
        body: Center(
          child: Text('Pegasus · protocole v$protocolVersion'),
        ),
      ),
    );
  }
}
