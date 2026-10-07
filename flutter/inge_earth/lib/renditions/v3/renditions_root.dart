import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../renditions_bridge.dart';
import '../renditions_models.dart';
import '../v2/received/received_models.dart';
import '../v2/received/received_query.dart';
import '../v2/received/received_metro_board.dart';
import '../v2/widgets/dashboard_widgets.dart' show RenditionsPalette;
import 'components/nothing_components.dart';
import 'renditions_shell.dart';
import '../../dock_context_client.dart';
import 'screens/rendition_editor.dart';
import 'screens/expense_editor.dart';
import 'state/rendition_editor_state.dart';
import 'theme/rendition_theme.dart';

enum RenditionsRoute {
  home,
  received,
  editor,
  draft,
  expense,
  presentConfirm,
  presented,
  receivedDetail,
}

/// The existing Flutter PopScope consumes Android's existing Back delivery.
/// This state machine only changes content inside the Renditions subapp.
class RenditionsRootV3 extends StatefulWidget {
  const RenditionsRootV3({
    required this.dark,
    required this.onGlobalAction,
    this.bridge,
    super.key,
  });
  final bool dark;
  final Future<void> Function(String) onGlobalAction;
  final RenditionsBridge? bridge;
  @override
  State<RenditionsRootV3> createState() => _RenditionsRootV3State();
}

class _RenditionsRootV3State extends State<RenditionsRootV3> with WidgetsBindingObserver {
  late final RenditionsBridge bridge;
  RenditionsRoute route = RenditionsRoute.home;
  RenditionData? selected, editing;
  ExpenseData? expense;
  bool loading = true, working = false;
  String error = '', search = '', syncFeedback = '';
  bool refreshing = false, retrySync = false;
  Timer? retryTimer;
  int generation = 0, session = 0;
  int documentOpenRevision = 0;
  List<ReceivedRendition> received = [];
  ReceivedRendition? snapshot;
  List<JsonMap> notes = [], activity = [];
  final editorKey = GlobalKey<RenditionEditorViewState>();
  final expenseKey = GlobalKey<ExpenseEditorViewState>();
  final supportsKey = GlobalKey();
  final queryKey = GlobalKey<ReceivedQueryState>();
  final queryLayout = ReceivedMetroLayout({
    'snapshot': MetroSize.large,
    'expenses': MetroSize.large,
    'supports': MetroSize.wide,
    'admin': MetroSize.large,
  });
  RenditionData? get current =>
      bridge.current?.localId == selected?.localId ? bridge.current : selected;
  bool get editable =>
      current != null &&
      !current!.readOnly &&
      !current!.hasConflict &&
      current!.syncState != 'SYNCING' &&
      !bridge.busy &&
      !working;
  List<ExpenseData> get expenses => current == null
      ? []
      : jsonRows(
          current!.raw['expenses'],
        ).map(ExpenseData.new).where((e) => !e.archived).toList();

  @override
  void initState() {
    super.initState();
    bridge = widget.bridge ?? RenditionsBridge();
    bridge.addListener(changed);
    WidgetsBinding.instance.addObserver(this);
    retryTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if ((retrySync || (bridge.pendingCount > 0 && bridge.connectionState == 'OFFLINE')) &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          (route == RenditionsRoute.home || route == RenditionsRoute.received)) unawaited(refresh());
    });
    unawaited(bootstrap());
  }

  void changed() {
    if (!mounted) return;
    if (bridge.documentOpenRevision != documentOpenRevision &&
        bridge.current != null &&
        bridge.documentTargetId.isNotEmpty &&
        bridge.current!.remoteId == bridge.documentTargetId) {
      documentOpenRevision = bridge.documentOpenRevision;
      selected = bridge.current;
      route = selected!.readOnly
          ? RenditionsRoute.presented
          : RenditionsRoute.draft;
    }
    if (session != bridge.receivedSessionRevision) {
      session = bridge.receivedSessionRevision;
      generation++;
      selected = editing = null;
      snapshot = null;
      received = [];
      notes = [];
      activity = [];
      expense = null;
      search = '';
      working = false;
      refreshing = retrySync = false; syncFeedback = '';
      route = RenditionsRoute.home;
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
    if (route == RenditionsRoute.draft && current?.readOnly == true) {
      route = RenditionsRoute.presented;
    }
    setState(() {});
  }

  void editorChanged() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) setState(() {});
  });
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && (retrySync || bridge.pendingCount > 0)) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (refreshing || working || loading || bridge.busy) return;
    final epoch = generation;
    setState(() { refreshing = true; error = ''; syncFeedback = 'Sincronizando…'; });
    bridge.clearError();
    try {
      final result = await bridge.command('sync');
      if (!mounted || epoch != generation) return;
      retrySync = false;
      syncFeedback = (result['pendingCount'] as num? ?? bridge.pendingCount) > 0
          ? 'Hay cambios pendientes' : 'Actualizado';
      if (route == RenditionsRoute.received) await loadReceived(fromRefresh: true);
      if (error.isNotEmpty) syncFeedback = 'Hay cambios pendientes';
    } catch (e) {
      if (!mounted || epoch != generation) return;
      final network = bridge.connectionState == 'OFFLINE' ||
          RegExp(r'NETWORK|TIMEOUT|OFFLINE|HOST.*FOUND|CONNECTION|CONEXI', caseSensitive: false).hasMatch(e.toString());
      retrySync = network;
      syncFeedback = network ? 'Sin conexión, se intentará luego' : 'Hay cambios pendientes';
      if (!network) error = 'No se pudo completar la actualización. Revisa los cambios pendientes y vuelve a deslizar para reintentar.';
    } finally {
      if (mounted && epoch == generation) setState(() => refreshing = false);
    }
  }

  Widget searchChip() => Align(alignment: Alignment.centerLeft, child: InputChip(
    label: Text(search), onPressed: openSearch, onDeleted: () => setState(() => search = ''),
  ));

  Future<void> openSearch() async {
    final controller = TextEditingController(text: search);
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Buscar rendiciones'),
      content: TextField(controller: controller, autofocus: true, textInputAction: TextInputAction.search,
        decoration: InputDecoration(hintText: route == RenditionsRoute.received ? 'RDC, propietario o proyecto' : 'RDC o proyecto'),
        onSubmitted: (value) => Navigator.pop(context, value)),
      actions: [TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Limpiar')),
        TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Buscar'))],
    ));
    if (mounted && value != null) setState(() => search = value.trim());
    // Wait for the dialog exit transition before disposing its text controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }
  Future<void> bootstrap() async {
    await run(() async {
      await bridge.initialize();
    });
    if (mounted) {
      setState(() => loading = false);
      // Resume the persisted outbox after reopening, including offline startup.
      if (bridge.pendingCount > 0) {
        retrySync = true;
        unawaited(refresh());
      }
    }
  }

  Future<void> run(Future<void> Function() task) async {
    if (working) return;
    setState(() {
      working = true;
      error = '';
    });
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  void go(RenditionsRoute next) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      route = next;
      error = '';
      search = '';
    });
  }

  Future<void> select(RenditionData item) => run(() async {
    final epoch = generation;
    final result = await bridge.command('select', {'localId': item.localId});
    if (!mounted || epoch != generation) return;
    final saved = RenditionData(jsonMap(result['current']));
    if (saved.localId != item.localId) {
      throw const RenditionCommandException(
        'IDENTITY_CHANGED',
        'No se pudo abrir la misma rendición.',
      );
    }
    selected = saved;
    go(saved.readOnly ? RenditionsRoute.presented : RenditionsRoute.draft);
  });
  void saved(RenditionData item) {
    selected = item;
    go(item.readOnly ? RenditionsRoute.presented : RenditionsRoute.draft);
  }

  void newRendition() {
    editing = null;
    go(RenditionsRoute.editor);
  }

  final Map<String, VoidCallback> _dockCommands = <String, VoidCallback>{};

  /// Publishes the actions of the current route to the host dock. Only
  /// semantic state crosses the channel; no rendition data is sent.
  void _syncDockContext() {
    if (!mounted) return;
    final actions = <DockAction>[];
    final commands = <String, VoidCallback>{};
    void add(String id, String label, String icon, VoidCallback? onRun,
        {bool selected = false}) {
      final command = 'renditions.$id';
      final enabled = onRun != null && !working && !refreshing;
      actions.add(DockAction(id, label, icon, command,
          enabled: enabled, selected: selected, priority: (actions.length + 1) * 10));
      if (onRun != null && enabled) commands[command] = onRun;
    }

    if (bridge.calicataPickerDocument.isNotEmpty) {
      add('back', 'Volver', 'system.back', back);
    } else {
      switch (route) {
        case RenditionsRoute.editor:
          add('back', 'Volver', 'system.back', back);
          add('location', 'Ubicación', 'map.location',
              () => editorKey.currentState?.openLocation());
          add('save', 'Guardar borrador', 'action.save',
              editorKey.currentState?.canSave == true
                  ? () => editorKey.currentState?.save()
                  : null);
        case RenditionsRoute.expense:
          final ready = expenseKey.currentState?.busy != true;
          add('back', 'Volver', 'system.back', back);
          add('attach', 'Adjuntar', 'documents.upload',
              ready ? () => expenseKey.currentState?.attach() : null);
          add('smart', 'Smart Fill', 'action.edit',
              ready ? () => expenseKey.currentState?.smartFill() : null);
          add('save', 'Guardar gasto', 'action.save',
              ready ? () => expenseKey.currentState?.save() : null);
        case RenditionsRoute.draft:
          add('back', 'Volver', 'system.back', back);
          add('expense', 'Nuevo gasto', 'action.add',
              editable ? () => editExpense() : null);
          add('supports', 'Sustentos', 'documents.file', () {
            final target = supportsKey.currentContext;
            if (target != null) Scrollable.ensureVisible(target);
          });
          add('present', 'Presentar', 'system.forward',
              editable ? () => go(RenditionsRoute.presentConfirm) : null);
        case RenditionsRoute.presentConfirm:
          add('back', 'Volver', 'system.back', back);
          add('present', 'Confirmar presentación', 'system.forward',
              preflight == null ? () => unawaited(present()) : null);
        case RenditionsRoute.presented:
        case RenditionsRoute.receivedDetail:
          add('back', 'Volver', 'system.back', back);
          add('documents', 'Documents', 'nav.documents', () {
            unawaited(run(() async {
              await bridge.command('globalAction', {'action': 'documents'});
            }));
          });
          add('pdf', 'PDF', 'documents.file', () => unawaited(exportSnapshot('pdf')));
          add('xlsx', 'Excel', 'action.export', () => unawaited(exportSnapshot('xlsx')));
        default:
          add('summary', 'Resumen', 'nav.renditions', () => go(RenditionsRoute.home),
              selected: route == RenditionsRoute.home);
          add('received', 'Recibidas', 'documents.download',
              () => unawaited(loadReceived()),
              selected: route == RenditionsRoute.received);
          add('new', 'Nueva rendición', 'action.add', newRendition);
          if (route == RenditionsRoute.home || route == RenditionsRoute.received) {
            add('search', 'Buscar', 'action.search', () => unawaited(openSearch()));
          }
      }
    }

    _dockCommands
      ..clear()
      ..addAll(commands);
    DockContextClient.instance.publish(
      'renditions',
      'renditions/${route.name}',
      actions,
      (command) => _dockCommands[command]?.call(),
    );
  }

  void editExpense([ExpenseData? item]) {
    if (!editable) return;
    expense = item;
    go(RenditionsRoute.expense);
  }

  Future<void> deleteItem([ExpenseData? item]) async {
    final r = current;
    if (!editable || r == null) return;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(item == null ? '¿Eliminar este borrador?' : '¿Eliminar este gasto?'),
      content: Text(item == null ? 'Se quitarán la rendición borrador y sus gastos.' : 'Esta acción quitará el gasto de la rendición.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar'))],
    ));
    if (confirmed != true || !mounted || !editable || current?.localId != r.localId) return;
    await run(() async {
      await bridge.command(item == null ? 'deleteDraft' : 'deleteExpense', {
        'localId': r.localId, if (item != null) 'expenseLocalId': item.localId,
      });
      if (!mounted) return;
      if (item == null) { selected = null; go(RenditionsRoute.home); }
    });
  }

  void back() {
    if (bridge.calicataPickerDocument.isNotEmpty) {
      unawaited(bridge.command('calicataProjectPicked', {
        'documentId': bridge.calicataPickerDocument, 'selection': <String, dynamic>{},
      }).catchError((Object e) { if (mounted) setState(() => error = e.toString()); return <String, dynamic>{}; }));
      return;
    }
    if (working ||
        editorKey.currentState?.saving == true ||
        expenseKey.currentState?.busy == true) {
      return;
    }
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    if (route == RenditionsRoute.editor &&
        editorKey.currentState?.back() == true) {
      return;
    }
    switch (route) {
      case RenditionsRoute.home:
        unawaited(
          run(() async {
            await bridge.command('globalAction', {'action': 'home'});
          }),
        );
      case RenditionsRoute.expense:
        go(RenditionsRoute.draft);
      case RenditionsRoute.presentConfirm:
        go(RenditionsRoute.draft);
      case RenditionsRoute.editor:
        go(editing == null ? RenditionsRoute.home : RenditionsRoute.draft);
      case RenditionsRoute.receivedDetail:
        snapshot = null;
        go(RenditionsRoute.received);
        unawaited(
          run(() async {
            await bridge.command('receivedClose');
          }),
        );
      default:
        selected = null;
        go(RenditionsRoute.home);
        unawaited(
          run(() async {
            await bridge.command('closeDetail');
          }),
        );
    }
  }

  Future<void> loadReceived({bool fromRefresh = false}) => run(() async {
    if (!fromRefresh) go(RenditionsRoute.received);
    final epoch = generation;
    final rows = <ReceivedRendition>[];
    final ids = <String>{};
    JsonMap cursor = {};
    while (mounted && epoch == generation) {
      final response = await bridge.command('receivedList', cursor);
      if (!mounted || epoch != generation) return;
      final page = jsonRows(
        response['rows'],
      ).map(ReceivedRendition.new).toList();
      for (final row in page) {
        if (!ids.add(row.id)) {
          throw const RenditionCommandException(
            'REPEATED_PAGE',
            'El servidor repitió una página.',
          );
        }
        rows.add(row);
      }
      if (page.length < 200) break;
      cursor = {
        'afterSubmittedAt': page.last.submitted,
        'afterId': page.last.id,
      };
    }
    if (mounted && epoch == generation) setState(() => received = rows);
  });
  Future<void> openReceived(ReceivedRendition row) => run(() async {
    final epoch = generation;
    final result = await bridge.command('receivedQuery', row.identity);
    if (!mounted || epoch != generation) return;
    final rows = jsonRows(result['rows']);
    if (rows.length != 1 || textField(rows.single, 'rendition_id') != row.id) {
      throw const RenditionCommandException(
        'SNAPSHOT_MISSING',
        'No se confirmó la versión presentada.',
      );
    }
    snapshot = ReceivedRendition(rows.single);
    notes = [];
    activity = [];
    go(RenditionsRoute.receivedDetail);
    await administration();
  });
  Future<void> administration() async {
    final row = snapshot;
    if (row == null) return;
    final n = await bridge.command('receivedNotes', row.identity);
    if (!mounted || snapshot != row) return;
    notes = jsonRows(n['rows']);
    final a = await bridge.command('receivedActivity', row.identity);
    if (mounted && snapshot == row) {
      setState(() => activity = jsonRows(a['rows']));
    }
  }

  Future<void> exportSnapshot(String format) => run(() async {
    final result = await bridge.command(
      snapshot == null ? 'ownerExport' : 'receivedExport',
      {if (snapshot != null) ...snapshot!.identity, 'format': format},
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Archivo: ${result['output']}')));
    }
  });
  String? get preflight {
    final r = current;
    if (r == null || r.readOnly) return 'Sólo se puede presentar un borrador.';
    if (!RenditionEditorState(baseline: r).valid) {
      return 'Completa el período, proyectos y ubicación documental.';
    }
    if (expenses.isEmpty) return 'Agrega al menos un gasto.';
    if (r.hasConflict) return 'Resuelve el conflicto antes de presentar.';
    final period = RenditionEditorState(baseline: r);
    if (expenses.any(
      (e) =>
          !period.includesExpenseDate(e.date) ||
          !r.projectIds.contains(e.projectId),
    )) {
      return 'Revisa las fechas y proyectos de los gastos.';
    }
    return null;
  }

  Future<void> present() => run(() async {
    final blocker = preflight;
    if (blocker != null) {
      throw RenditionCommandException('PRESENT_BLOCKED', blocker);
    }
    await bridge.command('present');
    if (mounted && current?.readOnly == true) {
      go(RenditionsRoute.presented);
    } else if (mounted) {
      throw const RenditionCommandException(
        'PRESENT_PENDING',
        'Espera la confirmación del servidor antes de considerar presentada la rendición.',
      );
    }
  });
  @override
  void dispose() {
    DockContextClient.instance.clear('renditions');
    retryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    bridge.removeListener(changed);
    if (widget.bridge == null) bridge.dispose();
    queryLayout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncDockContext());
    return _buildContent(context);
  }

  Widget _buildContent(BuildContext context) => Theme(
    data: renditionTheme(),
    child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back();
      },
      child: RenditionsShell(
        child: Column(
          children: [
            if (loading || working || bridge.busy)
              const LinearProgressIndicator(minHeight: 2),
            if (syncFeedback.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 6),
              child: Semantics(liveRegion: true, child: Text(syncFeedback, style: const TextStyle(fontSize: 12)))),
            if (!refreshing && (error.isNotEmpty || (syncFeedback.isEmpty && bridge.lastError.isNotEmpty)))
              Padding(
                padding: const EdgeInsets.all(12),
                child: NothingNotice(
                  error.isNotEmpty ? error : bridge.lastError,
                ),
              ),
            // Navegación interna: fade + desplazamiento corto. Solo se monta la
            // vista actual (los editores usan GlobalKey; nunca dos a la vez).
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOutCubic,
                layoutBuilder: (current, previous) =>
                    current ?? const SizedBox.shrink(),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: AnimatedBuilder(
                    animation: animation,
                    child: child,
                    builder: (context, inner) => Transform.translate(
                      offset: Offset(0, 14 * (1 - animation.value)),
                      child: inner,
                    ),
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey<String>(bridge.calicataPickerDocument.isNotEmpty
                      ? 'picker:${bridge.calicataPickerDocument}'
                      : route.name),
                  child: content(),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget content() {
    if (bridge.calicataPickerDocument.isNotEmpty) {
      final document = bridge.calicataPickerDocument;
      Future<void> finish(JsonMap selection) async {
        try {
          await bridge.command('calicataProjectPicked', {
            'documentId': document, 'selection': selection,
          });
        } catch (e) { if (mounted) setState(() => error = e.toString()); }
      }
      return RenditionEditor(
        key: ValueKey('calicata-project:$document'), bridge: bridge,
        projectSelectionOnly: true, onProjectSelected: (s) => unawaited(finish(s)),
        onSaved: (_) {}, onBack: () => unawaited(finish({})), onChanged: editorChanged,
      );
    }
    switch (route) {
      case RenditionsRoute.editor:
        return RenditionEditor(
          key: editorKey,
          bridge: bridge,
          rendition: editing,
          onSaved: saved,
          onBack: back,
          onChanged: editorChanged,
        );
      case RenditionsRoute.expense:
        return ExpenseEditor(
          key: expenseKey,
          bridge: bridge,
          rendition: current!,
          expense: expense,
          onBack: back,
          onSaved: () => go(RenditionsRoute.draft),
          onChanged: editorChanged,
          onExistingExpense: (item) {
            // Leave the unsaved intention in autosave and mount a fresh editor.
            go(RenditionsRoute.draft);
            WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) editExpense(item); });
          },
        );
      case RenditionsRoute.draft:
      case RenditionsRoute.presented:
        return detail();
      case RenditionsRoute.presentConfirm:
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      physics: const AlwaysScrollableScrollPhysics(),
          children: [
            NothingHeading('Presentar rendición', current!.code, onBack: back),
            metrics(),
            NothingNotice(
              preflight ??
                  'Al presentar, se sincronizarán los cambios y se generará una versión inmutable. La edición quedará bloqueada tras la confirmación del servidor.',
            ),
            FilledButton(
              onPressed: working || preflight != null
                  ? null
                  : () => unawaited(present()),
              child: const Text('Presentar rendición'),
            ),
          ],
        );
      case RenditionsRoute.received:
        return RefreshIndicator(onRefresh: refresh, child: receivedHome());
      case RenditionsRoute.receivedDetail:
        return ReceivedQuery(
          key: queryKey,
          rendition: snapshot!,
          notes: notes,
          activity: activity,
          layout: queryLayout,
          palette: const RenditionsPalette(false),
          search: '',
          adminLoading: working,
          adminError: error,
          onAdminRetry: () => unawaited(run(administration)),
          onNote: (body, id) async {
            await bridge.command('receivedAddNote', {
              ...snapshot!.identity,
              'body': body,
              'noteRequestId': id,
            });
            await administration();
          },
          onAttachment: (a) => unawaited(
            run(
              () => bridge.openSnapshotAttachment(
                snapshot!.identity,
                textField(a, 'id'),
              ),
            ),
          ),
        );
      default:
        return RefreshIndicator(onRefresh: refresh, child: home());
    }
  }

  Widget home() {
    final rows =
        bridge.renditions
            .where(
              (r) => '${r.code} ${r.primaryProjectName} ${r.status}'
                  .toLowerCase()
                  .contains(search.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const NothingHeading(
          'Rendiciones',
          'Gestiona y registra tus gastos de comisión.',
        ),
        NothingMetrics(
          values: [
            (
              'Borradores',
              '${bridge.renditions.where((r) => !r.readOnly).length}',
            ),
            (
              'Presentadas',
              '${bridge.renditions.where((r) => r.readOnly).length}',
            ),
          ],
        ),
        if (bridge.pendingCount > 0)
          NothingNotice(
            '${bridge.pendingCount} operaciones pendientes de sincronización.',
          ),
        const NothingSection('Mis rendiciones'),
        if (search.isNotEmpty) searchChip(),
        const SizedBox(height: 12),
        if (loading && rows.isEmpty) const NothingSkeletonRows(count: 4),
        if (!loading && rows.isEmpty)
          const NothingNotice('No hay rendiciones para mostrar.'),
        for (final r in rows)
          NothingCard(
            onTap: () => unawaited(select(r)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.code,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    NothingStatus(r.status, solid: r.readOnly),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  r.primaryProjectName.isEmpty
                      ? projectName(r.primaryProjectId)
                      : r.primaryProjectName,
                ),
                Text(
                  '${r.expenseCount} gastos · PEN ${r.totalPen.toStringAsFixed(2)} · USD ${r.totalUsd.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  '${receivedDate(r.periodStart)} — ${receivedDate(r.periodEnd)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: RenditionTokens.secondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String projectName(String id) => textField(bridge.project(id) ?? {}, 'name');
  Widget quick(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) => NothingCard(
    onTap: onTap,
    child: Row(
      children: [
        Icon(icon, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: RenditionTokens.secondary,
                ),
              ),
            ],
          ),
        ),
        const Icon(LucideIcons.chevronRight, size: 18),
      ],
    ),
  );
  Widget metrics() => NothingMetrics(
    financial: true,
    values: [
      ('Total declarado PEN', 'S/ ${current!.totalPen.toStringAsFixed(2)}'),
      ('Total declarado USD', 'USD ${current!.totalUsd.toStringAsFixed(2)}'),
      ('Número de gastos', '${current!.expenseCount}'),
      ('Pendientes de revisión', '${intField(current!.raw, 'pendingCount')}'),
    ],
  );
  Widget detail() {
    final r = current!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        NothingHeading(
          r.code,
          '${r.primaryProjectName.isEmpty ? projectName(r.primaryProjectId) : r.primaryProjectName}\n${receivedDate(r.periodStart)} — ${receivedDate(r.periodEnd)}',
          onBack: back,
          trailing: NothingStatus(r.status, solid: r.readOnly),
        ),
        if (r.readOnly)
          Text(
            'VERSIÓN ${r.versionNumber}',
            style: const TextStyle(letterSpacing: 1.5),
          ),
        if (!r.readOnly)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: editable
                  ? () {
                      editing = r;
                      go(RenditionsRoute.editor);
                    }
                  : null,
              icon: const Icon(LucideIcons.pencil, size: 16),
              label: const Text('Editar período y proyectos'),
            ),
          ),
        metrics(),
        Text(
          (r.raw['pendingCount'] as num? ?? 0) > 0
              ? '${r.raw['pendingCount']} operación(es) pendiente(s)'
              : NothingStatus.label(r.syncState),
          style: const TextStyle(
            fontSize: 11,
            color: RenditionTokens.secondary,
          ),
        ),
        NothingSection(
          'Gastos',
          action: r.readOnly
              ? null
              : TextButton.icon(
                  onPressed: editable ? () => editExpense() : null,
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('Agregar gasto'),
                ),
        ),
        if (textField(r.raw, 'syncError').isNotEmpty)
          NothingNotice(renditionUserMessage(textField(r.raw, 'syncError'))),
        if (expenses.isEmpty)
          const NothingNotice('Todavía no hay gastos guardados.'),
        for (final e in expenses)
          NothingCard(
            onTap: editable ? () => editExpense(e) : null,
            child: Row(
              children: [
                const Icon(LucideIcons.receipt, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.categoryName.isEmpty ? e.concept : e.categoryName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${receivedDate(e.date)} · ${e.paymentMethodName.isEmpty ? e.paymentMethodCode : e.paymentMethodName}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        '${e.supportTypeName.isEmpty ? e.supportTypeCode : e.supportTypeName} ${e.supportNumber}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: RenditionTokens.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${e.currency} ${e.amount.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    NothingStatus(e.reviewStatus),
                    if (!r.readOnly) IconButton(
                      tooltip: 'Eliminar gasto',
                      onPressed: editable ? () => unawaited(deleteItem(e)) : null,
                      icon: const Icon(LucideIcons.trash2, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
        NothingSection('Sustentos guardados', key: supportsKey),
        if (bridge.attachments.isEmpty)
          const NothingNotice(
            'Adjunta los sustentos desde el gasto al que pertenecen.',
          ),
        for (final a in bridge.attachments)
          NothingCard(
            onTap: a.id.isEmpty || a.phase != 'READY'
                ? null
                : () => unawaited(
                    run(() async {
                      await bridge.openAttachment(a.id);
                    }),
                  ),
            child: Row(
              children: [
                const Icon(LucideIcons.paperclip),
                const SizedBox(width: 12),
                Expanded(child: Text(a.fileName)),
                NothingStatus(a.phase == 'ERROR' || a.phase == 'NEEDS_RECONCILIATION' ? 'Error al subir' : a.phase),
                if (!r.readOnly && (a.phase == 'ERROR' || a.phase == 'NEEDS_RECONCILIATION'))
                  TextButton(onPressed: bridge.busy ? null : () => unawaited(run(() async { await bridge.command('sync'); })), child: const Text('Reintentar')),
              ],
            ),
          ),
        NothingNotice(
          r.readOnly
              ? 'Esta rendición fue presentada. Su edición está bloqueada.'
              : 'Puedes agregar y editar gastos antes de presentar la rendición.',
        ),
        if (!r.readOnly) TextButton.icon(
          onPressed: editable ? () => unawaited(deleteItem()) : null,
          icon: const Icon(LucideIcons.trash2, size: 18), label: const Text('Eliminar borrador'),
        ),
      ],
    );
  }

  Widget receivedHome() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const NothingHeading(
        'Rendiciones recibidas',
        'Versiones presentadas y recepción administrativa.',
      ),
      NothingStat('Presentadas', '${received.length}'),
      NothingStat('Recibidas', '${received.where((r) => r.received).length}'),
      NothingStat(
        'Pendientes de recepción',
        '${received.where((r) => !r.received).length}',
      ),
      if (search.isNotEmpty) searchChip(),
      const SizedBox(height: 12),
      for (final r in ReceivedFilter().apply(received, search))
        NothingCard(
          onTap: () => unawaited(openReceived(r)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.code,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 6),
              NothingStatus(r.reception, solid: r.received),
              Text('${r.status} · V${r.version}'),
              Text(r.owner),
              Text(r.project),
              Text(
                '${r.expenseCount} gastos · PEN ${r.pen.toStringAsFixed(2)} · USD ${r.usd.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                receivedDate(r.submitted, time: true),
                style: const TextStyle(
                  fontSize: 12,
                  color: RenditionTokens.secondary,
                ),
              ),
            ],
          ),
        ),
      if (working && received.isEmpty) const NothingSkeletonRows(count: 4),
      if (!working && received.isEmpty)
        const NothingNotice('No hay versiones recibidas para mostrar.'),
    ],
  );
}
