import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../renditions_bridge.dart';
import '../renditions_models.dart';
import 'widgets/dashboard_widgets.dart';

class RenditionsDashboard extends StatelessWidget {
  const RenditionsDashboard({
    required this.bridge,
    required this.palette,
    required this.loading,
    required this.error,
    required this.query,
    required this.onRetry,
    required this.onRenditionTap,
    required this.onNew,
    required this.onReceived,
    super.key,
  });

  final RenditionsBridge bridge;
  final RenditionsPalette palette;
  final bool loading;
  final String error;
  final String query;
  final Future<void> Function() onRetry;
  final ValueChanged<RenditionData> onRenditionTap;
  final VoidCallback onNew;
  final VoidCallback onReceived;

  bool _matches(RenditionData item, String normalized) => <String>[
    item.code,
    item.reference,
    item.primaryProjectName,
    item.status,
    item.periodStart,
    item.periodEnd,
  ].any((value) => value.toLowerCase().contains(normalized));

  List<RenditionData> get _visibleRenditions {
    final normalized = query.trim().toLowerCase();
    final loaded = bridge.renditions.toList(growable: false);
    Iterable<RenditionData> result;
    if (normalized.isNotEmpty) {
      result = loaded.where((item) => _matches(item, normalized));
    } else {
      result = loaded;
    }
    final sorted = result.toList(growable: false)
      ..sort((a, b) {
        final aDate = a.updatedAt.isEmpty ? a.createdAt : a.updatedAt;
        final bDate = b.updatedAt.isEmpty ? b.createdAt : b.updatedAt;
        return bDate.compareTo(aDate);
      });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final loaded = bridge.renditions.length;
    final drafts = bridge.renditions
        .where((item) => item.status == 'BORRADOR')
        .length;
    final presented = bridge.renditions
        .where((item) => item.status == 'PRESENTADA')
        .length;
    final renditions = _visibleRenditions;
    final searching = query.trim().isNotEmpty;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: onRetry,
        color: palette.accent,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 150),
              sliver: SliverList.list(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Rendiciones',
                          style: TextStyle(
                            color: palette.primary,
                            fontSize: 23,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (bridge.pendingCount > 0)
                        CompactStatus(
                          palette: palette,
                          text: '${bridge.pendingCount} pendientes',
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  CompactMetricsStrip(
                    palette: palette,
                    loaded: loaded,
                    drafts: drafts,
                    presented: presented,
                  ),
                  if (loading) ...<Widget>[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      minHeight: 2,
                      color: palette.accent,
                      backgroundColor: palette.border,
                    ),
                  ],
                  if (error.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    CompactError(
                      palette: palette,
                      message: error,
                      onRetry: onRetry,
                    ),
                  ],
                  const SizedBox(height: 18),
                  SectionTitle(
                    palette: palette,
                    title: searching ? 'Resultados' : 'Tus rendiciones',
                  ),
                  const SizedBox(height: 7),
                  if (!loading && renditions.isEmpty)
                    CompactEmptyState(
                      palette: palette,
                      searching: searching,
                      onNew: onNew,
                    )
                  else
                    for (final item in renditions)
                      RecentRenditionRow(
                        palette: palette,
                        rendition: item,
                        onTap: () => onRenditionTap(item),
                      ),
                  const SizedBox(height: 18),
                  SectionTitle(
                    palette: palette,
                    title: 'Proyectos disponibles',
                    trailing: bridge.projects.isEmpty
                        ? null
                        : '${bridge.projects.length}',
                  ),
                  const SizedBox(height: 8),
                  ProjectStrip(palette: palette, projects: bridge.projects),
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: QuickTarget(
                          palette: palette,
                          icon: LucideIcons.inbox,
                          label: 'Recibidas',
                          onTap: onReceived,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: QuickTarget(
                          palette: palette,
                          icon: LucideIcons.filePlus,
                          label: 'Nueva',
                          emphasized: true,
                          onTap: onNew,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
