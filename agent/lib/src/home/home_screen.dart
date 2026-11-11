import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_protocol/pegasus_protocol.dart';
import 'package:pegasus_ui/pegasus_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/format.dart';
import '../core/agent_controller.dart';

/// Accueil : état · association · appareils connectés · activité récente.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agentControllerProvider);
    const gap = 16.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ACCUEIL', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: gap),
        Expanded(
          flex: 5,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 4, child: _StatusPanel(state: state)),
              const SizedBox(width: gap),
              Expanded(flex: 6, child: _PairingPanel(state: state)),
            ],
          ),
        ),
        const SizedBox(height: gap),
        Expanded(
          flex: 4,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 4, child: _ConnectedPanel(state: state)),
              const SizedBox(width: gap),
              Expanded(flex: 6, child: _ActivityPanel(state: state)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Liste de lignes de hauteur fixe : n'affiche que celles qui tiennent.
class FittedRows extends StatelessWidget {
  const FittedRows({super.key, required this.count, required this.rowHeight, required this.builder, this.empty});

  final int count;
  final double rowHeight;
  final Widget Function(BuildContext, int) builder;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    if (count == 0 && empty != null) return Center(child: empty);
    return LayoutBuilder(builder: (context, box) {
      final fit = (box.maxHeight / rowHeight).floor().clamp(0, count);
      return Column(
        children: [
          for (var i = 0; i < fit; i++) SizedBox(height: rowHeight, child: builder(context, i)),
        ],
      );
    });
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.mono = false});
  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        SizedBox(width: 96, child: Text(label, style: text.bodySmall, maxLines: 1)),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono
                ? TextStyle(fontFamily: PegasusFonts.mono, package: PegasusFonts.package, fontSize: 13, color: c.text)
                : text.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.state});
  final AgentViewState state;

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    final (color, label) = switch (state.status) {
      AgentStatus.starting => (c.textMuted, 'DÉMARRAGE'),
      AgentStatus.error => (c.danger, 'ERREUR'),
      AgentStatus.running when state.paused => (c.warning, 'EN PAUSE'),
      AgentStatus.running => (c.success, 'ACTIF'),
    };
    final rows = <Widget>[
      _InfoRow('Adresse', state.primaryAddress == null ? '—' : '${state.primaryAddress}:${state.port}', mono: true),
      _InfoRow('PC', state.agentName),
      const _InfoRow('Version', 'agent $agentVersion · protocole v$protocolVersion'),
      const _InfoRow('Chiffrement', 'TLS · ECDSA P-256'),
      _InfoRow('Empreinte', PegasusCrypto.shortFingerprint(state.fingerprint), mono: true),
    ];
    return PegasusPanel(
      title: 'État',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StatusDot(color: color, size: 12),
              const SizedBox(width: 10),
              Text(label, style: text.headlineSmall?.copyWith(color: color)),
            ],
          ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(state.error!, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: c.danger)),
            ),
          const SizedBox(height: 10),
          Expanded(child: FittedRows(count: rows.length, rowHeight: 26, builder: (_, i) => rows[i])),
        ],
      ),
    );
  }
}

class _PairingPanel extends ConsumerStatefulWidget {
  const _PairingPanel({required this.state});
  final AgentViewState state;

  @override
  ConsumerState<_PairingPanel> createState() => _PairingPanelState();
}

class _PairingPanelState extends ConsumerState<_PairingPanel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    final invite = state.invite;
    final pairing = state.pairing;
    final renew = FilledButton.icon(
      key: const ValueKey('renew-pairing'),
      onPressed: state.status == AgentStatus.running
          ? () => ref.read(agentControllerProvider.notifier).renewPairing()
          : null,
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: const Text('Nouveau code'),
    );

    Widget body;
    if (state.status != AgentStatus.running) {
      body = Center(child: Text('Agent indisponible', style: text.bodyMedium));
    } else if (state.primaryAddress == null) {
      body = _Message(
        icon: Icons.wifi_off_rounded,
        text: 'Aucun réseau local détecté. Connectez le PC au même réseau que le téléphone.',
        action: OutlinedButton(
          onPressed: () => ref.read(agentControllerProvider.notifier).refreshAddresses(),
          child: const Text('Réessayer'),
        ),
      );
    } else if (invite == null || pairing == null) {
      body = _Message(
        icon: state.pairingLocked ? Icons.lock_outline_rounded : Icons.qr_code_2_rounded,
        text: state.pairingLocked
            ? 'Trop d’essais ratés : le code a été invalidé.'
            : 'Le code a expiré ou a déjà servi.',
        action: renew,
      );
    } else {
      final left = pairing.expiresAt.difference(DateTime.now());
      body = LayoutBuilder(builder: (context, box) {
        final qrSize = (box.maxHeight).clamp(0.0, box.maxWidth * 0.48);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              key: const ValueKey('pairing-qr'),
              width: qrSize,
              height: qrSize,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(PegasusRadii.control)),
              child: QrImageView(data: invite.toString(), padding: EdgeInsets.zero),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Scannez avec l’app Pegasus', style: text.bodyMedium),
                    const SizedBox(height: 14),
                    Text('CODE MANUEL', style: text.labelSmall),
                    Text(
                      formatCode(pairing.code),
                      key: const ValueKey('pairing-code'),
                      style: TextStyle(fontFamily: PegasusFonts.mono, package: PegasusFonts.package,
                          fontSize: 30, fontWeight: FontWeight.w700, color: c.accent2, letterSpacing: 2),
                    ),
                    const SizedBox(height: 6),
                    Text('${state.primaryAddress}:${state.port}', style: text.bodySmall),
                    Text('Empreinte ${PegasusCrypto.shortFingerprint(state.fingerprint)}', style: text.bodySmall),
                    Text('Expire dans ${formatCountdown(left)}', style: text.bodySmall),
                    const SizedBox(height: 12),
                    renew,
                  ],
                ),
              ),
            ),
          ],
        );
      });
    }

    return PegasusPanel(title: 'Associer un téléphone', child: body);
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 36, color: c.textMuted),
              const SizedBox(height: 10),
              Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              if (action != null) ...[const SizedBox(height: 12), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectedPanel extends StatelessWidget {
  const _ConnectedPanel({required this.state});
  final AgentViewState state;

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    final connected = state.devices.where((d) => state.connected.contains(d.id)).toList();
    return PegasusPanel(
      title: 'Appareils connectés',
      child: FittedRows(
        count: connected.length,
        rowHeight: 36,
        empty: Text('Aucun appareil connecté', style: Theme.of(context).textTheme.bodySmall),
        builder: (context, i) => Row(
          children: [
            Icon(Icons.smartphone_rounded, size: 18, color: c.accent2),
            const SizedBox(width: 10),
            Expanded(child: Text(connected[i].name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            StatusDot(color: c.success, size: 8),
          ],
        ),
      ),
    );
  }
}

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({required this.state});
  final AgentViewState state;

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    return PegasusPanel(
      title: 'Activité récente',
      child: FittedRows(
        count: state.activity.length,
        rowHeight: 28,
        empty: Text('Rien pour l’instant', style: text.bodySmall),
        builder: (context, i) {
          final e = state.activity[i];
          return Row(
            children: [
              Text(formatTime(e.time),
                  style: TextStyle(fontFamily: PegasusFonts.mono, package: PegasusFonts.package, fontSize: 12, color: c.textMuted)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(e.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(color: e.ok ? c.text : c.danger)),
              ),
            ],
          );
        },
      ),
    );
  }
}
