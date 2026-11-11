import 'package:flutter/material.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

/// Catalogue des modules (contenu au fil des paquets suivants).
class ModulesScreen extends StatelessWidget {
  const ModulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PegasusPanel(
      title: 'Modules',
      child: Center(
        child: Text(
          'Le catalogue des modules arrive bientôt.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.pegasus.textMuted),
        ),
      ),
    );
  }
}
