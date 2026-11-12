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

/// Un widget posé sur une page.
class Placement {
  const Placement({
    required this.id,
    required this.moduleId,
    required this.size,
    required this.col,
    required this.row,
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

  bool covers(int c, int r) => c >= col && c < col + size.cols && r >= row && r < row + size.rows;

  bool overlaps(Placement o) =>
      col < o.col + o.size.cols && o.col < col + size.cols && row < o.row + o.size.rows && o.row < row + size.rows;

  Map<String, Object?> toJson() => {'id': id, 'module': moduleId, 'size': size.name, 'col': col, 'row': row};

  static Placement? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final size = WidgetSize.parse(raw['size']);
    final id = raw['id'], module = raw['module'], col = raw['col'], row = raw['row'];
    if (size == null || id is! String || module is! String || col is! int || row is! int) return null;
    return Placement(id: id, moduleId: module, size: size, col: col, row: row);
  }

  @override
  String toString() => '$moduleId(${size.name}@$col,$row)';
}

/// Grille de l'accueil : pages de 4 × 6 cases fixes, sans chevauchement ni
/// case partielle (pur, testé).
class HomeLayout {
  const HomeLayout(this.pages);

  static const cols = 4;
  static const rows = 6;

  final List<List<Placement>> pages;

  int get pageCount => pages.length;
  Iterable<Placement> get all => pages.expand((p) => p);

  static const empty = HomeLayout([[]]);

  /// Vrai si [size] tient en ([col], [row]) de la page [page] (en ignorant [ignoreId]).
  bool fits(int page, WidgetSize size, int col, int row, {String? ignoreId}) {
    if (col < 0 || row < 0 || col + size.cols > cols || row + size.rows > rows) return false;
    if (page < 0 || page > pages.length) return false;
    if (page == pages.length) return true; // Nouvelle page vide.
    final probe = Placement(id: '', moduleId: '', size: size, col: col, row: row);
    return pages[page].every((p) => p.id == ignoreId || !p.overlaps(probe));
  }

  /// Première place libre sur [page] (lecture ligne par ligne).
  ({int col, int row})? freeSpot(int page, WidgetSize size, {String? ignoreId}) {
    for (var r = 0; r <= rows - size.rows; r++) {
      for (var c = 0; c <= cols - size.cols; c++) {
        if (fits(page, size, c, r, ignoreId: ignoreId)) return (col: c, row: r);
      }
    }
    return null;
  }

  /// Ajoute un widget : page [preferredPage] d'abord, puis les suivantes,
  /// puis une nouvelle page. Renvoie la mise en page et la page utilisée.
  (HomeLayout, int) add(String id, String moduleId, WidgetSize size, {int preferredPage = 0}) {
    final order = [
      for (var i = 0; i < pages.length; i++) (preferredPage + i) % pages.length,
    ];
    for (final page in order) {
      final spot = freeSpot(page, size);
      if (spot != null) {
        final placed = Placement(id: id, moduleId: moduleId, size: size, col: spot.col, row: spot.row);
        return (_withPage(page, [...pages[page], placed]), page);
      }
    }
    final placed = Placement(id: id, moduleId: moduleId, size: size, col: 0, row: 0);
    final emptyFirst = pages.length == 1 && pages.first.isEmpty;
    if (emptyFirst) return (HomeLayout([[placed]]), 0);
    return (HomeLayout([...pages, [placed]]), pages.length);
  }

  /// Retire un widget ; une page devenue vide disparaît (il reste toujours une page).
  HomeLayout remove(String id) => HomeLayout([
        for (final p in pages) [for (final w in p) if (w.id != id) w],
      ])._compact();

  /// Déplace un widget ; `null` si la place n'est pas libre.
  /// [page] peut valoir [pageCount] pour créer une nouvelle page.
  HomeLayout? move(String id, int page, int col, int row) {
    final w = find(id);
    if (w == null || !fits(page, w.$1.size, col, row, ignoreId: id)) return null;
    final moved = w.$1.copyWith(col: col, row: row);
    final without = [
      for (final p in pages) [for (final x in p) if (x.id != id) x],
    ];
    if (page == without.length) without.add([]);
    without[page] = [...without[page], moved];
    return HomeLayout(without)._compact();
  }

  /// Change la taille : même position si possible, sinon une autre place
  /// sur la même page, sinon une autre page.
  HomeLayout resize(String id, WidgetSize size) {
    final found = find(id);
    if (found == null) return this;
    final (w, page) = found;
    if (fits(page, size, w.col, w.row, ignoreId: id)) {
      return _replace(page, w.copyWith(size: size));
    }
    final spot = freeSpot(page, size, ignoreId: id);
    if (spot != null) return _replace(page, w.copyWith(size: size, col: spot.col, row: spot.row));
    return remove(id).add(id, w.moduleId, size, preferredPage: page).$1;
  }

  (Placement, int)? find(String id) {
    for (var i = 0; i < pages.length; i++) {
      for (final w in pages[i]) {
        if (w.id == id) return (w, i);
      }
    }
    return null;
  }

  HomeLayout _replace(int page, Placement w) =>
      _withPage(page, [for (final x in pages[page]) x.id == w.id ? w : x]);

  HomeLayout _withPage(int page, List<Placement> content) =>
      HomeLayout([for (var i = 0; i < pages.length; i++) i == page ? content : pages[i]]);

  HomeLayout _compact() {
    final kept = [for (final p in pages) if (p.isNotEmpty) p];
    return HomeLayout(kept.isEmpty ? [[]] : kept);
  }

  Map<String, Object?> toJson() => {
        'v': 1,
        'pages': [
          for (final p in pages) [for (final w in p) w.toJson()],
        ],
      };

  /// Relit une mise en page enregistrée : les entrées invalides, les modules
  /// inconnus et les chevauchements sont écartés (re-placés si possible).
  static HomeLayout fromJson(Object? raw, {required bool Function(String moduleId) knownModule}) {
    if (raw is! Map || raw['pages'] is! List) return empty;
    var layout = HomeLayout.empty;
    final rejected = <Placement>[];
    final seen = <String>{};
    final rawPages = raw['pages'] as List;
    for (var i = 0; i < rawPages.length; i++) {
      final page = rawPages[i];
      if (page is! List) continue;
      final target = layout.pages.length == 1 && layout.pages.first.isEmpty ? 0 : layout.pages.length;
      var placed = <Placement>[];
      for (final item in page) {
        final w = Placement.fromJson(item);
        if (w == null || !knownModule(w.moduleId) || !seen.add(w.id)) continue;
        final inBounds = w.col >= 0 && w.row >= 0 && w.col + w.size.cols <= cols && w.row + w.size.rows <= rows;
        if (inBounds && placed.every((p) => !p.overlaps(w))) {
          placed = [...placed, w];
        } else {
          rejected.add(w);
        }
      }
      if (placed.isEmpty) continue;
      layout = target == 0 ? HomeLayout([placed]) : HomeLayout([...layout.pages, placed]);
    }
    for (final w in rejected) {
      layout = layout.add(w.id, w.moduleId, w.size).$1;
    }
    return layout;
  }
}
