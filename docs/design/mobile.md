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

- DA gaming / néon : palette Néon (magenta + cyan) en thème sombre par défaut, 5 autres palettes et le mode clair au choix dans les réglages — voir [da.md](da.md)
- Typo : Barlow Condensed (titres), Barlow (texte), JetBrains Mono (chiffres)
- Zones tactiles ≥ 44 px, confirmation avant éteindre/redémarrer

## Accueil : grille de widgets (inspirée de l'écran d'accueil iOS)

### Pages
- L'accueil est composé de **plusieurs pages** qu'on fait glisser horizontalement (pagination, jamais de défilement continu).
- Indicateur de pages (points) au-dessus de la barre de navigation.
- Une nouvelle page est créée quand on ajoute un widget et que la page courante est pleine ; une page vide est supprimée.

### Grille fixe, rangement automatique (comme iOS)
- Chaque page a un **nombre de places fixe** : grille de **4 colonnes × 6 rangées** (24 cases).
- Une page est une **liste ordonnée** de widgets, rangés automatiquement ligne par ligne (chaque widget à la première place libre) : pas de chevauchement, pas de case partielle.
- Glisser un widget change sa place dans l'ordre : les autres se décalent **en direct pendant le glisser** ; ce qui ne tient plus passe en tête de la page suivante. Retirer un widget fait remonter les suivants.

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
Implémenté (paquet 2) : trackpad 4×4 + clavier 4×2 (page 1 pleine) ; les autres modules du MVP rejoindront l'accueil quand ils seront disponibles.

### Gestes du trackpad
| Geste | Action sur le PC |
|---|---|
| 1 doigt qui glisse | Déplace le pointeur : gain ×2,2 au ralenti, jusqu'à ×5,5 quand le doigt va vite (réglage « Vitesse » ×0,5 à ×2,5 dans l'écran trackpad) |
| Tap | Clic gauche (deux taps = double clic) |
| Tap à 2 doigts | Clic droit |
| 2 doigts qui glissent | Défilement (sens naturel, vertical et horizontal) |
| Tap puis appui maintenu qui glisse | Glisser-déposer |
| Boutons (icônes de souris gauche / droite) | Appui = bouton enfoncé, relâche = relevé |
| Doigt posé sur le trackpad de l'accueil | Les pages de l'accueil ne défilent pas |

### Clavier
- Frappe en direct : chaque caractère part aussitôt ; corrections automatiques et modifications au milieu du texte rejouées (flèches + retour arrière + texte).
- Modificateurs Ctrl / Alt / Maj / Win à activer puis lettre ou touche = raccourci.
- Touches spéciales (Échap, Tab, flèches, Suppr, Entrée) et raccourcis (Alt+Tab, Copier, Coller, Annuler, Tout, Bureau, Win, Fermer).
