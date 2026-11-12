import 'package:flutter_test/flutter_test.dart';
import 'package:pegasus/src/home/home_layout.dart';

HomeLayout _build(List<(String, WidgetSize)> items) {
  var l = HomeLayout.empty;
  for (final (m, s) in items) {
    l = l.add(m, m, s).$1;
  }
  return l;
}

List<String> _order(HomeLayout l, [int page = 0]) => [for (final w in l.pages[page]) w.id];
(int, int) _pos(HomeLayout l, String id) {
  final w = l.find(id)!.$1;
  return (w.col, w.row);
}

void main() {
  test('tailles : 1×1, 2×2, 4×2, 4×4', () {
    expect([for (final s in WidgetSize.values) s.cells], [1, 4, 8, 16]);
  });

  test('accueil par défaut : trackpad 4×4 + clavier 4×2 remplissent la page', () {
    final l = _build([('trackpad', WidgetSize.large), ('keyboard', WidgetSize.wide)]);
    expect(l.pageCount, 1);
    expect([_pos(l, 'trackpad'), _pos(l, 'keyboard')], [(0, 0), (0, 4)]);
  });

  test('page pleine → nouvelle page', () {
    final (l, page) = _build([('t', WidgetSize.large), ('k', WidgetSize.wide)]).add('p', 'power', WidgetSize.small);
    expect(page, 1);
    expect(l.pages[1].single.id, 'p');
  });

  test('rangement automatique sans chevauchement ni case partielle', () {
    final l = _build([for (var i = 0; i < 25; i++) ('m$i', WidgetSize.small)]);
    expect(l.pageCount, 2);
    expect({for (final w in l.pages[0]) (w.col, w.row)}, hasLength(24));
  });

  group('façon iOS', () {
    test('déposer un widget sur un autre : l’autre est poussé, rien ne se chevauche', () {
      // a (2×2) en haut à gauche, b (2×2) à droite, c (4×2) dessous.
      var l = _build([('a', WidgetSize.medium), ('b', WidgetSize.medium), ('c', WidgetSize.wide)]);
      expect([_pos(l, 'a'), _pos(l, 'b'), _pos(l, 'c')], [(0, 0), (2, 0), (0, 2)]);
      // On glisse c tout en haut : a et b descendent.
      l = l.dropAt('c', 0, 0, 0);
      expect(_order(l), ['c', 'a', 'b']);
      expect([_pos(l, 'c'), _pos(l, 'a'), _pos(l, 'b')], [(0, 0), (0, 2), (2, 2)]);
    });

    test('glisser un widget vers le bas : ceux du dessous remontent', () {
      var l = _build([('a', WidgetSize.wide), ('b', WidgetSize.wide), ('c', WidgetSize.wide)]);
      l = l.dropAt('a', 0, 0, 4);
      expect(_order(l), ['b', 'c', 'a']);
      expect(_pos(l, 'b'), (0, 0));
      expect(_pos(l, 'a'), (0, 4));
    });

    test('échanger deux petits widgets de place', () {
      var l = _build([('a', WidgetSize.small), ('b', WidgetSize.small), ('c', WidgetSize.small)]);
      l = l.dropAt('c', 0, 0, 0);
      expect(_order(l), ['c', 'a', 'b']);
      expect(_pos(l, 'c'), (0, 0));
    });

    test('page pleine : le widget poussé passe en tête de la page suivante', () {
      var l = _build([('t', WidgetSize.large), ('k', WidgetSize.wide), ('p', WidgetSize.small)]);
      expect(l.pageCount, 2);
      // p (page 2) glissé en haut de la page 1 : le clavier ne tient plus et part en page 2.
      l = l.dropAt('p', 0, 0, 0);
      expect(_order(l), ['p', 't']);
      expect(_order(l, 1), ['k']);
    });

    test('retirer : les suivants remontent combler le vide', () {
      var l = _build([('a', WidgetSize.wide), ('b', WidgetSize.wide), ('c', WidgetSize.wide)]);
      l = l.remove('a');
      expect([_pos(l, 'b'), _pos(l, 'c')], [(0, 0), (0, 2)]);
    });

    test('page vidée par un déplacement → supprimée', () {
      var l = _build([('t', WidgetSize.large), ('k', WidgetSize.small), ('p', WidgetSize.wide)]);
      expect(l.pageCount, 2);
      l = l.remove('k').dropAt('p', 0, 0, 4);
      expect(l.pageCount, 1);
    });

    test('vers une nouvelle page (glisser au bord après la dernière page)', () {
      final l = _build([('a', WidgetSize.small), ('b', WidgetSize.small)]).dropAt('b', 1, 0, 0);
      expect(l.pageCount, 2);
      expect(_order(l, 1), ['b']);
    });

    test('agrandir un widget pousse les suivants (et sur la page suivante si besoin)', () {
      var l = _build([('t', WidgetSize.large), ('k', WidgetSize.wide)]);
      l = l.resize('t', WidgetSize.medium);
      expect(_pos(l, 'k'), (0, 2), reason: 'le clavier remonte à côté… puis sous le 2×2');
      l = l.resize('k', WidgetSize.large);
      expect(l.pageCount, 1);
      l = l.resize('t', WidgetSize.large);
      expect(l.pageCount, 2);
    });
  });

  test('JSON : aller-retour de l’ordre ; inconnus et doublons écartés ; anciennes sauvegardes triées', () {
    final l = _build([('trackpad', WidgetSize.large), ('keyboard', WidgetSize.wide)]);
    expect(HomeLayout.fromJson(l.toJson(), knownModule: (_) => true).toJson(), l.toJson());

    final old = {
      'v': 1,
      'pages': [
        [
          {'id': 'k', 'module': 'keyboard', 'size': 'wide', 'col': 0, 'row': 4},
          {'id': 't', 'module': 'trackpad', 'size': 'large', 'col': 0, 'row': 0},
          {'id': 'x', 'module': 'inconnu', 'size': 'small', 'col': 0, 'row': 5},
          {'id': 't', 'module': 'trackpad', 'size': 'small'},
          {'id': 'g', 'module': 'keyboard', 'size': 'géant'},
        ],
        'pas une page',
      ],
    };
    final fixed = HomeLayout.fromJson(old, knownModule: (m) => m != 'inconnu');
    expect(_order(fixed), ['t', 'k']);
    expect(HomeLayout.fromJson('n’importe quoi', knownModule: (_) => true).all, isEmpty);
  });
}
