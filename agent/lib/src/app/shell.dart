import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../core/agent_controller.dart';
import '../devices/devices_screen.dart';
import '../favorites/favorites_screen.dart';
import '../home/home_screen.dart';

enum AgentSection {
  home('Accueil', Icons.space_dashboard_outlined),
  devices('Appareils', Icons.smartphone_outlined),
  favorites('Favoris', Icons.apps_rounded);

  const AgentSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

final agentSectionProvider = NotifierProvider<_SectionNotifier, AgentSection>(_SectionNotifier.new);

class _SectionNotifier extends Notifier<AgentSection> {
  @override
  AgentSection build() => AgentSection.home;
  void select(AgentSection s) => state = s;
}

/// Fenêtre principale : barre latérale fixe + contenu (structure C).
class AgentShell extends ConsumerWidget {
  const AgentShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(agentSectionProvider);
    return Scaffold(
      body: Row(
        children: [
          const _Sidebar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: switch (section) {
                AgentSection.home => const HomeScreen(),
                AgentSection.devices => const DevicesScreen(),
                AgentSection.favorites => const FavoritesScreen(),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    final state = ref.watch(agentControllerProvider);
    final section = ref.watch(agentSectionProvider);

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const PegasusLogo(size: 34),
              const SizedBox(width: 10),
              Text('PEGASUS', style: text.headlineSmall?.copyWith(letterSpacing: 2)),
            ],
          ),
          const SizedBox(height: 28),
          for (final s in AgentSection.values)
            _NavItem(
              section: s,
              selected: s == section,
              badge: s == AgentSection.devices && state.connected.isNotEmpty
                  ? '${state.connected.length}'
                  : null,
              onTap: () => ref.read(agentSectionProvider.notifier).select(s),
            ),
          const Spacer(),
          _StatusLine(state: state),
          const SizedBox(height: 12),
          _PauseButton(state: state),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.section, required this.selected, required this.onTap, this.badge});

  final AgentSection section;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    final color = selected ? c.accent : c.textMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? c.accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(PegasusRadii.control),
        child: InkWell(
          key: ValueKey('nav-${section.name}'),
          borderRadius: BorderRadius.circular(PegasusRadii.control),
          onTap: onTap,
          child: SizedBox(
            height: PegasusSizes.minTouch,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(section.icon, size: 20, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(color: selected ? c.text : c.textMuted),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: c.accent2, borderRadius: BorderRadius.circular(10)),
                    child: Text(badge!, style: TextStyle(color: c.background, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.state});
  final AgentViewState state;

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    final (color, label) = switch (state.status) {
      AgentStatus.starting => (c.textMuted, 'Démarrage…'),
      AgentStatus.error => (c.danger, 'Erreur'),
      AgentStatus.running when state.paused => (c.warning, 'En pause'),
      AgentStatus.running => (c.success, 'Actif'),
    };
    return Row(
      children: [
        StatusDot(color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, key: const ValueKey('agent-status'), style: Theme.of(context).textTheme.labelLarge),
        ),
      ],
    );
  }
}

class _PauseButton extends ConsumerWidget {
  const _PauseButton({required this.state});
  final AgentViewState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = state.status == AgentStatus.running;
    final controller = ref.read(agentControllerProvider.notifier);
    return state.paused
        ? FilledButton.icon(
            key: const ValueKey('resume'),
            onPressed: running ? () => controller.setPaused(false) : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Reprendre', maxLines: 1),
          )
        : OutlinedButton.icon(
            key: const ValueKey('pause'),
            onPressed: running ? () => controller.setPaused(true) : null,
            icon: const Icon(Icons.pause_rounded),
            label: const Text('Mettre en pause', maxLines: 1),
          );
  }
}
