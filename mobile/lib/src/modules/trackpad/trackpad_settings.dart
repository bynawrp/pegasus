import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'trackpad_engine.dart';

const _key = 'trackpad.speed';

/// Vitesse du trackpad choisie par l'utilisateur (× la vitesse de base),
/// enregistrée sur le téléphone.
final trackpadSpeedProvider = NotifierProvider<TrackpadSpeed, double>(TrackpadSpeed.new);

class TrackpadSpeed extends Notifier<double> {
  static const min = 0.5;
  static const max = 2.5;

  @override
  double build() {
    SharedPreferences.getInstance().then((p) {
      final saved = p.getDouble(_key);
      if (saved != null && ref.mounted) state = saved.clamp(min, max);
    });
    return 1.0;
  }

  Future<void> set(double value) async {
    state = value.clamp(min, max);
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_key, state);
  }
}

/// Réglages des gestes pour une vitesse donnée.
TrackpadSettings trackpadSettingsFor(double speed) =>
    TrackpadSettings(sensitivity: const TrackpadSettings().sensitivity * speed);
