# IHM mobile — décision

> Issue : #38 · Date : 2026-11-11

## Structure retenue : Hub personnalisable (proposition 2)

Raison principale : la **personnalisation des modules**. Chaque utilisateur compose son accueil avec les modules qu'il utilise.

Maquettes interactives :
- Proposition retenue + alternatives : https://claude.ai/artifact/2fwEmKoydtZneDeyUPp2L2
- Première exploration (MVP seul) : https://claude.ai/artifact/TT2SdboCou56J3UDSQNn5u

## Principes

1. **Zéro overflow** : aucun écran ne défile (ni verticalement ni horizontalement). Chaque module est conçu pour tenir dans la hauteur disponible ; les listes longues deviennent des grilles ou des sous-écrans.
2. **Architecture en modules** : une fonctionnalité = un module (`id`, catégorie, palier, écran, widget). Ajouter une feature = ajouter un module au registre, sans toucher à la navigation.
3. **Accès direct au plus fréquent** : trackpad, clavier, lecture et alimentation sont épinglables en widgets.

## Navigation

| Zone | Rôle |
|---|---|
| **Accueil** | Grille de widgets personnalisable (mode « Modifier ») + barre de recherche |
| **Modules** | Catalogue compact par catégorie, avec recherche et palier de chaque module |
| **Mes PC** | Choix du PC, appairage, accès distant |
| Écran module | Plein écran avec retour, bouton « Épingler à l'accueil » |

## Registre des modules

| Catégorie | Modules |
|---|---|
| Contrôle | Trackpad (MVP), Clavier (MVP), Manette (V3) |
| Médias | Lecture (MVP), Mixeur audio (V2) |
| Système | Alimentation (MVP), Surveillance (V2), Écran (V2) |
| Applications | Favoris (MVP), Fenêtres (V2), Processus (V2) |
| Fichiers | Transferts (V2), Presse-papiers (V2) |
| Automatisation | Macros (V2), Intégrations (V3), Notifications (V3) |
| Appareils | Mes PC (V2), Réglages (MVP) |
| Idées | Commandes vocales, mode présentation, profils, planificateur, montre, RGB, accès invité, plugins |

## Style

- Thème sombre par défaut, accent bleu `#8AB4FF`, fond `#0D1017`, surfaces `#161B24`
- Typo : Space Grotesk (titres), Inter (texte)
- Zones tactiles ≥ 44 px, confirmation avant éteindre/redémarrer

## Accueil : grille de widgets (inspirée de l'écran d'accueil iOS)

### Pages
- L'accueil est composé de **plusieurs pages** qu'on fait glisser horizontalement (pagination, jamais de défilement continu).
- Indicateur de pages (points) au-dessus de la barre de navigation.
- Une nouvelle page est créée quand on ajoute un widget et que la page courante est pleine ; une page vide est supprimée.

### Grille fixe
- Chaque page a un **nombre de places fixe** : grille de **4 colonnes × 6 rangées** (24 cases).
- Les widgets s'alignent sur la grille et se replacent automatiquement (pas de chevauchement, pas de case partielle).

### Tailles de widgets (au choix)
| Taille | Cases | Exemples |
|---|---|---|
| Petit | 1×1 | Action unique : verrouiller, lancer une app, une macro |
| Moyen carré | 2×2 | Lecture compacte, stats, groupe d'actions |
| Large | 4×2 | Lecture complète, rangée de macros, mixeur |
| Grand | 4×4 | Trackpad, clavier |

Chaque module déclare les tailles qu'il supporte et sa taille par défaut. L'utilisateur choisit la taille lors de l'ajout et peut la changer ensuite.

### Mode édition
- Appui long sur un widget ou bouton « Modifier » → les widgets tremblent.
- Glisser pour déplacer (y compris vers une autre page en atteignant le bord).
- Bouton « − » pour retirer, « + » pour ouvrir la galerie de widgets (choix du module puis de la taille).
- « Terminé » pour quitter le mode édition.

### Accueil par défaut (premier lancement, provisoire)
Les modules du MVP : trackpad, clavier, lecture, alimentation rapide, applications favorites.
