import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import 'src/app/shell.dart';
import 'src/core/local_network.dart';
import 'src/core/share_intake.dart';
import 'src/modules/link/link_module.dart';
import 'src/core/providers.dart';
import 'src/pairing/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProviderScope(child: PegasusApp()));
}

/// Navigateur racine : ouvre l'écran « Ouvrir un lien » sur un partage.
final rootNavigatorKey = GlobalKey<NavigatorState>();

class PegasusApp extends StatelessWidget {
  const PegasusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Pegasus',
      debugShowCheckedModeBanner: false,
      theme: PegasusTheme.build(),
      home: const _NetworkRecheck(child: RootGate()),
    );
  }
}

/// Aiguillage : association d'un PC au premier lancement, sinon l'app.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Autorisation « réseau local » demandée dès l'ouverture (iOS).
    ref.watch(localNetworkProvider);
    // Démarre la connexion dès qu'un PC est associé.
    ref.watch(linkStateProvider);
    final pc = ref.watch(pairedPcProvider);
    return switch (pc) {
      AsyncData(value: null) => const OnboardingScreen(),
      AsyncData() => const AppShell(),
      _ => const Scaffold(body: Center(child: PegasusLogo(size: 96))),
    };
  }
}

/// Revérifie l'autorisation réseau au retour dans l'app (ex. depuis les Réglages).
class _NetworkRecheck extends ConsumerStatefulWidget {
  const _NetworkRecheck({required this.child});
  final Widget child;

  @override
  ConsumerState<_NetworkRecheck> createState() => _NetworkRecheckState();
}

class _NetworkRecheckState extends ConsumerState<_NetworkRecheck> {
  StreamSubscription<String>? _links;

  /// Lien partagé vers Pegasus : écran « Ouvrir un lien » prérempli
  /// (s'il y a un PC associé).
  void _onIncomingUrl(String url) {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    if (ref.read(pairedPcProvider).value == null) {
      ScaffoldMessenger.maybeOf(nav.context)?.showSnackBar(
        const SnackBar(content: Text('Associez d’abord un PC pour y ouvrir ce lien.')),
      );
      return;
    }
    nav.push(MaterialPageRoute<void>(builder: (_) => LinkScreen(initialUrl: url)));
  }

  late final AppLifecycleListener _listener = AppLifecycleListener(onResume: () {
    if (ref.read(localNetworkProvider) != LocalNetworkAccess.granted) {
      ref.read(localNetworkProvider.notifier).check();
    }
  });

  @override
  void initState() {
    super.initState();
    _listener;
    _links = ref.read(incomingLinksProvider).urls.listen(_onIncomingUrl);
  }

  @override
  void dispose() {
    _links?.cancel();
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
