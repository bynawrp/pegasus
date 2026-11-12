import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_link/pegasus_link.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../modules/registry.dart';
import 'home_layout.dart';

const _key = 'home.layout';

/// Nombre de doigts posés sur un trackpad : tant qu'il y en a, les pages de
/// l'accueil ne défilent pas (le geste appartient au trackpad).
final homePagingLockProvider = NotifierProvider<HomePagingLock, int>(HomePagingLock.new);

class HomePagingLock extends Notifier<int> {
  @override
  int build() => 0;
  void hold() => state++;
  void release() => state = state > 0 ? state - 1 : 0;
}

/// Mise en page de l'accueil, enregistrée sur le téléphone.
final homeLayoutProvider = AsyncNotifierProvider<HomeLayoutNotifier, HomeLayout>(HomeLayoutNotifier.new);

class HomeLayoutNotifier extends AsyncNotifier<HomeLayout> {
  @override
  Future<HomeLayout> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        return HomeLayout.fromJson(jsonDecode(raw), knownModule: (id) => moduleById(id)?.available ?? false);
      } catch (_) {}
    }
    return defaultLayout();
  }

  static HomeLayout defaultLayout() {
    var layout = HomeLayout.empty;
    for (final (id, size) in defaultHomeModules) {
      layout = layout.add(newUuid(), id, size).$1;
    }
    return layout;
  }

  HomeLayout get _current => state.value ?? HomeLayout.empty;

  Future<void> _save(HomeLayout layout) async {
    state = AsyncData(layout);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(layout.toJson()));
  }

  /// Ajoute un widget ; renvoie la page où il a été posé.
  Future<int> add(String moduleId, WidgetSize size, {int preferredPage = 0}) async {
    final (layout, page) = _current.add(newUuid(), moduleId, size, preferredPage: preferredPage);
    await _save(layout);
    return page;
  }

  Future<void> remove(String id) => _save(_current.remove(id));

  Future<void> resize(String id, WidgetSize size) => _save(_current.resize(id, size));

  /// Enregistre une mise en page issue d'un glisser-déposer (aperçu validé).
  Future<void> commit(HomeLayout layout) => _save(layout);

  Future<void> reset() => _save(defaultLayout());
}
