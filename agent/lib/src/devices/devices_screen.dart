import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_link/pegasus_link.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../app/format.dart';
import '../app/shell.dart';
import '../core/agent_controller.dart';

/// Appareils associés : état, renommer, révoquer. Paginé (pas de défilement).
class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  int _page = 0;
  static const _rowHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentControllerProvider);
    final text = Theme.of(context).textTheme;
    final devices = [...state.devices]
      ..sort((a, b) {
        final ca = state.connected.contains(a.id) ? 0 : 1;
        final cb = state.connected.contains(b.id) ? 0 : 1;
        return ca != cb ? ca - cb : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('APPAREILS', style: text.headlineMedium)),
            FilledButton.icon(
              key: const ValueKey('pair-new'),
              onPressed: () {
                ref.read(agentControllerProvider.notifier).renewPairing();
                ref.read(agentSectionProvider.notifier).select(AgentSection.home);
              },
              icon: const Icon(Icons.qr_code_2_rounded, size: 18),
              label: const Text('Associer un téléphone'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: PegasusPanel(
            title: '${devices.length} appareil${devices.length > 1 ? 's' : ''} associé${devices.length > 1 ? 's' : ''}',
            child: devices.isEmpty
                ? Center(child: Text('Aucun appareil associé pour l’instant.', style: text.bodyMedium))
                : LayoutBuilder(builder: (context, box) {
                    final perPage = ((box.maxHeight - 52) / _rowHeight).floor().clamp(1, 1000);
                    final pages = (devices.length / perPage).ceil();
                    final page = _page.clamp(0, pages - 1);
                    final slice = devices.skip(page * perPage).take(perPage).toList();
                    return Column(
                      children: [
                        for (final d in slice)
                          SizedBox(
                            height: _rowHeight,
                            child: _DeviceRow(device: d, connected: state.connected.contains(d.id)),
                          ),
                        const Spacer(),
                        if (pages > 1)
                          SizedBox(
                            height: 44,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
                                  icon: const Icon(Icons.chevron_left_rounded),
                                ),
                                Text('${page + 1} / $pages', style: text.labelLarge),
                                IconButton(
                                  onPressed: page < pages - 1 ? () => setState(() => _page = page + 1) : null,
                                  icon: const Icon(Icons.chevron_right_rounded),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  }),
          ),
        ),
      ],
    );
  }
}

class _DeviceRow extends ConsumerWidget {
  const _DeviceRow({required this.device, required this.connected});
  final PairedDevice device;
  final bool connected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    final seen = device.lastSeen;
    final subtitle = connected
        ? 'Connecté'
        : seen == null
            ? 'Associé le ${formatDateTime(device.pairedAt)}'
            : 'Vu ${formatDateTime(seen)}';
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      child: Row(
        children: [
          Icon(device.platform == 'ios' ? Icons.phone_iphone_rounded : Icons.phone_android_rounded,
              color: connected ? c.accent2 : c.textMuted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: connected ? c.success : c.textMuted)),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('rename-${device.id}'),
            tooltip: 'Renommer',
            onPressed: () => _rename(context, ref),
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
          TextButton(
            key: ValueKey('revoke-${device.id}'),
            onPressed: () => _revoke(context, ref),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: const Text('Révoquer'),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: device.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('RENOMMER'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 64,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (name != null) ref.read(agentControllerProvider.notifier).rename(device.id, name);
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('RÉVOQUER ?'),
        content: Text('« ${device.name} » ne pourra plus contrôler ce PC. Il faudra l’associer à nouveau.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            key: const ValueKey('confirm-revoke'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Révoquer'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(agentControllerProvider.notifier).revoke(device.id);
  }
}
