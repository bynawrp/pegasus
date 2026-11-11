# ADR 0001 — Stack de l'agent Windows

- **Statut** : accepté
- **Date** : 2026-11-11
- **Issue** : #3

## Contexte

L'agent PC doit :
- afficher une vraie fenêtre (structure C : barre latérale, 6 sections), une icône dans la zone de notification et des notifications Windows ;
- appeler des API système : simulation souris/clavier, audio, média en cours, alimentation, plus tard manette virtuelle (ViGEm), processus, luminosité ;
- exposer un serveur WebSocket chiffré sur le réseau local, découvrable en mDNS ;
- parler le même protocole que l'app mobile Flutter ;
- pouvoir être porté sur macOS/Linux plus tard (#1).

Options étudiées : Flutter desktop (Dart), C# / .NET 8, Rust + Tauri.

## Décision

**Flutter desktop (Dart)** pour l'agent, dans un monorepo partagé avec l'app mobile :

```
pegasus/
├── mobile/                 app Flutter (Android / iOS)
├── agent/                  agent Flutter desktop (Windows)
└── packages/
    ├── pegasus_protocol/   messages, versionnage, sécurité (partagé)
    └── pegasus_ui/         thème et composants communs (partagé)
```

Accès système :
1. `package:win32` (FFI) pour les API Win32 classiques (SendInput, alimentation, processus…) ;
2. un **plugin Flutter Windows en C++** dans l'agent pour ce que Dart couvre mal (WinRT : média en cours / SMTC, notifications, Core Audio si nécessaire, ViGEm).

Le code spécifique à Windows est isolé derrière des interfaces Dart (une implémentation par OS), pour préparer #1.

## Conséquences

- ✅ Un seul langage, un seul design system et un seul registre de modules pour mobile et desktop.
- ✅ Protocole défini une fois dans `pegasus_protocol`, utilisé des deux côtés.
- ✅ Portabilité macOS/Linux facilitée (Flutter desktop y tourne déjà).
- ⚠️ Une partie des fonctions Windows demande du C++ (plugin natif).
- ⚠️ Binaire plus lourd (~20-30 Mo) qu'une solution Rust.
- ⚠️ Fonctionnement en arrière-plan à gérer côté app (masquer la fenêtre dans la zone de notification au lieu de quitter).
