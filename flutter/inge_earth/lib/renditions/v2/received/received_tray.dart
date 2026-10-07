import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'received_models.dart';
import 'received_metro_board.dart';
import '../widgets/dashboard_widgets.dart';

class ReceivedTray extends StatelessWidget {
  const ReceivedTray({
    required this.rows,
    required this.filteredRows,
    required this.loading,
    required this.error,
    required this.layout,
    required this.palette,
    required this.onSelect,
    required this.onRetry,
    super.key,
  });
  final List<ReceivedRendition> rows, filteredRows;
  final bool loading;
  final String error;
  final ReceivedMetroLayout layout;
  final RenditionsPalette palette;
  final ValueChanged<ReceivedRendition> onSelect;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 164),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rendiciones recibidas',
            style: TextStyle(
              color: palette.primary,
              fontSize: 23,
              fontWeight: FontWeight.w700,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Snapshot administrativo · mantén pulsado para organizar',
              style: TextStyle(color: palette.secondary, fontSize: 11),
            ),
          ),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextButton(
                onPressed: onRetry,
                child: Text(
                  '$error · Reintentar',
                  style: TextStyle(color: palette.error),
                ),
              ),
            ),
          ReceivedMetroBoard(
            layout: layout,
            palette: palette,
            tiles: {
              'summary': ReceivedMetroTile(
                'Resumen',
                LucideIcons.chartNoAxesColumn,
                (size) => ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _metric(
                      'Presentadas',
                      rows.where((r) => r.status == 'PRESENTADA').length,
                    ),
                    _metric('Recibidas', rows.where((r) => r.received).length),
                    _metric(
                      'Pendientes de recepción',
                      rows.where((r) => !r.received).length,
                    ),
                    Text(
                      'Sobre ${rows.length} rendiciones cargadas',
                      style: TextStyle(color: palette.tertiary, fontSize: 10),
                    ),
                  ],
                ),
              ),
              'renditions': ReceivedMetroTile(
                'Rendiciones',
                LucideIcons.inbox,
                (size) => filteredRows.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            loading
                                ? 'Cargando…'
                                : 'Sin rendiciones para estos criterios',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: palette.secondary),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: filteredRows.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: palette.border),
                        itemBuilder: (context, index) {
                          final r = filteredRows[index];
                          return InkWell(
                            onTap: () => onSelect(r),
                            child: Padding(
                              padding: const EdgeInsets.all(11),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.code,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: palette.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${r.status} · V${r.version}',
                                    style: TextStyle(
                                      color: palette.accent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    r.reception,
                                    style: TextStyle(
                                      color: palette.secondary,
                                      fontSize: 10,
                                    ),
                                  ),
                                  if (size != MetroSize.small) ...[
                                    const SizedBox(height: 5),
                                    Text(
                                      '${r.owner} · ${r.project}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: palette.primary,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      '${r.expenseCount} gastos · PEN ${r.pen.toStringAsFixed(2)} · USD ${r.usd.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: palette.secondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                  if (size == MetroSize.large) ...[
                                    Text(
                                      '${receivedDate(r.start)} – ${receivedDate(r.end)}',
                                      style: TextStyle(
                                        color: palette.tertiary,
                                        fontSize: 10,
                                      ),
                                    ),
                                    Text(
                                      'Presentada ${receivedDate(r.submitted, time: true)}',
                                      style: TextStyle(
                                        color: palette.tertiary,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            },
          ),
        ],
      ),
    ),
  );
  Widget _metric(String title, int value) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      children: [
        Text(
          '$value',
          style: TextStyle(
            color: palette.accent,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(color: palette.primary, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}
