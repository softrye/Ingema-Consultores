import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/dashboard_widgets.dart';

enum MetroSize { small, wide, large }

class MetroPlacement {
  const MetroPlacement(this.id, this.column, this.row, this.width, this.height);
  final String id;
  final int column, row, width, height;
}

/// UI-only session state. No business store or Supabase persistence.
class ReceivedMetroLayout extends ChangeNotifier {
  ReceivedMetroLayout(Map<String, MetroSize> initial)
    : sizes = Map.of(initial),
      order = initial.keys.toList() {
    if (order.length > 4) {
      throw ArgumentError('Metro admits at most four tiles.');
    }
    _reflow();
  }
  final Map<String, MetroSize> sizes;
  final List<String> order;
  List<MetroPlacement> placements = const [];
  bool editing = false;

  void edit(bool value) {
    editing = value;
    notifyListeners();
  }

  void resize(String id) {
    sizes[id] =
        MetroSize.values[(sizes[id]!.index + 1) % MetroSize.values.length];
    _reflow();
    notifyListeners();
  }

  void move(String id, String before) {
    if (id == before || !order.contains(id) || !order.contains(before)) return;
    final target = order.indexOf(before);
    order.remove(id);
    order.insert(target, id);
    _reflow();
    notifyListeners();
  }

  void _reflow() {
    final occupied = <int>{};
    final next = <MetroPlacement>[];
    for (final id in order) {
      final w = sizes[id] == MetroSize.small ? 1 : 2;
      final h = sizes[id] == MetroSize.large ? 2 : 1;
      var slot = 0;
      while (true) {
        final col = slot % 2, row = slot ~/ 2;
        final cells = [
          for (var y = 0; y < h; y++)
            for (var x = 0; x < w; x++) (row + y) * 2 + col + x,
        ];
        if (col + w <= 2 && !cells.any(occupied.contains)) {
          occupied.addAll(cells);
          next.add(MetroPlacement(id, col, row, w, h));
          break;
        }
        slot++;
      }
    }
    placements = List.unmodifiable(next);
  }
}

class ReceivedMetroTile {
  const ReceivedMetroTile(this.title, this.icon, this.builder);
  final String title;
  final IconData icon;
  final Widget Function(MetroSize size) builder;
}

class ReceivedMetroBoard extends StatefulWidget {
  const ReceivedMetroBoard({
    required this.layout,
    required this.tiles,
    required this.palette,
    super.key,
  });
  final ReceivedMetroLayout layout;
  final Map<String, ReceivedMetroTile> tiles;
  final RenditionsPalette palette;
  @override
  State<ReceivedMetroBoard> createState() => ReceivedMetroBoardState();
}

class ReceivedMetroBoardState extends State<ReceivedMetroBoard> {
  final Map<String, GlobalKey> _keys = {};
  void focusTile(String id) {
    final target = _keys[id]?.currentContext;
    if (target != null) Scrollable.ensureVisible(target, alignment: 0.02);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.layout,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final unit = (constraints.maxWidth - gap) / 2;
        final layout = widget.layout;
        final rows = layout.placements.fold<int>(
          0,
          (n, p) => n > p.row + p.height ? n : p.row + p.height,
        );
        return Column(
          children: [
            if (layout.editing)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Arrastra para mover · esquina para cambiar tamaño',
                      style: TextStyle(
                        color: widget.palette.secondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => layout.edit(false),
                    child: const Text('Listo'),
                  ),
                ],
              ),
            SizedBox(
              height: rows * (unit + gap) - gap,
              child: Stack(
                children: [
                  for (final p in layout.placements)
                    Positioned(
                      left: p.column * (unit + gap),
                      top: p.row * (unit + gap),
                      width: p.width * (unit + gap) - gap,
                      height: p.height * (unit + gap) - gap,
                      child: RepaintBoundary(
                        key: _keys.putIfAbsent(p.id, GlobalKey.new),
                        child: DragTarget<String>(
                          onWillAcceptWithDetails: (d) => d.data != p.id,
                          onAcceptWithDetails: (d) => layout.move(d.data, p.id),
                          builder: (context, candidates, rejected) =>
                              LongPressDraggable<String>(
                                data: p.id,
                                onDragStarted: () => layout.edit(true),
                                feedback: Material(
                                  color: widget.palette.accent,
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Text(
                                      widget.tiles[p.id]!.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.35,
                                  child: _tile(p, false),
                                ),
                                child: _tile(p, candidates.isNotEmpty),
                              ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _tile(MetroPlacement p, bool target) {
    final tile = widget.tiles[p.id]!, palette = widget.palette;
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
        side: BorderSide(
          color: target ? palette.accent : palette.border,
          width: target ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 38,
            color: palette.accentSoft,
            padding: const EdgeInsets.only(left: 10, right: 4),
            child: Row(
              children: [
                Icon(tile.icon, size: 16, color: palette.accent),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    tile.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: palette.primary,
                    ),
                  ),
                ),
                if (widget.layout.editing)
                  IconButton(
                    tooltip: 'Cambiar tamaño',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      LucideIcons.maximize2,
                      size: 17,
                      color: palette.accent,
                    ),
                    onPressed: () => widget.layout.resize(p.id),
                  ),
              ],
            ),
          ),
          Expanded(child: tile.builder(widget.layout.sizes[p.id]!)),
        ],
      ),
    );
  }
}
