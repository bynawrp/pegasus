# Architecture du code

> Issues : #2, #3 · Décisions liées : [ADR 0001](adr/0001-stack-agent.md), [protocole](protocol.md), [design mobile](design/mobile.md), [design desktop](design/desktop.md)

## Monorepo (workspace Dart)

```
pegasus/
├── pubspec.yaml              workspace (une seule résolution de dépendances)
├── mobile/                   app Flutter Android / iOS
├── agent/                    agent Flutter desktop (Windows)
└── packages/
    ├── pegasus_protocol/     protocole v1 : enveloppe, codes, modules (Dart pur, testé)
    └── pegasus_ui/           palette, thème, composants communs
```

Commandes (à la racine) :

| Action | Commande |
|---|---|
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

## Qualité

- Lints : `flutter_lints` (apps, `pegasus_ui`) et `lints` (`pegasus_protocol`).
- `flutter analyze` doit passer sans avertissement avant chaque commit.
