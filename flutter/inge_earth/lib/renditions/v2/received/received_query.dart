import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../renditions_models.dart';
import '../widgets/dashboard_widgets.dart';
import 'received_models.dart';
import 'received_metro_board.dart';

const snapshotImmutability =
    'Esta versión representa el estado inmutable presentado. La recepción y las observaciones administrativas no transfieren la propiedad ni modifican el snapshot, su versión o su hash. Otras versiones históricas requieren soporte del backend.';

String _text(JsonMap row, String key) => receivedText(row, key);
bool _matches(JsonMap row, String query) =>
    query.trim().isEmpty ||
    row.values
        .where((v) => v != null)
        .join(' ')
        .toLowerCase()
        .contains(query.trim().toLowerCase());

class ReceivedQuery extends StatefulWidget {
  const ReceivedQuery({
    required this.rendition,
    required this.notes,
    required this.activity,
    required this.layout,
    required this.palette,
    required this.search,
    required this.onNote,
    required this.onAttachment,
    required this.adminLoading,
    required this.adminError,
    required this.onAdminRetry,
    super.key,
  });
  final ReceivedRendition rendition;
  final List<JsonMap> notes, activity;
  final ReceivedMetroLayout layout;
  final RenditionsPalette palette;
  final String search, adminError;
  final bool adminLoading;
  final Future<void> Function(String body, String requestId) onNote;
  final ValueChanged<JsonMap> onAttachment;
  final VoidCallback onAdminRetry;
  @override
  State<ReceivedQuery> createState() => ReceivedQueryState();
}

class ReceivedQueryState extends State<ReceivedQuery> {
  final _board = GlobalKey<ReceivedMetroBoardState>();
  final _note = TextEditingController();
  String _noteRequest = '', _lastBody = '', _error = '';
  bool _saving = false, _activityTab = false;
  void focusTile(String id) => _board.currentState?.focusTile(id);
  void focusSearchMatch() {
    if (widget.search.trim().isEmpty) return;
    if (widget.rendition.expenses.any((r) => _matches(r, widget.search))) {
      focusTile('expenses');
      return;
    }
    if (widget.rendition.attachments.any((r) => _matches(r, widget.search))) {
      focusTile('supports');
      return;
    }
    if (widget.notes.any((r) => _matches(r, widget.search))) {
      setState(() => _activityTab = false);
      focusTile('admin');
      return;
    }
    if (widget.activity.any((r) => _matches(r, widget.search))) {
      setState(() => _activityTab = true);
      focusTile('admin');
    }
  }

  @override
  void didUpdateWidget(covariant ReceivedQuery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.search != widget.search) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) focusSearchMatch();
      });
    }
  }

  String _uuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<void> _save() async {
    final body = _note.text.trim();
    if (body.isEmpty || _saving) return;
    if (_lastBody != body || _noteRequest.isEmpty) {
      _lastBody = body;
      _noteRequest = _uuid();
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await widget.onNote(body, _noteRequest);
      if (mounted) {
        _note.clear();
        _lastBody = _noteRequest = '';
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rendition, p = widget.palette;
    final expenses = r.expenses
        .where((e) => _matches(e, widget.search))
        .toList();
    final attachments = r.attachments
        .where((e) => _matches(e, widget.search))
        .toList();
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 164),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              r.code,
              style: TextStyle(
                color: p.primary,
                fontWeight: FontWeight.w700,
                fontSize: 23,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Consulta de snapshot · V${r.version}',
                style: TextStyle(color: p.secondary, fontSize: 12),
              ),
            ),
            ReceivedMetroBoard(
              key: _board,
              layout: widget.layout,
              palette: p,
              tiles: {
                'snapshot': ReceivedMetroTile(
                  'Snapshot',
                  LucideIcons.shieldCheck,
                  (_) => ListView(
                    padding: const EdgeInsets.all(12),
                    children: snapshotDetails(r, widget.notes.length, p),
                  ),
                ),
                'expenses': ReceivedMetroTile(
                  'Gastos',
                  LucideIcons.receipt,
                  (_) => _rows(
                    expenses,
                    (e) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _text(e, 'concept'),
                          style: TextStyle(
                            color: p.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${receivedDate(_text(e, 'expense_date'))} · ${_text(e, 'category_name')} · ${_text(e, 'beneficiary')}',
                          style: TextStyle(color: p.secondary, fontSize: 11),
                        ),
                        Text(
                          '${_text(e, 'currency_code')} ${numberField(e, 'amount').toStringAsFixed(2)}',
                          style: TextStyle(
                            color: p.accent,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${_text(e, 'payment_method_name')} · ${_text(e, 'support_type_name')} ${_text(e, 'support_number')}',
                          style: TextStyle(color: p.tertiary, fontSize: 10),
                        ),
                      ],
                    ),
                    'Sin gastos coincidentes',
                  ),
                ),
                'supports': ReceivedMetroTile(
                  'Sustentos',
                  LucideIcons.paperclip,
                  (_) => _rows(
                    attachments,
                    (a) => InkWell(
                      onTap: () => widget.onAttachment(a),
                      child: Row(
                        children: [
                          Icon(LucideIcons.file, size: 20, color: p.accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _text(a, 'file_name'),
                                  style: TextStyle(
                                    color: p.primary,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  '${_text(a, 'support_type_code')} ${_text(a, 'document_number')}',
                                  style: TextStyle(
                                    color: p.secondary,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    r.attachments.isEmpty
                        ? 'Sin sustentos presentados'
                        : 'Sin sustentos coincidentes',
                  ),
                ),
                'admin': ReceivedMetroTile(
                  'Administración',
                  LucideIcons.messagesSquare,
                  (_) => Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () =>
                                  setState(() => _activityTab = false),
                              child: Text(
                                'Observaciones',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: !_activityTab ? p.accent : p.secondary,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: TextButton(
                              onPressed: () =>
                                  setState(() => _activityTab = true),
                              child: Text(
                                'Actividad',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _activityTab ? p.accent : p.secondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (widget.adminLoading)
                        const LinearProgressIndicator(minHeight: 2),
                      Expanded(
                        child: _activityTab
                            ? activityList(
                                widget.activity
                                    .where((a) => _matches(a, widget.search))
                                    .toList(),
                                p,
                              )
                            : ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  12,
                                ),
                                children: [
                                  TextField(
                                    controller: _note,
                                    maxLength: 4000,
                                    minLines: 2,
                                    maxLines: 4,
                                    enabled: !_saving,
                                    style: TextStyle(
                                      color: p.primary,
                                      fontSize: 12,
                                    ),
                                    decoration: const InputDecoration(
                                      labelText: 'Nueva observación',
                                      counterText: '',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  FilledButton(
                                    onPressed: _saving ? null : _save,
                                    child: Text(
                                      _saving
                                          ? 'Registrando…'
                                          : 'Registrar observación',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  if (_error.isNotEmpty)
                                    Text(
                                      _error,
                                      style: TextStyle(
                                        color: p.error,
                                        fontSize: 11,
                                      ),
                                    ),
                                  if (widget.adminError.isNotEmpty)
                                    TextButton(
                                      onPressed: widget.onAdminRetry,
                                      child: Text(
                                        '${widget.adminError} · Reintentar',
                                        style: TextStyle(
                                          color: p.error,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  for (final note in widget.notes.where(
                                    (n) => _matches(n, widget.search),
                                  ))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _text(note, 'body'),
                                            style: TextStyle(
                                              color: p.primary,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            '${_text(note, 'author_name')} · ${receivedDate(_text(note, 'created_at'), time: true)}',
                                            style: TextStyle(
                                              color: p.secondary,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (widget.notes.isEmpty &&
                                      !widget.adminLoading)
                                    Text(
                                      'Sin observaciones registradas',
                                      style: TextStyle(
                                        color: p.secondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _rows(
    List<JsonMap> rows,
    Widget Function(JsonMap) builder,
    String empty,
  ) => rows.isEmpty
      ? Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              empty,
              textAlign: TextAlign.center,
              style: TextStyle(color: widget.palette.secondary, fontSize: 12),
            ),
          ),
        )
      : ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          separatorBuilder: (_, _) => Divider(color: widget.palette.border),
          itemBuilder: (_, i) => builder(rows[i]),
        );
}

List<Widget> snapshotDetails(
  ReceivedRendition r,
  int notes,
  RenditionsPalette p,
) {
  final fields = <String, String>{
    'RDC': r.code,
    'Autorización': 'Snapshot administrativo autorizado',
    'Estado': '${r.status} · V${r.version}',
    'Recepción': r.reception,
    'Propietario': r.owner,
    'Proyecto': r.project,
    'Periodo': '${receivedDate(r.start)} – ${receivedDate(r.end)}',
    'Presentada': receivedDate(r.submitted, time: true),
    'Recibida': receivedDate(r.receivedAt, time: true),
    'Gastos': '${r.expenseCount}',
    'Total PEN': r.pen.toStringAsFixed(2),
    'Total USD': r.usd.toStringAsFixed(2),
    'Observaciones': '$notes',
    'Versión ID': r.versionId,
    'Hash': r.hash,
    'Inmutabilidad': snapshotImmutability,
  };
  return [
    for (final entry in fields.entries)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.key, style: TextStyle(color: p.tertiary, fontSize: 10)),
            SelectableText(
              entry.value,
              style: TextStyle(color: p.primary, fontSize: 12),
            ),
          ],
        ),
      ),
  ];
}

Widget activityList(List<JsonMap> rows, RenditionsPalette p) => rows.isEmpty
    ? Center(
        child: Text(
          'Sin actividad disponible',
          style: TextStyle(color: p.secondary, fontSize: 12),
        ),
      )
    : ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: rows.length,
        separatorBuilder: (_, _) => Divider(color: p.border),
        itemBuilder: (_, index) {
          final row = rows[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _text(row, 'action'),
                style: TextStyle(
                  color: p.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _text(row, 'actor_name'),
                style: TextStyle(color: p.primary, fontSize: 12),
              ),
              Text(
                '${receivedDate(_text(row, 'occurred_at'), time: true)} · ${_text(row, 'platform')}',
                style: TextStyle(color: p.secondary, fontSize: 10),
              ),
              Text(
                '${_text(row, 'entity_type')} · ${_text(row, 'entity_id')}',
                style: TextStyle(color: p.tertiary, fontSize: 10),
              ),
            ],
          );
        },
      );

Future<void> showSnapshotContext(
  BuildContext context,
  ReceivedRendition rendition,
  List<JsonMap> notes,
  List<JsonMap> activity,
  RenditionsPalette palette,
) => showDialog<void>(
  context: context,
  builder: (_) => Dialog(
    backgroundColor: palette.surface,
    insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 40),
    child: SizedBox(
      width: 390,
      height: MediaQuery.sizeOf(context).height * .67,
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 6, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rendition.code,
                      style: TextStyle(
                        color: palette.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar contexto',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, size: 19),
                  ),
                ],
              ),
            ),
            Text(
              'Snapshot administrativo autorizado',
              style: TextStyle(color: palette.accent, fontSize: 11),
            ),
            const TabBar(
              tabs: [
                Tab(text: 'Detalles'),
                Tab(text: 'Actividad'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: snapshotDetails(rendition, notes.length, palette),
                  ),
                  activityList(activity, palette),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);
