import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../../core/providers.dart';
import '../../home/home_layout.dart';
import '../action_feedback.dart';
import '../input/input_service.dart';
import '../module_gate.dart';
import '../registry.dart';

final powerModule = PegasusModule(
  id: 'power',
  name: 'Alimentation',
  icon: Icons.power_settings_new_rounded,
  category: ModuleCategory.system,
  tier: ModuleTier.mvp,
  permission: 'power',
  sizes: const [WidgetSize.small, WidgetSize.medium, WidgetSize.wide],
  defaultSize: WidgetSize.medium,
  screen: (_) => const PowerScreen(),
  widget: (context, size) => PowerPad(
    actions: size == WidgetSize.medium
        ? const [PowerAction.lock, PowerAction.sleep, PowerAction.restart, PowerAction.shutdown]
        : PowerAction.values,
    columns: size == WidgetSize.medium ? 2 : 5,
  ),
);

extension PowerActionUi on PowerAction {
  String get label => switch (this) {
        PowerAction.lock => 'Verrouiller',
        PowerAction.sleep => 'Veille',
        PowerAction.logoff => 'Déconnexion',
        PowerAction.restart => 'Redémarrer',
        PowerAction.shutdown => 'Éteindre',
      };

  IconData get icon => switch (this) {
        PowerAction.lock => Icons.lock_outline_rounded,
        PowerAction.sleep => Icons.bedtime_outlined,
        PowerAction.logoff => Icons.logout_rounded,
        PowerAction.restart => Icons.restart_alt_rounded,
        PowerAction.shutdown => Icons.power_settings_new_rounded,
      };

  String get done => switch (this) {
        PowerAction.lock => 'PC verrouillé',
        PowerAction.sleep => 'PC mis en veille',
        PowerAction.logoff => 'Session fermée',
        PowerAction.restart => 'Le PC redémarre',
        PowerAction.shutdown => 'Le PC s’éteint',
      };
}

/// Exécute [action] ; demande confirmation pour les actions destructrices.
Future<void> runPowerAction(BuildContext context, WidgetRef ref, PowerAction action) async {
  if (action.destructive) {
    final pc = ref.read(pairedPcProvider).value?.agentName ?? 'le PC';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${action.label.toUpperCase()} ?'),
        content: Text('« $pc » : les applications ouvertes seront fermées.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            key: const ValueKey('confirm-power'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(action.label),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
  }
  await runAction(
    context,
    () => ref.read(remoteSenderProvider).request(action.op, {if (action.destructive) 'confirmed': true}),
    success: action.done,
  );
}

/// Grille de boutons d'alimentation.
class PowerPad extends ConsumerWidget {
  const PowerPad({super.key, this.actions = PowerAction.values, this.columns = 5, this.large = false});

  final List<PowerAction> actions;
  final int columns;
  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pegasus;
    final rows = (actions.length / columns).ceil();
    final gap = large ? 12.0 : 6.0;
    Widget button(PowerAction a) => Material(
          color: a.destructive ? c.danger.withValues(alpha: 0.12) : c.surfaceHigh,
          borderRadius: BorderRadius.circular(PegasusRadii.control),
          child: InkWell(
            key: ValueKey('power-${a.name}'),
            borderRadius: BorderRadius.circular(PegasusRadii.control),
            onTap: () => runPowerAction(context, ref, a),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(a.icon, size: large ? 34 : 22, color: a.destructive ? c.danger : c.accent2),
                    const SizedBox(height: 4),
                    Text(a.label, maxLines: 1, style: Theme.of(context).textTheme.labelMedium),
                  ],
                ),
              ),
            ),
          ),
        );

    return ModuleGate(
      permission: 'power',
      compact: !large,
      child: Column(
        children: [
          for (var r = 0; r < rows; r++) ...[
            if (r > 0) SizedBox(height: gap),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var col = 0; col < columns; col++) ...[
                    if (col > 0) SizedBox(width: gap),
                    Expanded(
                      child: r * columns + col < actions.length
                          ? button(actions[r * columns + col])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PowerScreen extends StatelessWidget {
  const PowerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ALIMENTATION')),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Center(
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: PowerPad(columns: 2, large: true),
            ),
          ),
        ),
      ),
    );
  }
}
