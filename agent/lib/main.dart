import 'package:flutter/material.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

void main() {
  runApp(const PegasusAgentApp());
}

class PegasusAgentApp extends StatelessWidget {
  const PegasusAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pegasus',
      debugShowCheckedModeBanner: false,
      theme: PegasusTheme.dark(),
      home: const Scaffold(
        body: Center(
          child: Text('Pegasus · agent · protocole v$protocolVersion · port $defaultPort'),
        ),
      ),
    );
  }
}
