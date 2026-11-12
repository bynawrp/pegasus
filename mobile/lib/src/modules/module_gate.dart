import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_link/pegasus_link.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../core/providers.dart';

/// Pourquoi un module ne peut pas être utilisé, ou `null` s'il peut l'être.
String? moduleBlockReason(LinkState link, String? permission) {
  if (!link.isConnected) return 'PC non connecté';
  final info = link.info!;
  if (info.paused) return 'En pause sur le PC';
  if (permission != null && info.modules[permission] == false) return 'Désactivé sur le PC';
  return null;
}

/// Grise un module (et bloque les gestes) quand il n'est pas utilisable.
class ModuleGate extends ConsumerWidget {
  const ModuleGate({super.key, required this.permission, required this.child, this.compact = false});

  final String? permission;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reason = moduleBlockReason(ref.watch(linkStateProvider), permission);
    if (reason == null) return child;
    final c = context.pegasus;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        IgnorePointer(child: Opacity(opacity: 0.35, child: child)),
        Positioned.fill(
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Container(
                key: const ValueKey('module-blocked'),
                padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 14, vertical: compact ? 4 : 8),
                decoration: BoxDecoration(
                  color: c.surfaceHigh,
                  borderRadius: BorderRadius.circular(PegasusRadii.control),
                  border: Border.all(color: c.line),
                ),
                child: Text(reason, maxLines: 1, style: Theme.of(context).textTheme.labelLarge),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
