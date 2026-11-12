import 'package:flutter_test/flutter_test.dart';
import 'package:pegasus/src/home/home_layout.dart';

void main() {
  HomeLayout build(List<(String, WidgetSize)> items) {
    var l = HomeLayout.empty;
    for (final (m, s) in items) {
      l = l.add('$m-${l.all.length}', m, s).$1;
    }
    return l;
  }

  test('tailles : 1×1, 2×2, 4×2, 4×4', () {
    expect([for (final s in WidgetSize.values) s.cells], [1, 4, 8, 16]);
  });

  test('accueil par défaut : trackpad 4×4 + clavier 4×2 remplissent la page', () {
    final l = build([('trackpad', WidgetSize.large), ('keyboard', WidgetSize.wide)]);
    expect(l.pageCount, 1);
    expect(l.pages[0].map((w) => (w.col, w.row)).toList(), [(0, 0), (0, 4)]);
    expect(l.freeSpot(0, WidgetSize.small), isNull);
  });

  test('page pleine → nouvelle page créée', () {
    final (l, page) = build([('trackpad', WidgetSize.large), ('keyboard', WidgetSize.wide)])
        .add('x', 'power', WidgetSize.small);
    expect(page, 1);
    expect(l.pageCount, 2);
    expect(l.pages[1].single.moduleId, 'power');
  });

  test('remplissage ligne par ligne sans chevauchement', () {
    final l = build([for (var i = 0; i < 24; i++) ('m$i', WidgetSize.small)]);
    expect(l.pageCount, 1);
    final cells = {for (final w in l.all) (w.col, w.row)};
    expect(cells, hasLength(24));
    expect(build([for (var i = 0; i < 25; i++) ('m$i', WidgetSize.small)]).pageCount, 2);
  });

  test('aucune case partielle : un 4×4 ne se pose pas sous 3 rangées occupées', () {
    final l = build([('a', WidgetSize.wide), ('b', WidgetSize.small)]);
    // a = rangées 0-1, b = (0,2) → un 4×4 ne tient plus (il faudrait 4 rangées libres complètes).
    expect(l.freeSpot(0, WidgetSize.large), isNull);
    expect(l.freeSpot(0, WidgetSize.wide), (col: 0, row: 3));
  });

  test('retirer : une page vide disparaît, il reste toujours une page', () {
    var (l, _) = build([('trackpad', WidgetSize.large), ('keyboard', WidgetSize.wide)]).add('p', 'power', WidgetSize.small);
    l = l.remove('p');
    expect(l.pageCount, 1);
    l = l.remove(l.all.first.id).remove(l.all.last.id);
    expect(l.pageCount, 1);
    expect(l.all, isEmpty);
  });

  test('déplacer : place libre acceptée, place occupée refusée, nouvelle page possible', () {
    final l = build([('a', WidgetSize.medium), ('b', WidgetSize.medium)]);
    final a = l.pages[0][0];
    expect(l.move(a.id, 0, 2, 0), isNull, reason: 'occupé par b');
    final moved = l.move(a.id, 0, 0, 4)!;
    expect(moved.find(a.id)!.$1.row, 4);
    expect(l.move(a.id, 0, 3, 0), isNull, reason: 'dépasse à droite');
    final newPage = l.move(a.id, 1, 0, 0)!;
    expect(newPage.pageCount, 2);
    expect(newPage.find(a.id)!.$2, 1);
  });

  test('déplacer le seul widget d’une page vers une autre supprime la page vide', () {
    var (l, _) = build([('t', WidgetSize.large), ('k', WidgetSize.wide)]).add('p', 'power', WidgetSize.small);
    l = l.remove(l.pages[0][1].id); // libère 2 rangées en page 0
    final moved = l.move('p', 0, 0, 4)!;
    expect(moved.pageCount, 1);
  });

  test('redimensionner : sur place, sinon ailleurs sur la page, sinon autre page', () {
    var l = build([('a', WidgetSize.small), ('b', WidgetSize.small)]);
    final a = l.pages[0][0].id;
    l = l.resize(a, WidgetSize.medium); // (0,0) en 2×2 chevauche b (1,0) → déplacé
    final w = l.find(a)!.$1;
    expect(w.size, WidgetSize.medium);
    expect(l.all.where((x) => x.id != a).every((x) => !x.overlaps(w)), isTrue);

    final full = build([('t', WidgetSize.large), ('k', WidgetSize.wide)]);
    final grown = full.resize(full.pages[0][1].id, WidgetSize.large);
    expect(grown.pageCount, 2);
  });

  test('JSON : aller-retour ; modules inconnus, doublons et chevauchements écartés', () {
    final l = build([('trackpad', WidgetSize.large), ('keyboard', WidgetSize.wide)]);
    final back = HomeLayout.fromJson(l.toJson(), knownModule: (_) => true);
    expect(back.toJson(), l.toJson());

    final messy = {
      'pages': [
        [
          {'id': '1', 'module': 'trackpad', 'size': 'large', 'col': 0, 'row': 0},
          {'id': '2', 'module': 'keyboard', 'size': 'wide', 'col': 0, 'row': 2}, // chevauche
          {'id': '3', 'module': 'inconnu', 'size': 'small', 'col': 0, 'row': 5},
          {'id': '1', 'module': 'trackpad', 'size': 'small', 'col': 3, 'row': 5}, // doublon
          {'id': '4', 'module': 'keyboard', 'size': 'géant', 'col': 0, 'row': 0},
        ],
        'pas une page',
      ],
    };
    final fixed = HomeLayout.fromJson(messy, knownModule: (m) => m != 'inconnu');
    expect(fixed.all.map((w) => w.id).toSet(), {'1', '2'});
    final ws = fixed.all.toList();
    expect(ws[0].overlaps(ws[1]), isFalse);
    expect(HomeLayout.fromJson('n’importe quoi', knownModule: (_) => true).all, isEmpty);
  });
}
