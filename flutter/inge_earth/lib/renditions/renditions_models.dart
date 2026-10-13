typedef JsonMap = Map<String, dynamic>;

JsonMap jsonMap(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : <String, dynamic>{};

List<JsonMap> jsonRows(Object? value) => value is List
    ? value.map(jsonMap).where((row) => row.isNotEmpty).toList(growable: false)
    : const <JsonMap>[];

Object? field(JsonMap map, String camel, [String? snake]) {
  final direct = map[camel];
  if (direct != null) return direct;
  return snake == null ? null : map[snake];
}

String textField(JsonMap map, String camel, [String? snake]) =>
    field(map, camel, snake)?.toString() ?? '';

double numberField(JsonMap map, String camel, [String? snake]) =>
    switch (field(map, camel, snake)) {
      final num value => value.toDouble(),
      final Object value => double.tryParse(value.toString()) ?? 0,
      _ => 0,
    };

int intField(JsonMap map, String camel, [String? snake]) =>
    switch (field(map, camel, snake)) {
      final num value => value.toInt(),
      final Object value => int.tryParse(value.toString()) ?? 0,
      _ => 0,
    };

List<String> stringList(Object? value) => value is List
    ? value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList()
    : const <String>[];

String compactDate(String value) {
  if (value.length >= 10) return value.substring(0, 10);
  return value.isEmpty ? 'Sin fecha' : value;
}

class RenditionData {
  const RenditionData(this.raw);

  final JsonMap raw;

  String get localId => textField(raw, 'localId');
  String get remoteId => textField(raw, 'remoteId', 'rendition_id').isNotEmpty
      ? textField(raw, 'remoteId', 'rendition_id')
      : textField(raw, 'id');
  String get code {
    final value = textField(raw, 'visibleCode', 'visible_code');
    return value.isEmpty ? 'Borrador local' : value;
  }

  String get status {
    final value = textField(raw, 'status').toUpperCase();
    return value.isEmpty ? 'BORRADOR' : value;
  }

  String get syncState {
    final value = textField(raw, 'syncState', 'sync_state').toUpperCase();
    return value.isEmpty ? 'LOCAL_ONLY' : value;
  }

  String get periodStart => textField(raw, 'periodStart', 'period_start');
  String get periodEnd => textField(raw, 'periodEnd', 'period_end');
  String get updatedAt => textField(raw, 'updatedAt', 'updated_at');
  String get createdAt => textField(raw, 'createdAt', 'created_at');
  String get baseCurrency => textField(raw, 'baseCurrency', 'base_currency');
  String get reference {
    for (final value in <String>[
      textField(raw, 'reference', 'reference_code'),
      textField(raw, 'shortReference', 'short_reference'),
      textField(raw, 'renditionReference', 'rendition_reference'),
    ]) {
      if (value.isNotEmpty) return value;
    }
    final id = remoteId;
    final separator = id.indexOf('-');
    return separator > 0 ? id.substring(0, separator) : '';
  }

  String get primaryProjectId =>
      textField(raw, 'primaryProjectId', 'primary_project_id');
  String get primaryProjectName =>
      textField(raw, 'primaryProjectName', 'primary_project_name');
  List<String> get projectIds =>
      stringList(field(raw, 'projectIds', 'project_ids'));
  String get documentParentNodeId =>
      textField(raw, 'documentParentNodeId', 'document_parent_node_id');
  String get documentParentNodeName =>
      textField(raw, 'documentParentNodeName', 'document_parent_node_name');
  String get spaceId => textField(raw, 'spaceId', 'space_id');
  int get rowVersion => intField(raw, 'rowVersion', 'row_version');
  int get versionNumber => intField(raw, 'versionNumber', 'version_number');
  double get totalPen => numberField(raw, 'totalPen', 'total_pen');
  double get totalUsd => numberField(raw, 'totalUsd', 'total_usd');
  int get expenseCount => intField(raw, 'expenseCount', 'expense_count');
  bool get readOnly => status != 'BORRADOR';
  bool get hasConflict =>
      syncState == 'CONFLICT' || syncState == 'NEEDS_RECONCILIATION';
}

class ExpenseData {
  const ExpenseData(this.raw);

  final JsonMap raw;

  String get localId => textField(raw, 'localId');
  String get remoteId => textField(raw, 'remoteId', 'expense_id');
  String get projectId => textField(raw, 'projectId', 'project_id');
  String get date => textField(raw, 'expenseDate', 'expense_date');
  String get categoryCode => textField(raw, 'categoryCode', 'category_code');
  String get categoryName => textField(raw, 'categoryName', 'category_name');
  String get concept => textField(raw, 'concept');
  String get beneficiary => textField(raw, 'beneficiary');
  String get paymentMethodCode =>
      textField(raw, 'paymentMethodCode', 'payment_method_code');
  String get paymentMethodName =>
      textField(raw, 'paymentMethodName', 'payment_method_name');
  String get paymentMethodDetail =>
      textField(raw, 'paymentMethodDetail', 'payment_method_detail');
  String get supportTypeCode =>
      textField(raw, 'supportTypeCode', 'support_type_code');
  String get supportTypeName =>
      textField(raw, 'supportTypeName', 'support_type_name');
  String get supportNumber => textField(raw, 'supportNumber', 'support_number');
  String get supportDetail => textField(raw, 'supportDetail', 'support_detail');
  String get currency => textField(raw, 'currencyCode', 'currency_code').isEmpty
      ? 'PEN'
      : textField(raw, 'currencyCode', 'currency_code');
  double get amount => numberField(raw, 'amount');
  String get justification => textField(raw, 'justification');
  String get reviewStatus {
    final value = textField(raw, 'reviewStatus', 'review_status');
    return value.isEmpty ? 'PENDIENTE' : value;
  }

  String get syncState {
    final value = textField(raw, 'syncState', 'sync_state');
    return value.isEmpty ? 'LOCAL_ONLY' : value;
  }

  int get rowVersion => intField(raw, 'rowVersion', 'row_version');
  bool get archived => raw['archived'] == true;
}

class AttachmentData {
  const AttachmentData(this.raw);

  final JsonMap raw;

  String get id {
    for (final key in <String>[
      'remoteId',
      'attachment_id',
      'attachmentId',
      'id',
    ]) {
      final value = raw[key]?.toString() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String get localId => textField(raw, 'localId');
  String get expenseId => textField(raw, 'expenseId', 'expense_id');
  String get fileName => textField(raw, 'fileName', 'file_name').isEmpty
      ? 'Sustento'
      : textField(raw, 'fileName', 'file_name');
  String get mimeType => textField(raw, 'mimeType', 'mime_type');
  String get documentNumber =>
      textField(raw, 'documentNumber', 'document_number');
  String get expenseNumber => textField(raw, 'expenseNumber', 'expense_number');
  int get sizeBytes => intField(raw, 'sizeBytes', 'size_bytes');
  String get phase => textField(raw, 'phase', 'status').isEmpty
      ? 'READY'
      : textField(raw, 'phase', 'status');
  int get rowVersion => intField(raw, 'rowVersion', 'row_version');
}

class VersionData {
  const VersionData(this.raw);
  final JsonMap raw;

  int get number => intField(raw, 'versionNumber', 'version_number');
  String get status => textField(raw, 'status');
  String get createdAt => textField(raw, 'createdAt', 'created_at');
  int get expenses => intField(raw, 'expenseCount', 'expense_count');
  double get totalPen => numberField(raw, 'totalPen', 'total_pen');
  double get totalUsd => numberField(raw, 'totalUsd', 'total_usd');
  String get hash => textField(raw, 'snapshotHash', 'snapshot_hash').isNotEmpty
      ? textField(raw, 'snapshotHash', 'snapshot_hash')
      : textField(raw, 'snapshot_sha256');
}
