// Reglas y contratos de comandos de Rendiciones extraídos de la interfaz
// Flutter eliminada (Visual Zero, 2026-10-10). Dart puro: sin widgets, sin
// BuildContext. Cada función reproduce exactamente la regla que antes vivía
// en renditions_root.dart, rendition_editor.dart, expense_editor.dart y
// received_query.dart (v2/v3); los comandos se ejecutan en C++
// (RenditionFlutterBridge::submit).
import 'dart:math';

import 'renditions_bridge.dart' show RenditionCommandException;
import 'renditions_models.dart';
import 'v2/received/received_models.dart';
import 'v3/state/rendition_editor_state.dart';
import 'v3/state/smart_fill.dart';

// ---------------------------------------------------------------- Recibidas

/// Tamaño de página del servidor para `receivedList`.
const receivedPageSize = 200;

/// Búsqueda textual sobre todas las columnas no nulas de una fila.
bool receivedRowMatches(JsonMap row, String query) =>
    query.trim().isEmpty ||
    row.values
        .where((v) => v != null)
        .join(' ')
        .toLowerCase()
        .contains(query.trim().toLowerCase());

/// Recorre `receivedList` página a página (cursor submitted_at + id) y
/// rechaza páginas repetidas. Devuelve null si [alive] deja de ser cierto
/// (la consulta fue reemplazada por otra).
Future<List<ReceivedRendition>?> loadAllReceived(
  Future<JsonMap> Function(JsonMap cursor) fetch, {
  bool Function()? alive,
}) async {
  bool live() => alive == null || alive();
  final rows = <ReceivedRendition>[];
  final ids = <String>{};
  JsonMap cursor = {};
  while (live()) {
    final response = await fetch(cursor);
    if (!live()) return null;
    final page = jsonRows(response['rows']).map(ReceivedRendition.new).toList();
    for (final row in page) {
      if (!ids.add(row.id)) {
        throw const RenditionCommandException(
          'REPEATED_PAGE',
          'El servidor repitió una página.',
        );
      }
      rows.add(row);
    }
    if (page.length < receivedPageSize) break;
    cursor = {
      'afterSubmittedAt': page.last.submitted,
      'afterId': page.last.id,
    };
  }
  return live() ? rows : null;
}

/// `receivedQuery` debe devolver exactamente la versión presentada pedida.
ReceivedRendition confirmReceivedSnapshot(JsonMap result, ReceivedRendition row) {
  final rows = jsonRows(result['rows']);
  if (rows.length != 1 || textField(rows.single, 'rendition_id') != row.id) {
    throw const RenditionCommandException(
      'SNAPSHOT_MISSING',
      'No se confirmó la versión presentada.',
    );
  }
  return ReceivedRendition(rows.single);
}

/// UUID v4 (Random.secure) para solicitudes idempotentes.
String newRequestUuid([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Una nota reintentada con el mismo cuerpo conserva su id de solicitud; un
/// cuerpo distinto (o sin id previo) recibe uno nuevo.
String noteRequestId(String body, String lastBody, String lastRequestId,
        {String Function()? uuid}) =>
    lastBody != body || lastRequestId.isEmpty
        ? (uuid ?? newRequestUuid)()
        : lastRequestId;

JsonMap receivedAddNoteArgs(JsonMap identity, String body, String requestId) => {
      ...identity,
      'body': body,
      'noteRequestId': requestId,
    };

/// Exportación: snapshot recibido (con identidad) o rendición propia.
({String command, JsonMap args}) exportCommand(JsonMap? snapshotIdentity, String format) => (
      command: snapshotIdentity == null ? 'ownerExport' : 'receivedExport',
      args: {...?snapshotIdentity, 'format': format},
    );

// ------------------------------------------------------------- Rendiciones

/// Gastos vigentes (no archivados) de una rendición.
List<ExpenseData> activeExpenses(RenditionData? rendition) => rendition == null
    ? []
    : jsonRows(rendition.raw['expenses'])
        .map(ExpenseData.new)
        .where((e) => !e.archived)
        .toList();

/// Edición permitida sobre la rendición actual.
bool renditionEditable(RenditionData? current, {required bool busy}) =>
    current != null &&
    !current.readOnly &&
    !current.hasConflict &&
    current.syncState != 'SYNCING' &&
    !busy;

/// Bloqueo previo a `present`; null = se puede presentar.
String? presentPreflight(RenditionData? r, List<ExpenseData> expenses) {
  if (r == null || r.readOnly) return 'Sólo se puede presentar un borrador.';
  if (!RenditionEditorState(baseline: r).valid) {
    return 'Completa el período, proyectos y ubicación documental.';
  }
  if (expenses.isEmpty) return 'Agrega al menos un gasto.';
  if (r.hasConflict) return 'Resuelve el conflicto antes de presentar.';
  final period = RenditionEditorState(baseline: r);
  if (expenses.any(
    (e) => !period.includesExpenseDate(e.date) || !r.projectIds.contains(e.projectId),
  )) {
    return 'Revisa las fechas y proyectos de los gastos.';
  }
  return null;
}

/// `select` debe abrir la misma rendición local.
RenditionData confirmSelected(JsonMap result, String localId) {
  final saved = RenditionData(jsonMap(result['current']));
  if (saved.localId != localId) {
    throw const RenditionCommandException(
      'IDENTITY_CHANGED',
      'No se pudo abrir la misma rendición.',
    );
  }
  return saved;
}

/// `create`/`update` deben confirmar identidad (la misma si ya existía).
RenditionData confirmSaved(JsonMap result, RenditionData? baseline) {
  final saved = RenditionData(jsonMap(result['current']));
  if (saved.localId.isEmpty ||
      (baseline != null && saved.localId != baseline.localId)) {
    throw const RenditionCommandException(
      'IDENTITY_MISMATCH',
      'No se pudo confirmar la identidad guardada.',
    );
  }
  return saved;
}

String headerSaveCommand(RenditionData? baseline) =>
    baseline == null ? 'create' : 'update';

String headerDraftKey(String? renditionLocalId) =>
    'header:${renditionLocalId ?? 'new'}';

({String command, JsonMap args}) deleteCommand(String renditionLocalId, String? expenseLocalId) => (
      command: expenseLocalId == null ? 'deleteDraft' : 'deleteExpense',
      args: {
        'localId': renditionLocalId,
        'expenseLocalId': ?expenseLocalId,
      },
    );

/// Espacio documental del proyecto (`projectWorkspace`).
String workspaceSpaceId(JsonMap workspace) {
  final space = textField(workspace, 'spaceId', 'space_id');
  if (space.isEmpty) {
    throw const RenditionCommandException(
      'NO_WORKSPACE',
      'El proyecto no tiene un espacio documental disponible.',
    );
  }
  return space;
}

/// `folderCapabilities`: sólo una carpeta ACTIVA del mismo espacio que
/// admite hijos puede ser destino documental.
void validateFolderCapabilities(JsonMap result, String spaceId, Object? nodeId) {
  if (result['node_kind'] != 'FOLDER' ||
      result['lifecycle'] != 'ACTIVE' ||
      result['can_accept_child'] != true ||
      result['space_id'] != spaceId ||
      result['node_id'] != nodeId) {
    throw const RenditionCommandException(
      'INVALID_FOLDER',
      'Esta carpeta no está activa o no admite documentos. Elige otra ubicación.',
    );
  }
}

String folderPath(List<JsonMap> path, String folderName) =>
    [...path.map((r) => textField(r, 'name')), folderName].join('/');

/// Padre al subir un nivel en la navegación de carpetas ('' = raíz).
String parentFolderId(List<JsonMap> path) =>
    path.length < 2 ? '' : textField(path[path.length - 2], 'id');

/// Fallo de red (reintento diferido) frente a error de datos.
bool isNetworkFailure(String connectionState, Object error) =>
    connectionState == 'OFFLINE' ||
    RegExp(r'NETWORK|TIMEOUT|OFFLINE|HOST.*FOUND|CONNECTION|CONEXI',
            caseSensitive: false)
        .hasMatch(error.toString());

// ------------------------------------------------------------------ Gastos

const expenseTextFields = <String>[
  'amount', 'concept', 'beneficiary', 'ruc', 'subtotal', 'igv',
  'paymentMethodDetail', 'supportNumber', 'supportDetail', 'justification',
];

String expenseDraftKey(String renditionLocalId, String? expenseLocalId) =>
    'expense:$renditionLocalId:${expenseLocalId ?? 'new'}';

String newExpenseIntentId([DateTime? now]) =>
    'expense-${(now ?? DateTime.now()).microsecondsSinceEpoch}';

/// Valores normalizados del gasto (importe con punto decimal).
JsonMap expenseValues({
  required String intentId,
  required String projectId,
  required String expenseDate,
  required String categoryCode,
  required String currencyCode,
  required String paymentMethodCode,
  required String supportTypeCode,
  required Map<String, String> fields,
}) => {
      'clientIntentId': intentId, 'projectId': projectId, 'expenseDate': expenseDate,
      'categoryCode': categoryCode, 'currencyCode': currencyCode,
      'paymentMethodCode': paymentMethodCode, 'supportTypeCode': supportTypeCode,
      for (final f in fields.entries)
        f.key: f.key == 'amount' ? f.value.replaceAll(',', '.') : f.value,
    };

/// Validación de un campo del gasto; null = válido.
String? expenseFieldError(String id, String? value,
    {required bool required, bool numeric = false}) {
  if (required && (value ?? '').trim().isEmpty) {
    return 'Campo obligatorio';
  }
  if (numeric) {
    if (!required && (value ?? '').trim().isEmpty) return null;
    final amount = double.tryParse((value ?? '').replaceAll(',', '.'));
    if (amount == null ||
        !amount.isFinite ||
        (required ? amount <= 0 : amount < 0) ||
        !RegExp(r'^\d+([.,]\d{1,2})?$').hasMatch(value ?? '')) {
      return 'Monto válido con hasta 2 decimales';
    }
  }
  if (['concept', 'justification'].contains(id) &&
      (value ?? '').trim().isNotEmpty &&
      !meaningfulExpenseText(value!)) {
    return 'Describe el gasto con palabras completas';
  }
  return null;
}

/// La fecha del gasto debe caer dentro del período de la rendición.
String? expenseDateError(RenditionData rendition, String date) =>
    RenditionEditorState(baseline: rendition).includesExpenseDate(date)
        ? null
        : 'La fecha del gasto debe estar dentro del período de la rendición.';

/// Posibles duplicados (sólo antes del primer guardado).
List<ExpenseData> duplicateExpenses(List<ExpenseData> expenses, String savedId,
        JsonMap values, List<JsonMap> pendingAttachments) =>
    expenses
        .where((e) =>
            e.localId != savedId &&
            similarExpense({...values, 'attachments': pendingAttachments}, e.raw))
        .toList();

/// Contexto de `coreAnalyze` para el análisis de comprobantes.
JsonMap coreAnalyzeArgs({
  required List<JsonMap> attachments,
  required String projectId,
  required String entityId,
  required String renditionLocalId,
  required JsonMap currentFields,
  required String periodStart,
  required String periodEnd,
  required List<JsonMap> categories,
  required List<JsonMap> supportTypes,
  required List<JsonMap> paymentMethods,
  required List<ExpenseData> history,
  required String savedId,
}) => {
      'attachments': attachments,
      'context': {
        'project_id': projectId, 'entity_id': entityId,
        'entity': {'rendition_id': renditionLocalId},
        'current_fields': currentFields,
        'rules': {
          'period_start': periodStart,
          'period_end': periodEnd,
          'categories': categories,
          'support_types': supportTypes,
          'payment_methods': paymentMethods,
        },
        'related_history':
            history.where((e) => e.localId != savedId).take(20).map((e) => e.raw).toList(),
      },
    };

/// Propuestas del análisis aplicables automáticamente: válidas, sin
/// conflicto y con confianza >= 0,70.
List<SuggestedExpensePatch> acceptedReceiptPatches(JsonMap result) =>
    jsonRows(result['fields'])
        .where((r) =>
            r['conflict'] != true &&
            r['valid'] == true &&
            ((r['confidence'] as num?) ?? 0) >= .70)
        .map((r) => SuggestedExpensePatch(
              field: textField(r, 'field'),
              proposedValue: r['value'] ?? '',
              confidence: (r['confidence'] as num?)?.toDouble() ?? 0,
              sourceAttachment: (r['sources'] as List? ?? []).join(', '),
            ))
        .toList();

/// Un gasto nuevo con fecha/moneda aún en su valor por defecto puede ser
/// sobrescrito por el análisis.
bool untouchedDefaultField(String field,
        {required bool isNew,
        required String date,
        required String periodStart,
        required String currency}) =>
    isNew &&
    ((field == 'expenseDate' && date == periodStart) ||
        (field == 'currencyCode' && currency == 'PEN'));

/// Argumentos de `saveExpense` (sincroniza al confirmar).
JsonMap saveExpenseArgs({
  required String renditionLocalId,
  required String savedId,
  int? expectedRowVersion,
  required JsonMap values,
  required Map<String, JsonMap> receiptEvidence,
}) => {
      'localId': renditionLocalId,
      'expenseLocalId': savedId,
      if (savedId.isNotEmpty && expectedRowVersion != null)
        'expectedExpenseRowVersion': expectedRowVersion,
      'expense': {...values, 'receiptEvidence': receiptEvidence},
      'synchronize': true,
    };

/// `saveExpense` debe confirmar la identidad local del gasto.
String confirmSavedExpenseId(JsonMap result) {
  final id = textField(result, 'localId');
  if (id.isEmpty) {
    throw const RenditionCommandException(
      'EXPENSE_ID_MISSING',
      'No se confirmó la identidad del gasto.',
    );
  }
  return id;
}

/// `attachSupport` idempotente por intención + URI local del sustento.
JsonMap attachSupportArgs({
  required String renditionLocalId,
  required String expenseLocalId,
  required String intentId,
  required JsonMap attachment,
  required String supportTypeCode,
  required String documentNumber,
}) => {
      'localId': renditionLocalId,
      'expenseLocalId': expenseLocalId,
      'attachment': {
        ...attachment,
        'clientIntentId': '$intentId:${attachment['localUri']}',
        'supportTypeCode': supportTypeCode,
        'documentNumber': documentNumber,
      },
    };
