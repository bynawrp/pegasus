/// Tailles de widget sur la grille de l'accueil (docs/design/mobile.md).
enum WidgetSize {
  small(1, 1, 'Petit'),
  medium(2, 2, 'Moyen'),
  wide(4, 2, 'Large'),
  large(4, 4, 'Grand');

  const WidgetSize(this.cols, this.rows, this.label);
  final int cols;
  final int rows;
  final String label;

  int get cells => cols * rows;

  static WidgetSize? parse(Object? v) => values.where((s) => s.name == v).firstOrNull;
}

/// Un widget posé sur une page (position calculée par la mise en page).
class Placement {
  const Placement({
    required this.id,
    required this.moduleId,
    required this.size,
    this.col = 0,
    this.row = 0,
  });

  /// Identifiant unique de l'instance (un module peut être posé plusieurs fois).
  final String id;
  final String moduleId;
  final WidgetSize size;
  final int col;
  final int row;

  Placement copyWith({WidgetSize? size, int? col, int? row}) => Placement(
        id: id,
        moduleId: moduleId,
        size: size ?? this.size,
        col: col ?? this.col,
        row: row ?? this.row,
      );

  bool overlaps(Placement o) =>
      col < o.col + o.size.cols && o.col < col + size.cols && row < o.row + o.size.rows && o.row < row + size.rows;

  Map<String, Object?> toJson() => {'id': id, 'module': moduleId, 'size': size.name};

  static Placement? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final size = WidgetSize.parse(raw['size']);
    final id = raw['id'], module = raw['module'];
    if (size == null || id is! String || module is! String) return null;
    // Anciennes sauvegardes (paquet 2 v1) : la position sert à retrouver l'ordre.
    final col = raw['col'] is int ? raw['col'] as int : 0;
    final row = raw['row'] is int ? raw['row'] as int : 0;
    return Placement(id: id, moduleId: module, size: size, col: col, row: row);
  }

  @override
  String toString() => '$moduleId(${size.name}@$col,$row)';
}

/// Accueil façon iOS : chaque page est une **liste ordonnée** de widgets,
/// rangés automatiquement sur une grille fixe de 4 × 6 cases (ligne par
/// ligne, chaque widget à la première place libre). Déplacer = changer
/// l'ordre ; les autres widgets se réorganisent, et ce qui ne tient plus
/// passe en tête de la page suivante (pur, testé).
class HomeLayout {
  HomeLayout._(this.pages);

  /// Range [pages] (ordre conservé) et calcule les positions.
  factory HomeLayout(List<List<Placement>> pages) => HomeLayout._(_pack(pages));

  static const cols = 4;
  static const rows = 6;

  final List<List<Placement>> pages;

  int get pageCount => pages.length;
  Iterable<Placement> get all => pages.expand((p) => p);

  static final empty = HomeLayout._(const [[]]);

  (Placement, int)? find(String id) {
    for (var i = 0; i < pages.length; i++) {
      for (final w in pages[i]) {
        if (w.id == id) return (w, i);
      }
    }
    return null;
  }

  /// Ajoute un widget à la fin de [preferredPage] (ou de la suivante si
  /// elle est pleine). Renvoie la mise en page et la page utilisée.
  (HomeLayout, int) add(String id, String moduleId, WidgetSize size, {int preferredPage = 0}) {
    final widget = Placement(id: id, moduleId: moduleId, size: size);
    var page = preferredPage.clamp(0, pages.length - 1);
    // Première page (à partir de la préférée) où le widget tient à la fin.
    while (page < pages.length) {
      final trial = HomeLayout([for (var i = 0; i < pages.length; i++) i == page ? [...pages[i], widget] : pages[i]]);
      if (trial.find(id)!.$2 == page && trial.pageCount == pageCount) return (trial, page);
      page++;
    }
    final grown = HomeLayout([...pages, [widget]]);
    return (grown, grown.find(id)!.$2);
  }

  /// Retire un widget ; les suivants remontent, une page vide disparaît.
  HomeLayout remove(String id) => HomeLayout([
        for (final p in pages) [for (final w in p) if (w.id != id) w],
      ]);

  /// Change la taille ; la page se réorganise.
  HomeLayout resize(String id, WidgetSize size) => HomeLayout([
        for (final p in pages) [for (final w in p) w.id == id ? w.copyWith(size: size) : w],
      ]);

  /// Place le widget [id] à la position [index] de l'ordre de la page [page]
  /// ([page] == [pageCount] : nouvelle page à la fin).
  HomeLayout moveTo(String id, int page, int index) {
    final found = find(id);
    if (found == null) return this;
    final lists = [
      for (final p in pages) [for (final w in p) if (w.id != id) w],
    ];
    if (page >= lists.length) lists.add([]);
    final target = lists[page.clamp(0, lists.length - 1)];
    target.insert(index.clamp(0, target.length), found.$1);
    return HomeLayout(lists);
  }

  /// Glisser-déposer : meilleure position dans l'ordre de [page] pour que
  /// [id] arrive au plus près de la case ([col], [row]). Renvoie la mise en
  /// page résultante (aperçu en direct pendant le glisser).
  HomeLayout dropAt(String id, int page, int col, int row) {
    final found = find(id);
    if (found == null) return this;
    final others = page < pages.length ? pages[page].where((w) => w.id != id).length : 0;
    HomeLayout? best;
    var bestScore = double.infinity;
    for (var i = 0; i <= others; i++) {
      final trial = moveTo(id, page, i);
      final (w, p) = trial.find(id)!;
      // Un widget qui part sur une autre page est un mauvais choix.
      final score = (p == page.clamp(0, trial.pageCount - 1) ? 0 : 1000) +
          ((w.row - row) * (w.row - row) * 1.0 + (w.col - col) * (w.col - col)) +
          i * 0.001; // À égalité, la position la plus tôt.
      if (score < bestScore) {
        bestScore = score;
        best = trial;
      }
    }
    return best ?? this;
  }

  Map<String, Object?> toJson() => {
        'v': 2,
        'pages': [
          for (final p in pages) [for (final w in p) w.toJson()],
        ],
      };

  /// Relit une mise en page enregistrée : entrées invalides, modules
  /// inconnus et doublons écartés ; l'ordre est conservé (ou retrouvé à
  /// partir des positions des anciennes sauvegardes).
  static HomeLayout fromJson(Object? raw, {required bool Function(String moduleId) knownModule}) {
    if (raw is! Map || raw['pages'] is! List) return empty;
    final seen = <String>{};
    final lists = <List<Placement>>[];
    for (final page in raw['pages'] as List) {
      if (page is! List) continue;
      final items = <Placement>[];
      for (final item in page) {
        final w = Placement.fromJson(item);
        if (w != null && knownModule(w.moduleId) && seen.add(w.id)) items.add(w);
      }
      if (raw['v'] != 2) {
        items.sort((a, b) => a.row != b.row ? a.row - b.row : a.col - b.col);
      }
      if (items.isNotEmpty) lists.add(items);
    }
    return HomeLayout(lists);
  }

  /// Rangement : chaque widget à la première place libre de sa page, dans
  /// l'ordre ; ce qui ne tient pas passe en tête de la page suivante.
  static List<List<Placement>> _pack(List<List<Placement>> input) {
    final out = <List<Placement>>[];
    var carry = <Placement>[];
    var i = 0;
    while (i < input.length || carry.isNotEmpty) {
      final queue = [...carry, if (i < input.length) ...input[i]];
      i++;
      carry = [];
      final grid = List.generate(rows, (_) => List.filled(cols, false));
      final placed = <Placement>[];
      for (final w in queue) {
        final spot = _firstFit(grid, w.size);
        if (spot == null) {
          carry.add(w);
          continue;
        }
        for (var r = spot.$2; r < spot.$2 + w.size.rows; r++) {
          for (var c = spot.$1; c < spot.$1 + w.size.cols; c++) {
            grid[r][c] = true;
          }
        }
        placed.add(w.copyWith(col: spot.$1, row: spot.$2));
      }
      if (placed.isNotEmpty) out.add(placed);
    }
    return out.isEmpty ? [[]] : out;
  }

  static (int, int)? _firstFit(List<List<bool>> grid, WidgetSize size) {
    for (var r = 0; r <= rows - size.rows; r++) {
      for (var c = 0; c <= cols - size.cols; c++) {
        var free = true;
        for (var rr = r; rr < r + size.rows && free; rr++) {
          for (var cc = c; cc < c + size.cols && free; cc++) {
            if (grid[rr][cc]) free = false;
          }
        }
        if (free) return (c, r);
      }
    }
    return null;
  }
}
