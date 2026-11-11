# IHM desktop (agent Windows) — décision

> Issue : #39 · Date : 2026-11-11

## Structure retenue : application complète avec barre latérale (proposition C)

Maquette interactive (A, B et C) : https://claude.ai/artifact/LMG68poXEUNFT3Nd2C8Cz8

## Principes

1. **Zéro overflow** : aucune vue ne défile. Les listes longues sont paginées (journal) ou limitées.
2. **Toujours actif en arrière-plan** : fermer la fenêtre ne quitte pas Pegasus, l'agent reste dans la zone de notification de la barre des tâches. Quitter se fait explicitement.
3. **Cohérence avec le mobile** : même DA gaming / néon, mêmes palettes et typos ([da.md](da.md)), même registre de modules.

## Fenêtre principale

Barre latérale fixe + zone de contenu. Bouton « Mettre en pause / Reprendre le contrôle » en bas de la barre latérale.

| Section | Contenu |
|---|---|
| **Accueil** | 4 cartes : état (actif/pause, adresse, version, chiffrement, démarrage auto) · association (QR code + code manuel + nouveau code) · appareils connectés · activité récente |
| **Appareils** | Liste des appareils associés (état, date), renommer, révoquer, associer un nouvel appareil |
| **Autorisations** | Un interrupteur par module (souris & clavier, médias, alimentation, applications, fichiers, macros & scripts…). Un module désactivé apparaît grisé dans l'app mobile |
| **Favoris** | Applications proposées dans le module « Favoris » du mobile, ajout/suppression |
| **Journal** | Historique des commandes reçues, filtres (connexions, alimentation, médias…), pagination |
| **Réglages** | Démarrer avec Windows, notifications, confirmation sur le PC avant d'éteindre, mises à jour auto, port réseau, dossier de réception des fichiers, thème (système/sombre/clair) |

## Icône de la barre des tâches

- Pastille d'état sur l'icône : vert = actif, orange = en pause.
- Clic : ouvre/ramène la fenêtre principale.
- Clic droit (menu court) : associer un téléphone, pause/reprise, quitter.

## Notifications Windows

- Nouvel appareil connecté.
- Commande sensible reçue (alimentation, scripts) selon les réglages.

## Découpage par palier

- **MVP** : Accueil, Appareils (liste + révocation), Réglages de base (démarrage auto, port), icône + pause, QR d'association.
- **V2** : Autorisations par module, Favoris éditables, Journal complet, dossier de réception, thème.
