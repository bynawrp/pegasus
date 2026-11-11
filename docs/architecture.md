# Architecture du code

> Issues : #2, #3 · Décisions liées : [ADR 0001](adr/0001-stack-agent.md), [protocole](protocol.md), [design mobile](design/mobile.md), [design desktop](design/desktop.md)

## Monorepo (workspace Dart)

```
pegasus/
├── pubspec.yaml              workspace (une seule résolution de dépendances)
├── mobile/                   app Flutter Android / iOS
├── agent/                    agent Flutter desktop (Windows)
└── packages/
    ├── pegasus_protocol/     protocole v1 : enveloppe, codes, modules, appairage, HMAC (Dart pur)
    ├── pegasus_link/         connexion : serveur TLS de l'agent + client de l'app (Dart pur, testé de bout en bout)
    └── pegasus_ui/           palette, thème, composants communs, outils de test (testing.dart)
```

Commandes (à la racine) :

| Action | Commande |
|---|---|
| **Tout valider (analyse + tous les tests)** | `bash tool/validate.sh` (`--build` : + APK et agent Windows) |
| Installer les dépendances | `flutter pub get` |
| Analyse statique (tout le repo) | `flutter analyze` |
| Tests du protocole | `cd packages/pegasus_protocol && dart test` |
| Tests UI / apps | `cd <package> && flutter test` |
| APK de debug | `cd mobile && flutter build apk --debug` |
| Build iOS (sur Mac) | `cd mobile && flutter build ios --debug --no-codesign` |
| Agent Windows | `cd agent && flutter run -d windows` (requiert Visual Studio + « Desktop development with C++ ») |

## Gestion d'état : Riverpod

`flutter_riverpod` dans l'app et l'agent. L'application est enveloppée dans un `ProviderScope`.

Conventions :
- Un **provider par source de données** (connexion, état audio, liste des appareils…). Les widgets lisent les providers, ils ne parlent jamais directement au réseau ou à l'OS.
- Les flux temps réel (événements `evt` du protocole) sont exposés en `StreamProvider` / `Notifier`.
- Les dépendances système (réseau, stockage sécurisé, API Windows) sont injectées via des providers, remplaçables par des faux dans les tests.

## Organisation d'une app (`mobile/lib`, `agent/lib`)

```
lib/
├── main.dart                 point d'entrée, ProviderScope, thème
└── src/
    ├── app/                  routage, shell (navigation principale)
    ├── core/                 connexion, session, stockage, services transverses
    ├── modules/              un dossier par module du registre
    │   └── <module>/
    │       ├── <module>_module.dart     déclaration (id, catégorie, palier, tailles de widget)
    │       ├── <module>_providers.dart  état et actions (envoi des requêtes du protocole)
    │       ├── <module>_screen.dart     écran plein du module
    │       └── <module>_widget.dart     widget d'accueil (mobile)
    └── home/                 accueil : grille 4×6, pages, mode édition (mobile)
```

Côté agent, `src/platform/` contient les interfaces d'accès au système (entrée, audio, alimentation, apps) et leur implémentation Windows (`win32` FFI ou plugin C++), pour préparer la portabilité (#1).

## Registre de modules

Chaque fonctionnalité est un module (cf. `docs/design/mobile.md`). Ajouter une feature = ajouter un dossier dans `modules/` et l'inscrire dans le registre ; la navigation, le catalogue et la galerie de widgets le récupèrent automatiquement. Le préfixe des opérations du protocole (`power.*`…) correspond à l'interrupteur d'autorisation côté agent (`moduleForOp` dans `pegasus_protocol`).

## Connexion (`pegasus_link`)

- `AgentServer` : WebSocket TLS (certificat ECDSA P-256 de `AgentIdentity`), appairage (`PairingManager` : jeton + code, 5 min, 5 essais), authentification HMAC, pause, modules, limites de débit, journal (`events`). Les opérations des modules s'y branchent avec `onRequest(op, …)` / `onCommand(op, …)`.
- `PegasusClient` / `PegasusConnection` : connexion avec épinglage de l'empreinte, requêtes (10 s), commandes, évènements.
- `PegasusLink` : connexion maintenue côté app (reconnexion 1 → 30 s, états `revoked` / `unauthorized` / `untrusted` sans nouvel essai).
- Agent : identité et appareils dans `%APPDATA%/com.bynawrp/pegasus_agent/agent.json` ; clé privée et secrets chiffrés avec DPAPI.
- App : PC associé et secret dans le stockage sécurisé (Keychain / Keystore).

## Qualité

- Lints : `flutter_lints` (apps, `pegasus_ui`) et `lints` (`pegasus_protocol`).
- `flutter analyze` doit passer sans avertissement avant chaque commit.
- Développement par **paquets** d'issues : chaque paquet est livré avec ses tests et `tool/validate.sh` doit être entièrement vert (non-régression). La CI lance le même script.
- Tests obligatoires par type :
  - réseau / protocole : tests de bout en bout sur un vrai serveur TLS en local (`pegasus_link/test/e2e_test.dart`) ;
  - interface : tests « zéro overflow » sur plusieurs tailles (téléphones 320×568 → 430×932, fenêtre agent 960×600 → 1920×1080), texte agrandi ×1.3 et clavier ouvert, avec les vraies polices (`pegasus_ui/testing.dart`).
