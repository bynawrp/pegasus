import 'dart:async';

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

final mediaModule = PegasusModule(
  id: 'media',
  name: 'Lecture',
  icon: Icons.play_circle_outline_rounded,
  category: ModuleCategory.media,
  tier: ModuleTier.mvp,
  permission: 'media',
  sizes: const [WidgetSize.small, WidgetSize.medium, WidgetSize.wide],
  defaultSize: WidgetSize.wide,
  screen: (_) => const MediaScreen(),
  widget: (context, size) => MediaPad(compact: size == WidgetSize.medium),
);

/// Volume du PC : lu à la connexion, tenu à jour par `audio.changed`
/// (molette du PC, autre téléphone…), réglé depuis le curseur.
final audioProvider = NotifierProvider<AudioNotifier, AudioState?>(AudioNotifier.new);

class AudioNotifier extends Notifier<AudioState?> {
  Timer? _throttle;
  int? _pendingVolume;
  DateTime _localUntil = DateTime(0);

  @override
  AudioState? build() {
    final link = ref.watch(linkStateProvider);
    final remote = ref.read(remoteSenderProvider);
    ref.onDispose(() => _throttle?.cancel());
    if (!link.isConnected || link.info?.modules['media'] == false) return null;
    final sub = remote.events.where((e) => e.op == 'audio.changed').listen((e) {
      // Pendant qu'on fait glisser le curseur, on ne le fait pas sauter.
      if (DateTime.now().isBefore(_localUntil)) return;
      state = AudioState.fromJson(e.data);
    });
    ref.onDispose(sub.cancel);
    Future.microtask(refresh);
    return null;
  }

  Future<void> refresh() async {
    try {
      final data = await ref.read(remoteSenderProvider).request('audio.get', const {});
      if (ref.mounted) state = AudioState.fromJson(data);
    } catch (_) {}
  }

  /// Curseur : affichage immédiat, envoi au plus toutes les 120 ms.
  void setVolume(int volume) {
    final current = state;
    if (current == null) return;
    _localUntil = DateTime.now().add(const Duration(milliseconds: 600));
    state = AudioState(volume: volume, muted: current.muted);
    _pendingVolume = volume;
    _throttle ??= Timer(const Duration(milliseconds: 120), _flush);
  }

  Future<void> _flush() async {
    _throttle = null;
    final v = _pendingVolume;
    _pendingVolume = null;
    if (v == null) return;
    try {
      await ref.read(remoteSenderProvider).request('audio.set', {'volume': v});
    } catch (_) {}
  }

  Future<void> toggleMute() async {
    final current = state;
    if (current == null) return;
    state = AudioState(volume: current.volume, muted: !current.muted);
    try {
      final data = await ref.read(remoteSenderProvider).request('audio.set', {'muted': !current.muted});
      if (ref.mounted) state = AudioState.fromJson(data);
    } catch (_) {
      if (ref.mounted) state = current;
    }
  }
}

/// Lecture / pause, précédent, suivant, muet et volume.
class MediaPad extends ConsumerWidget {
  const MediaPad({super.key, this.compact = false, this.large = false});

  /// Widget 2×2 : sans curseur.
  final bool compact;

  /// Écran plein : boutons plus grands.
  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pegasus;
    final audio = ref.watch(audioProvider);
    final remote = ref.read(remoteSenderProvider);
    final iconSize = large ? 40.0 : 26.0;

    Widget transport(String key, IconData icon, MediaCommand command, {bool primary = false}) => Expanded(
          child: Material(
            color: primary ? c.accent.withValues(alpha: 0.18) : c.surfaceHigh,
            borderRadius: BorderRadius.circular(PegasusRadii.control),
            child: InkWell(
              key: ValueKey(key),
              borderRadius: BorderRadius.circular(PegasusRadii.control),
              onTap: () => runAction(context, () => remote.request(command.op, const {})),
              child: Center(child: Icon(icon, size: iconSize, color: primary ? c.accent : c.text)),
            ),
          ),
        );

    final muteButton = Material(
      color: c.surfaceHigh,
      borderRadius: BorderRadius.circular(PegasusRadii.control),
      child: InkWell(
        key: const ValueKey('media-mute'),
        borderRadius: BorderRadius.circular(PegasusRadii.control),
        onTap: audio == null ? null : () => ref.read(audioProvider.notifier).toggleMute(),
        child: SizedBox(
          width: large ? 64 : 44,
          child: Center(
            child: Icon(
              audio?.muted == true ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              size: iconSize * 0.85,
              color: audio?.muted == true ? c.warning : c.text,
            ),
          ),
        ),
      ),
    );

    return ModuleGate(
      permission: 'media',
      compact: !large,
      child: LayoutBuilder(builder: (context, box) {
        final gap = large ? 12.0 : 6.0;
        final controlsRow = Row(
          children: [
            transport('media-previous', Icons.skip_previous_rounded, MediaCommand.previous),
            SizedBox(width: gap),
            transport('media-play', Icons.play_arrow_rounded, MediaCommand.playPause, primary: true),
            SizedBox(width: gap),
            transport('media-next', Icons.skip_next_rounded, MediaCommand.next),
            if (compact) ...[SizedBox(width: gap), muteButton],
          ],
        );
        if (compact) return controlsRow;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: controlsRow),
            SizedBox(height: gap),
            SizedBox(
              height: large ? 56 : (box.maxHeight / 2 - gap).clamp(28.0, 44.0),
              child: Row(
                children: [
                  muteButton,
                  Expanded(
                    child: Slider(
                      key: const ValueKey('media-volume'),
                      min: 0,
                      max: 100,
                      value: (audio?.volume ?? 0).toDouble(),
                      onChanged: audio == null ? null : (v) => ref.read(audioProvider.notifier).setVolume(v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 34,
                    child: Text(
                      audio == null ? '–' : '${audio.volume}',
                      key: const ValueKey('media-volume-label'),
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontFamily: PegasusFonts.mono, package: PegasusFonts.package, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}

class MediaScreen extends StatelessWidget {
  const MediaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LECTURE')),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Center(
            child: SizedBox(height: 240, child: MediaPad(large: true)),
          ),
        ),
      ),
    );
  }
}
