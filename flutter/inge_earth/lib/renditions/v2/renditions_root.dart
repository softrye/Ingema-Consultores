import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../renditions_bridge.dart';
import '../renditions_models.dart';
import 'renditions_dashboard.dart';
import 'rendition_detail.dart';
import 'widgets/dashboard_widgets.dart';
import 'received/received_models.dart';
import 'received/received_metro_board.dart';
import 'received/received_filter_sheet.dart';
import 'received/received_tray.dart';
import 'received/received_query.dart';

enum _RenditionsRoute { dashboard, received, query, detail }

/// User-facing V2 entrypoint. Business operations remain owned by the native
/// Renditions bridge.
class RenditionsRootV2 extends StatefulWidget {
  const RenditionsRootV2({
    required this.dark,
    required this.onGlobalAction,
    super.key,
  });

  final bool dark;
  final Future<void> Function(String action) onGlobalAction;

  @override
  State<RenditionsRootV2> createState() => _RenditionsRootV2State();
}

class _RenditionsRootV2State extends State<RenditionsRootV2> {
  late final RenditionsBridge _bridge;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _loading = true;
  bool _searchOpen = false;
  String _bootstrapError = '';
  _RenditionsRoute _route = _RenditionsRoute.dashboard;
  RenditionData? _selected;
  bool _selecting = false;
  final _filter = ReceivedFilter();
  final _receivedLayout = ReceivedMetroLayout({
    'summary': MetroSize.wide,
    'renditions': MetroSize.large,
  });
  final _queryLayout = ReceivedMetroLayout({
    'snapshot': MetroSize.large,
    'expenses': MetroSize.large,
    'supports': MetroSize.wide,
    'admin': MetroSize.large,
  });
  final _queryKey = GlobalKey<ReceivedQueryState>();
  List<ReceivedRendition> _received = [];
  ReceivedRendition? _snapshot;
  List<JsonMap> _notes = [], _activity = [];
  bool _receivedLoading = false,
      _queryLoading = false,
      _adminLoading = false,
      _exporting = false;
  String _receivedError = '', _adminError = '';
  int _generation = 0, _sessionRevision = 0;

  @override
  void initState() {
    super.initState();
    _bridge = RenditionsBridge()..addListener(_onBridgeChanged);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _bootstrapError = '';
      });
    }
    try {
      await _bridge.initialize();
      await _bridge.command('receivedClose');
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'InGe+ Renditions V2',
          context: ErrorDescription('while bootstrapping the native bridge'),
        ),
      );
      if (mounted) _bootstrapError = _readableError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _readableError(Object error) => error is RenditionCommandException
      ? error.message
      : 'No se pudo cargar Rendiciones.';

  void _onBridgeChanged() {
    if (_sessionRevision != _bridge.receivedSessionRevision) {
      _sessionRevision = _bridge.receivedSessionRevision;
      _generation++;
      _received = [];
      _snapshot = null;
      _selected = null;
      _notes = [];
      _activity = [];
      _receivedLoading = _queryLoading = _adminLoading = false;
      _route = _RenditionsRoute.dashboard;
      _searchController.clear();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        _setRoute(_RenditionsRoute.dashboard);
      }
    }
    if (mounted) setState(() {});
  }

  void _setRoute(_RenditionsRoute route) {
    _searchFocus.unfocus();
    _searchController.clear();
    setState(() {
      _route = route;
      _searchOpen = false;
    });
  }

  Future<void> _openReceived() async {
    if (_receivedLoading) return;
    _generation++;
    _setRoute(_RenditionsRoute.received);
    await _loadReceived();
  }

  Future<void> _loadReceived() async {
    if (_receivedLoading) return;
    final generation = _generation;
    setState(() {
      _receivedLoading = true;
      _receivedError = '';
    });
    final loaded = <ReceivedRendition>[];
    final ids = <String>{};
    var cursor = <String, dynamic>{};
    try {
      while (mounted && generation == _generation) {
        final result = await _bridge.command('receivedList', cursor);
        if (!mounted || generation != _generation) return;
        final page = jsonRows(
          result['rows'],
        ).map(ReceivedRendition.new).toList();
        for (final row in page) {
          if (!ids.add(row.id)) {
            throw const RenditionCommandException(
              'INVALID_PAGE',
              'El servidor repitió una página de rendiciones.',
            );
          }
          loaded.add(row);
        }
        if (page.length < 200) break;
        cursor = {
          'afterSubmittedAt': page.last.submitted,
          'afterId': page.last.id,
        };
      }
      if (mounted && generation == _generation) {
        setState(() => _received = loaded);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _receivedError = _readableError(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _receivedLoading = false);
      }
    }
  }

  Future<void> _openQuery(ReceivedRendition row) async {
    if (_queryLoading) return;
    final generation = ++_generation;
    _receivedLoading = false;
    _snapshot = null;
    _notes = [];
    _activity = [];
    _adminError = '';
    _receivedError = '';
    _queryLoading = true;
    _setRoute(_RenditionsRoute.query);
    try {
      final result = await _bridge.command('receivedQuery', row.identity);
      if (!mounted || generation != _generation) return;
      final values = jsonRows(result['rows']);
      if (values.length != 1) {
        throw const RenditionCommandException(
          'SNAPSHOT_MISSING',
          'El servidor no devolvió un snapshot único.',
        );
      }
      setState(() => _snapshot = ReceivedRendition(values.single));
      await _loadAdministration();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _receivedError = _readableError(error));
        _setRoute(_RenditionsRoute.received);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _queryLoading = false);
      }
    }
  }

  Future<void> _loadAdministration() async {
    final selected = _snapshot;
    if (selected == null || _adminLoading) return;
    final generation = _generation;
    setState(() {
      _adminLoading = true;
      _adminError = '';
    });
    try {
      final notes = await _bridge.command('receivedNotes', selected.identity);
      if (!mounted || generation != _generation) return;
      setState(
        () => _notes = jsonRows(notes['rows'])
            .where(
              (n) =>
                  n['rendition_version_id'] == null ||
                  n['rendition_version_id'] == selected.versionId,
            )
            .toList(),
      );
      final activity = await _bridge.command(
        'receivedActivity',
        selected.identity,
      );
      if (!mounted || generation != _generation) return;
      setState(() => _activity = jsonRows(activity['rows']));
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _adminError = _readableError(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _adminLoading = false);
      }
    }
  }

  Future<void> _addNote(String body, String requestId) async {
    final selected = _snapshot;
    if (selected == null) {
      throw const RenditionCommandException(
        'QUERY_CLOSED',
        'La consulta se cerró.',
      );
    }
    await _bridge.command('receivedAddNote', {
      ...selected.identity,
      'body': body,
      'noteRequestId': requestId,
    });
    if (mounted && _snapshot == selected) await _loadAdministration();
  }

  Future<void> _filters() async {
    _searchFocus.unfocus();
    final refresh = await showReceivedFilters(
      context,
      _filter,
      RenditionsPalette(widget.dark),
    );
    if (!mounted) return;
    setState(() {});
    if (refresh == true) await _loadReceived();
  }

  Future<void> _export() async {
    final selected = _snapshot;
    if (selected == null || _exporting) return;
    _searchFocus.unfocus();
    final format = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Exportar snapshot'),
        children: [
          ListTile(
            leading: const Icon(LucideIcons.fileText),
            title: const Text('PDF'),
            onTap: () => Navigator.pop(dialogContext, 'pdf'),
          ),
          ListTile(
            leading: const Icon(LucideIcons.sheet),
            title: const Text('Excel'),
            onTap: () => Navigator.pop(dialogContext, 'xlsx'),
          ),
        ],
      ),
    );
    if (format == null || !mounted || _snapshot != selected) return;
    setState(() => _exporting = true);
    try {
      final result = await _bridge.command('receivedExport', {
        ...selected.identity,
        'format': format,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              MediaQuery.viewPaddingOf(context).bottom + 148,
            ),
            content: Text(
              (result['warning']?.toString() ?? '').isNotEmpty
                  ? '${result['warning']}\n${result['output']}'
                  : 'Archivo guardado: ${result['output']}',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_readableError(error))));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _bootstrapError = '');
    try {
      await _bridge.command('refresh');
    } catch (error) {
      if (mounted) setState(() => _bootstrapError = _readableError(error));
    }
  }

  Future<void> _selectRendition(RenditionData rendition) async {
    if (rendition.localId.isEmpty || _selecting) return;
    _selecting = true;
    final generation = _generation;
    try {
      final result = await _bridge.command('select', <String, dynamic>{
        'localId': rendition.localId,
      });
      if (!mounted || generation != _generation) return;
      final selected = RenditionData(jsonMap(result['current']));
      if (selected.localId != rendition.localId) {
        throw const RenditionCommandException(
          'SELECTION_CHANGED',
          'No se pudo recuperar la rendición seleccionada.',
        );
      }
      _selected = selected;
      _setRoute(_RenditionsRoute.detail);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _bootstrapError = _readableError(error));
      }
    } finally {
      _selecting = false;
    }
  }

  void _closeDetail() {
    _selected = null;
    _setRoute(_RenditionsRoute.dashboard);
    unawaited(
      _bridge.command('closeDetail').catchError((Object error) {
        if (mounted) setState(() => _bootstrapError = _readableError(error));
        return <String, dynamic>{};
      }),
    );
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    _searchController.clear();
    setState(() => _searchOpen = false);
  }

  Future<void> _handleAction(String key) async {
    try {
      if (key == 'received') {
        await _openReceived();
        return;
      }
      if (key == 'renditions') {
        if (_route == _RenditionsRoute.detail) {
          _closeDetail();
          return;
        }
        _leaveQuery();
        _setRoute(_RenditionsRoute.dashboard);
        return;
      }
      if (key == 'sync') {
        await _bridge.command('sync');
        if (mounted && _route == _RenditionsRoute.received) {
          await _loadReceived();
        }
        return;
      }
      if (key == 'expenses' || key == 'supports') {
        _queryKey.currentState?.focusTile(key);
        return;
      }
      if (key == 'export') {
        await _export();
        return;
      }
      if (key == 'context' && _snapshot != null) {
        _searchFocus.unfocus();
        await showSnapshotContext(
          context,
          _snapshot!,
          _notes,
          _activity,
          RenditionsPalette(widget.dark),
        );
        return;
      }
      await _bridge.command('globalAction', {'action': key});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La acción no está disponible en este momento.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _handleBack(bool didPop) {
    if (didPop) return;
    if (_route == _RenditionsRoute.detail) {
      _closeDetail();
      return;
    }
    if (FocusManager.instance.primaryFocus?.hasFocus == true &&
        MediaQuery.viewInsetsOf(context).bottom > 0) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    final layout = _route == _RenditionsRoute.query
        ? _queryLayout
        : _receivedLayout;
    if (layout.editing) {
      layout.edit(false);
      return;
    }
    if (_searchOpen) {
      _closeSearch();
      return;
    }
    if (_route == _RenditionsRoute.query) {
      _leaveQuery();
      _setRoute(_RenditionsRoute.received);
      return;
    }
    if (_route == _RenditionsRoute.received) {
      _leaveQuery();
      _setRoute(_RenditionsRoute.dashboard);
      return;
    }
    unawaited(_handleAction('home'));
  }

  void _leaveQuery() {
    _generation++;
    _snapshot = null;
    _notes = [];
    _activity = [];
    _receivedLoading = _queryLoading = _adminLoading = false;
    unawaited(
      _bridge.command('receivedClose').catchError((Object error) {
        if (mounted) setState(() => _receivedError = _readableError(error));
        return <String, dynamic>{};
      }),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _receivedLayout.dispose();
    _queryLayout.dispose();
    _bridge
      ..removeListener(_onBridgeChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = RenditionsPalette(widget.dark);
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final searchBottom = safeBottom + 8;
    final collapsedSearchLeft = ((screenWidth - 128) / 2)
        .clamp(8.0, double.infinity)
        .toDouble();
    final error = _bootstrapError.isNotEmpty
        ? _bootstrapError
        : _bridge.lastError;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _handleBack(didPop),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: palette.background,
        body: Stack(
          children: <Widget>[
            Positioned.fill(
              bottom: _route != _RenditionsRoute.dashboard && keyboard > 0
                  ? keyboard + 68
                  : safeBottom,
              child: _route == _RenditionsRoute.received
                  ? ReceivedTray(
                      rows: _received,
                      filteredRows: _filter.apply(
                        _received,
                        _searchController.text,
                      ),
                      loading: _receivedLoading,
                      error: _receivedError,
                      layout: _receivedLayout,
                      palette: palette,
                      onSelect: (row) => unawaited(_openQuery(row)),
                      onRetry: () => unawaited(_loadReceived()),
                    )
                  : _route == _RenditionsRoute.query
                  ? (_snapshot == null
                        ? const Center(child: CircularProgressIndicator())
                        : ReceivedQuery(
                            key: _queryKey,
                            rendition: _snapshot!,
                            notes: _notes,
                            activity: _activity,
                            layout: _queryLayout,
                            palette: palette,
                            search: _searchController.text,
                            onNote: _addNote,
                            adminLoading: _adminLoading,
                            adminError: _adminError,
                            onAdminRetry: () =>
                                unawaited(_loadAdministration()),
                            onAttachment: (a) => unawaited(
                              _bridge
                                  .openSnapshotAttachment(
                                    _snapshot!.identity,
                                    a['id']?.toString() ?? '',
                                  )
                                  .catchError((Object error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(_readableError(error)),
                                        ),
                                      );
                                    }
                                  }),
                            ),
                          ))
                  : _route == _RenditionsRoute.detail && _selected != null
                  ? RenditionDetailV2(
                      bridge: _bridge,
                      selected: _selected!,
                      palette: palette,
                      onBack: _closeDetail,
                    )
                  : RenditionsDashboard(
                      bridge: _bridge,
                      palette: palette,
                      loading: _loading,
                      error: error,
                      query: _searchController.text,
                      onRetry: _refresh,
                      onRenditionTap: _selectRendition,
                      onNew: () => unawaited(_handleAction('create')),
                      onReceived: () =>
                          unawaited(_handleAction('received')),
                    ),
            ),
            if (_exporting)
              Positioned(
                top: MediaQuery.viewPaddingOf(context).top,
                left: 0,
                right: 0,
                child: const LinearProgressIndicator(minHeight: 2),
              ),
            if (_route == _RenditionsRoute.received ||
                _route == _RenditionsRoute.query)
              Positioned(
                left: 16,
                right: 16,
                bottom: keyboard > 0 ? keyboard + 12 : searchBottom,
                child: ReceivedSearchControl(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  palette: palette,
                  onChanged: (_) => setState(() {}),
                  query: _route == _RenditionsRoute.query,
                  filtered: _filter.active,
                  onFilter: _route == _RenditionsRoute.received
                      ? () => unawaited(_filters())
                      : null,
                ),
              ),
            if (_route == _RenditionsRoute.dashboard)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                left: _searchOpen ? 16 : collapsedSearchLeft,
                right: _searchOpen ? 16 : null,
                bottom: keyboard > 0 ? keyboard + 12 : searchBottom,
                child: RenditionSearchAffordance(
                  palette: palette,
                  expanded: _searchOpen,
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onOpen: _openSearch,
                  onClose: _closeSearch,
                  onChanged: (_) => setState(() {}),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
