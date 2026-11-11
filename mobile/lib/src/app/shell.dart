import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_link/pegasus_link.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../core/providers.dart';
import '../home/home_screen.dart';
import '../modules/modules_screen.dart';
import '../pcs/my_pc_screen.dart';
import 'connection_banner.dart';

final shellTabProvider = NotifierProvider<_TabNotifier, int>(_TabNotifier.new);

class _TabNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void select(int i) => state = i;
}

/// Navigation principale : Accueil · Modules · Mes PC.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Reconnexion immédiate au retour au premier plan (spec §5).
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(linkStateProvider.notifier).reconnect(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(shellTabProvider);
    final link = ref.watch(linkStateProvider);
    final pc = ref.watch(pairedPcProvider).value;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConnectionBanner(state: link, pcName: pc?.agentName ?? ''),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: switch (tab) {
                  0 => const HomeScreen(),
                  1 => const ModulesScreen(),
                  _ => const MyPcScreen(),
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: ref.read(shellTabProvider.notifier).select,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
              key: ValueKey('tab-home'), icon: Icon(Icons.space_dashboard_outlined), label: 'Accueil'),
          NavigationDestination(
              key: ValueKey('tab-modules'), icon: Icon(Icons.grid_view_rounded), label: 'Modules'),
          NavigationDestination(
              key: ValueKey('tab-pc'), icon: Icon(Icons.computer_rounded), label: 'Mes PC'),
        ],
      ),
    );
  }
}

/// Libellé court d'un état de connexion.
String linkLabel(LinkState s) => switch (s.status) {
      LinkStatus.idle => 'Déconnecté',
      LinkStatus.connecting => 'Connexion…',
      LinkStatus.connected => s.info?.paused == true ? 'En pause sur le PC' : 'Connecté',
      LinkStatus.waiting => 'Nouvel essai dans ${(s.retryIn?.inSeconds ?? 0) + 1} s',
      LinkStatus.revoked => 'Accès révoqué par le PC',
      LinkStatus.unauthorized => 'Accès refusé par le PC',
      LinkStatus.untrusted => 'Certificat du PC inattendu',
      LinkStatus.replaced => 'Connecté depuis une autre session',
    };

Color linkColor(BuildContext context, LinkState s) {
  final c = context.pegasus;
  return switch (s.status) {
    LinkStatus.connected => s.info?.paused == true ? c.warning : c.success,
    LinkStatus.connecting || LinkStatus.waiting || LinkStatus.replaced => c.warning,
    LinkStatus.idle => c.textMuted,
    LinkStatus.revoked || LinkStatus.unauthorized || LinkStatus.untrusted => c.danger,
  };
}
