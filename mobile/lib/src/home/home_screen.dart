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
/// continu), mode édition façon écran d'accueil iOS.
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
  String? _dragging;
  Timer? _edgeTimer;

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

  /// Glisser au bord de l'écran pendant un déplacement : page voisine.
  void _edgeHover(int direction, int pageCount) {
    if (_edgeTimer != null) return;
    _edgeTimer = Timer(const Duration(milliseconds: 550), () {
      _edgeTimer = null;
      final target = (_page + direction).clamp(0, pageCount);
      if (target != _page) _goTo(target);
    });
  }

  void _edgeLeave() {
    _edgeTimer?.cancel();
    _edgeTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(homeLayoutProvider).value;
    final c = context.pegasus;
    final text = Theme.of(context).textTheme;
    if (layout == null) return const SizedBox.shrink();

    // En mode édition, une page vide en plus permet d'y glisser un widget.
    final pageCount = layout.pageCount + (_editing && _dragging != null ? 1 : 0);
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
            final grid = _GridMetrics(box.biggest);
            return Stack(
              children: [
                PageView.builder(
                  key: const ValueKey('home-pages'),
                  controller: _pages,
                  itemCount: pageCount,
                  onPageChanged: (p) => setState(() => _page = p),
                  itemBuilder: (context, p) => _HomePage(
                    page: p,
                    placements: p < layout.pageCount ? layout.pages[p] : const [],
                    layout: layout,
                    grid: grid,
                    editing: _editing,
                    wiggle: _wiggle,
                    onLongPress: () => _setEditing(true),
                    onDragState: (id) => setState(() => _dragging = id),
                  ),
                ),
                if (_editing && _dragging != null) ...[
                  _EdgeZone(left: true, onHover: () => _edgeHover(-1, pageCount), onLeave: _edgeLeave),
                  _EdgeZone(left: false, onHover: () => _edgeHover(1, pageCount), onLeave: _edgeLeave),
                ],
              ],
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
class _GridMetrics {
  _GridMetrics(Size area)
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

class _HomePage extends ConsumerStatefulWidget {
  const _HomePage({
    required this.page,
    required this.placements,
    required this.layout,
    required this.grid,
    required this.editing,
    required this.wiggle,
    required this.onLongPress,
    required this.onDragState,
  });

  final int page;
  final List<Placement> placements;
  final HomeLayout layout;
  final _GridMetrics grid;
  final bool editing;
  final Animation<double> wiggle;
  final VoidCallback onLongPress;
  final ValueChanged<String?> onDragState;

  @override
  ConsumerState<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<_HomePage> {
  /// Case visée pendant un glisser : (col, row, place libre ?).
  (int, int, bool)? _hover;

  @override
  Widget build(BuildContext context) {
    final grid = widget.grid;
    final c = context.pegasus;
    final dragged = _hover == null ? null : widget.layout.find(_draggedId ?? '')?.$1;

    final content = Stack(
      children: [
        if (_hover != null && dragged != null)
          Positioned.fromRect(
            rect: grid.rect(_hover!.$1, _hover!.$2, dragged.size),
            child: DecoratedBox(
              key: const ValueKey('drop-preview'),
              decoration: BoxDecoration(
                color: (_hover!.$3 ? c.success : c.danger).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(PegasusRadii.card),
                border: Border.all(color: _hover!.$3 ? c.success : c.danger),
              ),
            ),
          ),
        for (final w in widget.placements)
          Positioned.fromRect(
            key: ValueKey('tile-${w.id}'),
            rect: grid.rect(w.col, w.row, w.size),
            child: _tile(w),
          ),
      ],
    );

    if (!widget.editing) return content;
    return DragTarget<String>(
      onMove: (d) => _updateHover(d.data, d.offset),
      onLeave: (_) => setState(() => _hover = null),
      onAcceptWithDetails: (d) async {
        final hover = _hover;
        setState(() => _hover = null);
        if (hover != null && hover.$3) {
          HapticFeedback.selectionClick();
          await ref.read(homeLayoutProvider.notifier).move(d.data, widget.page, hover.$1, hover.$2);
        }
      },
      builder: (context, _, _) => content,
    );
  }

  String? _draggedId;

  void _updateHover(String id, Offset globalTopLeft) {
    final box = context.findRenderObject() as RenderBox?;
    final found = widget.layout.find(id);
    if (box == null || found == null) return;
    _draggedId = id;
    final local = box.globalToLocal(globalTopLeft);
    final cell = widget.grid.cellAt(local, found.$1.size);
    final ok = widget.layout.fits(widget.page, found.$1.size, cell.col, cell.row, ignoreId: id);
    final next = (cell.col, cell.row, ok);
    if (next != _hover) setState(() => _hover = next);
  }

  Widget _tile(Placement w) {
    final module = moduleById(w.moduleId);
    if (module == null) return const SizedBox.shrink();
    final tile = HomeTile(placement: w, module: module, editing: widget.editing);
    if (!widget.editing) {
      return GestureDetector(onLongPress: widget.onLongPress, child: tile);
    }
    final rect = widget.grid.rect(w.col, w.row, w.size);
    final wiggling = AnimatedBuilder(
      animation: widget.wiggle,
      builder: (context, child) => Transform.rotate(
        angle: (widget.wiggle.value - 0.5) * 0.03 * (w.id.hashCode.isEven ? 1 : -1),
        child: child,
      ),
      child: tile,
    );
    return LongPressDraggable<String>(
      data: w.id,
      onDragStarted: () {
        HapticFeedback.mediumImpact();
        widget.onDragState(w.id);
      },
      onDragEnd: (_) => widget.onDragState(null),
      feedback: SizedBox(
        width: rect.width,
        height: rect.height,
        child: Opacity(opacity: 0.85, child: HomeTile(placement: w, module: module, editing: true, floating: true)),
      ),
      childWhenDragging: const SizedBox.shrink(),
      child: wiggling,
    );
  }
}

class _EdgeZone extends StatelessWidget {
  const _EdgeZone({required this.left, required this.onHover, required this.onLeave});
  final bool left;
  final VoidCallback onHover;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) => Positioned(
        left: left ? 0 : null,
        right: left ? null : 0,
        top: 0,
        bottom: 0,
        width: 22,
        child: DragTarget<String>(
          key: ValueKey(left ? 'edge-left' : 'edge-right'),
          onWillAcceptWithDetails: (_) {
            onHover();
            return false;
          },
          onMove: (_) => onHover(),
          onLeave: (_) => onLeave(),
          builder: (context, _, _) => const SizedBox.expand(),
        ),
      );
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
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
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
