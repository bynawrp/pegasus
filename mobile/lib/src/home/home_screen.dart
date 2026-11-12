import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pegasus_ui/pegasus_ui.dart';

import '../modules/registry.dart';
import 'home_layout.dart';
import 'home_layout_provider.dart';
import 'widget_gallery.dart';

/// Accueil : pages de 4 × 6 cases (glissement horizontal, jamais de défilement
/// continu), mode édition façon écran d'accueil iOS : en glissant un widget,
/// les autres se réorganisent en direct.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  final _pages = PageController();
  late final AnimationController _wiggle =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  bool _editing = false;
  int _page = 0;

  /// Widget en cours de glisser, aperçu de la réorganisation, position du
  /// doigt (repère de la grille) et point de prise dans le widget.
  String? _dragging;
  HomeLayout? _preview;
  Offset _finger = Offset.zero;
  Offset _grab = Offset.zero;
  Timer? _edgeTimer;
  final _gridKey = GlobalKey();

  @override
  void dispose() {
    _pages.dispose();
    _wiggle.dispose();
    _edgeTimer?.cancel();
    super.dispose();
  }

  void _setEditing(bool v) {
    setState(() => _editing = v);
    if (v) {
      HapticFeedback.mediumImpact();
      _wiggle.repeat(reverse: true);
    } else {
      _wiggle.stop();
      _wiggle.value = 0;
    }
  }

  void _goTo(int page) {
    if (!_pages.hasClients) return;
    _pages.animateToPage(page, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _add() async {
    final choice = await showWidgetGallery(context);
    if (choice == null) return;
    final page = await ref.read(homeLayoutProvider.notifier).add(choice.$1, choice.$2, preferredPage: _page);
    _goTo(page);
  }

  Offset _toGrid(Offset global) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? global : box.globalToLocal(global);
  }

  /// Appui long sur un widget en mode édition : début du glisser.
  void _dragStart(Placement w, Offset global, GridMetrics grid) {
    HapticFeedback.mediumImpact();
    final local = _toGrid(global);
    setState(() {
      _dragging = w.id;
      _preview = null;
      _finger = local;
      _grab = local - grid.rect(w.col, w.row, w.size).topLeft;
    });
  }

  void _dragMove(Offset global, GridMetrics grid, int pageCount) {
    final id = _dragging;
    final layout = ref.read(homeLayoutProvider).value;
    if (id == null || layout == null) return;
    final local = _toGrid(global);
    setState(() => _finger = local);

    // Bord de l'écran : page voisine après un court instant.
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 0;
    if (local.dx < 20) {
      _edgeHover(-1, pageCount);
    } else if (local.dx > width - 20) {
      _edgeHover(1, pageCount);
    } else {
      _edgeLeave();
    }

    final size = layout.find(id)!.$1.size;
    final cell = grid.cellAt(local - _grab, size);
    final next = layout.dropAt(id, _page, cell.col, cell.row);
    if (next.toJson().toString() != (_preview ?? layout).toJson().toString()) {
      HapticFeedback.selectionClick();
      setState(() => _preview = next);
    }
  }

  Future<void> _dragEnd() async {
    final preview = _preview;
    _edgeLeave();
    setState(() {
      _dragging = null;
      _preview = null;
    });
    if (preview != null) await ref.read(homeLayoutProvider.notifier).commit(preview);
  }

  /// Glisser au bord de l'écran pendant un déplacement : page voisine.
  void _edgeHover(int direction, int pageCount) {
    if (_edgeTimer != null) return;
    _edgeTimer = Timer(const Duration(milliseconds: 550), () {
      _edgeTimer = null;
      final target = (_page + direction).clamp(0, pageCount - 1);
      if (target != _page) _goTo(target);
    });
  }

  void _edgeLeave() {
    _edgeTimer?.cancel();
    _edgeTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(homeLayoutProvider).value;
    final locked = ref.watch(homePagingLockProvider) > 0;
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    if (saved == null) return const SizedBox.shrink();
    final layout = _preview ?? saved;

    // Pendant un glisser, une page vide en plus permet d'en créer une.
    final pageCount = layout.pageCount + (_dragging != null ? 1 : 0);
    final page = _page.clamp(0, max(pageCount - 1, 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 40,
          child: Row(
            children: [
              Expanded(
                child: Text(_editing ? 'MODIFIER' : 'ACCUEIL',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: text.headlineSmall),
              ),
              if (_editing) ...[
                IconButton(
                  key: const ValueKey('home-add'),
                  tooltip: 'Ajouter un widget',
                  onPressed: _add,
                  icon: Icon(Icons.add_circle_outline_rounded, color: c.accent2),
                ),
                FilledButton(
                  key: const ValueKey('home-done'),
                  onPressed: () => _setEditing(false),
                  child: const Text('Terminé', maxLines: 1),
                ),
              ] else
                TextButton(
                  key: const ValueKey('home-edit'),
                  onPressed: () => _setEditing(true),
                  child: const Text('Modifier', maxLines: 1),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final grid = GridMetrics(box.biggest);
            final dragged = _dragging == null ? null : layout.find(_dragging!)?.$1;
            return Listener(
              key: _gridKey,
              // Le glisser est suivi ici : il survit aux réorganisations et
              // aux changements de page.
              onPointerMove: _dragging == null ? null : (e) => _dragMove(e.position, grid, pageCount),
              onPointerUp: _dragging == null ? null : (_) => _dragEnd(),
              onPointerCancel: _dragging == null ? null : (_) => _dragEnd(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  PageView.builder(
                    key: const ValueKey('home-pages'),
                    controller: _pages,
                    // Doigt sur le trackpad ou widget en cours de glisser : pages figées.
                    physics: locked || _dragging != null ? const NeverScrollableScrollPhysics() : null,
                    itemCount: pageCount,
                    onPageChanged: (p) => setState(() => _page = p),
                    itemBuilder: (context, p) => _HomePage(
                      placements: p < layout.pageCount ? layout.pages[p] : const [],
                      grid: grid,
                      editing: _editing,
                      dragging: _dragging,
                      wiggle: _wiggle,
                      onLongPress: () => _setEditing(true),
                      onDragStart: (w, global) => _dragStart(w, global, grid),
                    ),
                  ),
                  if (dragged != null)
                    Positioned.fromRect(
                      rect: grid.rect(0, 0, dragged.size).shift(_finger - _grab - const Offset(GridMetrics.gap / 2, GridMetrics.gap / 2)),
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: 0.9,
                          child: HomeTile(
                            key: const ValueKey('drag-floating'),
                            placement: dragged,
                            module: moduleById(dragged.moduleId)!,
                            editing: true,
                            floating: true,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        SizedBox(
          height: 18,
          child: Row(
            key: const ValueKey('home-dots'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < pageCount; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == page ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == page ? c.accent : c.line,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Taille d'une case et conversions position ↔ case.
class GridMetrics {
  GridMetrics(Size area)
      : cellW = area.width / HomeLayout.cols,
        cellH = area.height / HomeLayout.rows;

  final double cellW;
  final double cellH;
  static const gap = 6.0;

  Rect rect(int col, int row, WidgetSize size) => Rect.fromLTWH(
        col * cellW + gap / 2,
        row * cellH + gap / 2,
        size.cols * cellW - gap,
        size.rows * cellH - gap,
      );

  ({int col, int row}) cellAt(Offset topLeft, WidgetSize size) => (
        col: (topLeft.dx / cellW).round().clamp(0, HomeLayout.cols - size.cols),
        row: (topLeft.dy / cellH).round().clamp(0, HomeLayout.rows - size.rows),
      );
}

class _HomePage extends StatelessWidget {
  const _HomePage({
    required this.placements,
    required this.grid,
    required this.editing,
    required this.dragging,
    required this.wiggle,
    required this.onLongPress,
    required this.onDragStart,
  });

  final List<Placement> placements;
  final GridMetrics grid;
  final bool editing;
  final String? dragging;
  final Animation<double> wiggle;
  final VoidCallback onLongPress;
  final void Function(Placement w, Offset global) onDragStart;

  @override
  Widget build(BuildContext context) {
    final c = context.pegasus;
    return Stack(
      children: [
        for (final w in placements)
          AnimatedPositioned.fromRect(
            key: ValueKey('tile-${w.id}'),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            rect: grid.rect(w.col, w.row, w.size),
            child: w.id == dragging
                // Emplacement réservé au widget qu'on déplace.
                ? DecoratedBox(
                    key: const ValueKey('drop-preview'),
                    decoration: BoxDecoration(
                      color: c.accent2.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(PegasusRadii.card),
                      border: Border.all(color: c.accent2),
                    ),
                  )
                : _tile(w),
          ),
      ],
    );
  }

  Widget _tile(Placement w) {
    final module = moduleById(w.moduleId);
    if (module == null) return const SizedBox.shrink();
    final tile = HomeTile(placement: w, module: module, editing: editing);
    if (!editing) {
      return GestureDetector(onLongPress: onLongPress, child: tile);
    }
    return GestureDetector(
      onLongPressStart: (d) => onDragStart(w, d.globalPosition),
      child: AnimatedBuilder(
        animation: wiggle,
        builder: (context, child) => Transform.rotate(
          angle: (wiggle.value - 0.5) * 0.03 * (w.id.hashCode.isEven ? 1 : -1),
          child: child,
        ),
        child: tile,
      ),
    );
  }
}

/// Un widget de l'accueil.
class HomeTile extends ConsumerWidget {
  const HomeTile({
    super.key,
    required this.placement,
    required this.module,
    required this.editing,
    this.floating = false,
  });

  final Placement placement;
  final PegasusModule module;
  final bool editing;
  final bool floating;

  void _open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: module.screen!));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    final small = placement.size == WidgetSize.small || module.widget == null;

    Widget body;
    if (small) {
      body = InkWell(
        borderRadius: BorderRadius.circular(PegasusRadii.card),
        onTap: editing ? null : () => _open(context),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(module.icon, color: c.accent2, size: 26),
                  const SizedBox(height: 4),
                  Text(module.name, maxLines: 1, style: text.labelMedium),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      body = Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: IgnorePointer(ignoring: editing, child: module.widget!(context, placement.size)),
            ),
          ),
          if (!editing)
            Positioned(
              top: 2,
              right: 2,
              child: SizedBox.square(
                dimension: 30,
                child: IconButton(
                  key: ValueKey('open-${placement.id}'),
                  tooltip: 'Ouvrir ${module.name}',
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  onPressed: () => _open(context),
                  icon: Icon(Icons.open_in_full_rounded, color: c.textMuted),
                ),
              ),
            ),
        ],
      );
    }

    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(PegasusRadii.card),
                border: Border.all(color: editing ? c.accent2.withValues(alpha: 0.6) : c.line),
                boxShadow: floating ? PegasusEffects.neonGlow(c.accent2, Theme.of(context).brightness) : null,
              ),
              child: ClipRRect(borderRadius: BorderRadius.circular(PegasusRadii.card), child: body),
            ),
          ),
          if (editing && !floating) ...[
            // Toucher le widget : changer sa taille.
            if (module.sizes.length > 1)
              Positioned.fill(
                child: GestureDetector(
                  key: ValueKey('resize-${placement.id}'),
                  behavior: HitTestBehavior.translucent,
                  onTap: () => _pickSize(context, ref),
                ),
              ),
            Positioned(
              top: -6,
              left: -6,
              child: GestureDetector(
                key: ValueKey('remove-${placement.id}'),
                onTap: () => ref.read(homeLayoutProvider.notifier).remove(placement.id),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle, border: Border.all(color: c.background, width: 2)),
                  child: Icon(Icons.remove_rounded, size: 16, color: c.background),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickSize(BuildContext context, WidgetRef ref) async {
    final size = await showModalBottomSheet<WidgetSize>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('TAILLE · ${module.name.toUpperCase()}', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              SizeChoices(
                sizes: module.sizes,
                selected: placement.size,
                onSelected: (s) => Navigator.pop(context, s),
              ),
            ],
          ),
        ),
      ),
    );
    if (size != null && size != placement.size) {
      await ref.read(homeLayoutProvider.notifier).resize(placement.id, size);
    }
  }
}
