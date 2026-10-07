import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'renditions_models.dart';

String renditionUserMessage(String message, [String code = '']) {
  if (message.isEmpty && code.isEmpty) return '';
  final detail = '$code $message';
  if (RegExp(r'AUTH_REQUIRED|PROFILE_NOT_ACTIVE').hasMatch(detail)) {
    return 'Inicia sesión con una cuenta activa para continuar.';
  }
  if (RegExp(r'NETWORK|TIMEOUT|OFFLINE|SocketException|Failed host', caseSensitive: false).hasMatch(detail)) {
    return 'Sin conexión. Tus cambios se conservan para reintentar.';
  }
  if (RegExp(r'CONFLICT|ROW_VERSION|CAS mismatch').hasMatch(detail)) {
    return 'Hay cambios pendientes de revisar. Actualiza la rendición antes de continuar.';
  }
  if (message.isEmpty || RegExp(r'[A-Z]{2,}_[A-Z_]+|HTTP|PostgREST|Exception|SQL|\{|\b[0-9a-f]{8}-[0-9a-f-]{27,}\b').hasMatch(message)) {
    return 'No se pudo completar este cambio. Intenta nuevamente.';
  }
  return message;
}

class RenditionCommandException implements Exception {
  const RenditionCommandException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => renditionUserMessage(message, code);
}

class RenditionsBridge extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('inge.renditions/host');

  final Map<String, Completer<JsonMap>> _commands =
      <String, Completer<JsonMap>>{};
  int _sequence = 0;
  bool _disposed = false;
  String _lastStatePayload = '';
  int receivedSessionRevision = 0;

  bool busy = false;
  String connectionState = 'UNKNOWN';
  String contractMode = 'V02';
  String lastError = '';
  int pendingCount = 0;
  JsonMap editorDrafts = {};
  String selectedLocalId = '';
  String documentTargetId = '';
  int documentOpenRevision = 0;
  String calicataPickerDocument = '';
  List<RenditionData> renditions = const <RenditionData>[];
  List<JsonMap> projects = const <JsonMap>[];
  List<JsonMap> catalogs = const <JsonMap>[];
  RenditionData? current;
  JsonMap remoteCurrent = <String, dynamic>{};
  List<ExpenseData> expenses = const <ExpenseData>[];
  JsonMap summary = <String, dynamic>{};
  List<VersionData> versions = const <VersionData>[];
  List<AttachmentData> attachments = const <AttachmentData>[];
  JsonMap documentWorkspace = <String, dynamic>{};
  JsonMap documentSpace = <String, dynamic>{};
  List<JsonMap> documentFolders = const <JsonMap>[];
  JsonMap documentCapabilities = <String, dynamic>{};

  Future<void> initialize() async {
    _channel.setMethodCallHandler(_handleHostCall);
    await command('bootstrap');
  }

  Future<dynamic> _handleHostCall(MethodCall call) async {
    if (call.method != 'renditionEvent' || call.arguments is! String) return;
    try {
      final payload = call.arguments as String;
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return;
      final event = jsonMap(decoded);
      switch (event['type']?.toString()) {
        case 'receivedReset':
          receivedSessionRevision++;
          _notify();
          break;
        case 'state':
          if (payload == _lastStatePayload) return;
          _lastStatePayload = payload;
          _applyState(event);
          break;
        case 'commandResult':
          _completeCommand(event);
          break;
        case 'attachmentAccess':
          await _openAttachment(jsonMap(event['result']));
          break;
      }
    } catch (error) {
      lastError = 'No se pudo actualizar la pantalla. Intenta nuevamente.';
      _notify();
    }
  }

  void _applyState(JsonMap state) {
    calicataPickerDocument = textField(state, 'calicataPickerDocument');
    busy = state['busy'] == true;
    connectionState = state['connectionState']?.toString() ?? 'UNKNOWN';
    contractMode = state['contractMode']?.toString() ?? contractMode;
    lastError = renditionUserMessage(state['lastError']?.toString() ?? '');
    pendingCount = (state['pendingCount'] as num?)?.toInt() ?? 0;
    editorDrafts = jsonMap(state['editorDrafts']);
    selectedLocalId = state['selectedLocalId']?.toString() ?? '';
    documentTargetId = state['documentTargetId']?.toString() ?? '';
    documentOpenRevision =
        (state['documentOpenRevision'] as num?)?.toInt() ?? 0;
    renditions = jsonRows(
      state['renditions'],
    ).map(RenditionData.new).toList(growable: false);
    projects = jsonRows(state['projects']);
    catalogs = jsonRows(state['catalogs']);
    final currentRow = jsonMap(state['current']);
    current = currentRow.isEmpty ? null : RenditionData(currentRow);
    remoteCurrent = jsonMap(state['remoteCurrent']);
    expenses = jsonRows(state['expenses'])
        .map(ExpenseData.new)
        .where((expense) => !expense.archived)
        .toList(growable: false);
    summary = jsonMap(state['summary']);
    versions = jsonRows(
      state['versions'],
    ).map(VersionData.new).toList(growable: false);

    final combined = <AttachmentData>[];
    final known = <String>{};
    for (final row in <JsonMap>[
      ...jsonRows(state['localAttachments']),
      ...jsonRows(state['attachments']),
    ]) {
      final attachment = AttachmentData(row);
      final identity = attachment.id.isNotEmpty
          ? attachment.id
          : '${attachment.localId}:${attachment.fileName}';
      if (known.add(identity)) combined.add(attachment);
    }
    attachments = combined;
    documentWorkspace = jsonMap(state['documentWorkspace']);
    documentSpace = jsonMap(state['documentSpace']);
    documentFolders = jsonRows(state['documentFolders']);
    documentCapabilities = jsonMap(state['documentCapabilities']);
    _notify();
  }

  void _completeCommand(JsonMap event) {
    final requestId = event['requestId']?.toString() ?? '';
    final completer = _commands.remove(requestId);
    if (event['ok'] == true) {
      completer?.complete(jsonMap(event['result']));
      return;
    }
    final code = event['code']?.toString() ?? 'RENDITION_ERROR';
    final message = event['message']?.toString() ?? '';
    // The awaiting screen owns this failure. Keep it out of other screens.
    if (completer != null) {
      completer.completeError(RenditionCommandException(code, message));
    }
    _notify();
  }

  Future<bool> _openAttachment(JsonMap result) async {
    String url = '';
    for (final key in <String>[
      'signedUrl',
      'signed_url',
      'url',
      'download_url',
    ]) {
      final candidate = result[key]?.toString() ?? '';
      if (candidate.isNotEmpty) {
        url = candidate;
        break;
      }
    }
    if (url.isEmpty) {
      lastError = 'El backend no devolvió una URL privada de acceso.';
      _notify();
      return false;
    }
    final opened = await _channel.invokeMethod<bool>('openUri', url) == true;
    if (!opened) {
      lastError = 'Android no pudo abrir el sustento.';
      _notify();
    }
    return opened;
  }

  Future<void> openSnapshotAttachment(
    JsonMap identity,
    String attachmentId,
  ) async {
    final result = await command('receivedAttachment', {
      ...identity,
      'attachmentId': attachmentId,
    });
    final rows = jsonRows(result['rows']);
    if (rows.length != 1) {
      throw const RenditionCommandException(
        'ATTACHMENT_ACCESS_INVALID',
        'No se recibió acceso al sustento.',
      );
    }
    if (!await _openAttachment(rows.single)) {
      throw RenditionCommandException('ATTACHMENT_OPEN_FAILED', lastError);
    }
  }

  Future<void> openAttachment(String attachmentId) async {
    final result = await command('attachmentAccess', {
      'attachmentId': attachmentId,
    });
    final rows = jsonRows(result['rows']);
    if (rows.length != 1 || !await _openAttachment(rows.single)) {
      throw RenditionCommandException('ATTACHMENT_OPEN_FAILED', lastError);
    }
  }

  Future<JsonMap> command(
    String operation, [
    JsonMap arguments = const <String, dynamic>{},
  ]) async {
    final requestId = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    final completer = Completer<JsonMap>();
    _commands[requestId] = completer;
    final payload = jsonEncode(<String, Object>{
      'requestId': requestId,
      'operation': operation,
      'arguments': arguments,
    });
    try {
      await _channel.invokeMethod<void>('submit', payload);
    } on PlatformException catch (error) {
      _commands.remove(requestId);
      throw RenditionCommandException(
        error.code,
        error.message ?? 'El host Android rechazó la operación.',
      );
    }
    return completer.future.timeout(
      Duration(seconds: operation == 'coreAnalyze' ? 620 : operation == 'sync' ? 180 : 45),
      onTimeout: () {
        _commands.remove(requestId);
        throw const RenditionCommandException(
          'RENDITION_TIMEOUT',
          'La operación no respondió dentro del tiempo esperado.',
        );
      },
    );
  }

  Future<JsonMap?> pickAttachment() async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        'pickAttachment',
      );
      return value == null ? null : Map<String, dynamic>.from(value);
    } on PlatformException catch (error) {
      throw RenditionCommandException(
        error.code,
        error.message ?? 'No se pudo seleccionar el sustento.',
      );
    }
  }

  List<JsonMap> catalogsOf(String kind) {
    final wanted = kind.toUpperCase();
    return catalogs
        .where((row) {
          final type = textField(row, 'catalogType', 'catalog_type').isNotEmpty
              ? textField(row, 'catalogType', 'catalog_type')
              : textField(row, 'type');
          return type.toUpperCase().contains(wanted);
        })
        .toList(growable: false);
  }

  JsonMap? project(String id) {
    for (final row in projects) {
      if (textField(row, 'id') == id) return row;
    }
    return null;
  }

  double localTotal(String currency) => expenses
      .where((expense) => expense.currency == currency)
      .fold<double>(0, (sum, expense) => sum + expense.amount);

  void clearError() {
    if (lastError.isEmpty) return;
    lastError = '';
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
    for (final completer in _commands.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const RenditionCommandException(
            'BRIDGE_CLOSED',
            'La pantalla de rendiciones se cerró.',
          ),
        );
      }
    }
    _commands.clear();
    super.dispose();
  }
}
