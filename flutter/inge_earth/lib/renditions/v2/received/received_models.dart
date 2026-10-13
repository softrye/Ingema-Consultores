import '../../renditions_models.dart';

String receivedText(JsonMap row, String key) => row[key]?.toString() ?? '';
String receivedDate(String value, {bool time = false}) {
  final date = DateTime.tryParse(value);
  if (date == null) return value.isEmpty ? '—' : value;
  final d = time ? date.toLocal() : date;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}'
      '${time ? ' · ${two(d.hour)}:${two(d.minute)}' : ''}';
}

String backendDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class ReceivedRendition {
  ReceivedRendition(JsonMap value) : raw = Map.unmodifiable(value);
  final JsonMap raw;
  String get id => receivedText(raw, 'rendition_id');
  String get code => receivedText(raw, 'visible_code');
  String get owner => receivedText(raw, 'owner_name');
  String get project => [
    receivedText(raw, 'primary_project_code'),
    receivedText(raw, 'primary_project_name'),
  ].where((s) => s.isNotEmpty).join(' - ');
  String get start => receivedText(raw, 'period_start');
  String get end => receivedText(raw, 'period_end');
  String get submitted => receivedText(raw, 'submitted_at');
  String get receivedAt => receivedText(raw, 'received_at');
  bool get received => receivedAt.isNotEmpty;
  String get reception => received ? 'RECIBIDA' : 'PENDIENTE DE RECEPCIÓN';
  String get status => receivedText(raw, 'status');
  int get version => intField(raw, 'version_number');
  String get versionId => receivedText(raw, 'rendition_version_id');
  String get hash => receivedText(raw, 'snapshot_hash');
  int get expenseCount => intField(raw, 'expense_count');
  double get pen => numberField(raw, 'total_declared_pen');
  double get usd => numberField(raw, 'total_declared_usd');
  JsonMap get identity => {
    'renditionId': id,
    'versionId': versionId,
    'versionNumber': version,
    'hash': hash,
  };
  JsonMap get snapshot => jsonMap(raw['snapshot_payload']);
  List<JsonMap> get expenses => jsonRows(snapshot['expenses']);
  List<JsonMap> get attachments => jsonRows(snapshot['attachments']);
}

enum ReceivedOrder { newest, oldest, code }

class ReceivedFilter {
  void copyFrom(ReceivedFilter other) {
    code = other.code;
    owner = other.owner;
    project = other.project;
    periodFrom = other.periodFrom;
    periodTo = other.periodTo;
    submittedFrom = other.submittedFrom;
    submittedTo = other.submittedTo;
    order = other.order;
  }

  String code = '', owner = '', project = '';
  String periodFrom = '', periodTo = '', submittedFrom = '', submittedTo = '';
  ReceivedOrder order = ReceivedOrder.newest;

  void clear() {
    code = owner = project = periodFrom = periodTo = submittedFrom =
        submittedTo = '';
    order = ReceivedOrder.newest;
  }

  bool get active =>
      [
        code,
        owner,
        project,
        periodFrom,
        periodTo,
        submittedFrom,
        submittedTo,
      ].any((s) => s.isNotEmpty) ||
      order != ReceivedOrder.newest;
  bool get valid =>
      (periodFrom.isEmpty ||
          periodTo.isEmpty ||
          periodFrom.compareTo(periodTo) <= 0) &&
      (submittedFrom.isEmpty ||
          submittedTo.isEmpty ||
          submittedFrom.compareTo(submittedTo) <= 0);

  List<ReceivedRendition> apply(List<ReceivedRendition> rows, String search) {
    bool contains(String text, String query) =>
        text.toLowerCase().contains(query.trim().toLowerCase());
    final output = rows.where((r) {
      final local = DateTime.tryParse(r.submitted)?.toLocal();
      final day = local == null ? '' : backendDate(local);
      return contains('${r.code} ${r.owner} ${r.project}', search) &&
          contains(r.code, code) &&
          contains(r.owner, owner) &&
          contains(r.project, project) &&
          (periodFrom.isEmpty || r.end.compareTo(periodFrom) >= 0) &&
          (periodTo.isEmpty || r.start.compareTo(periodTo) <= 0) &&
          (submittedFrom.isEmpty || day.compareTo(submittedFrom) >= 0) &&
          (submittedTo.isEmpty ||
              (day.isNotEmpty && day.compareTo(submittedTo) <= 0));
    }).toList();
    output.sort((a, b) {
      int result;
      if (order == ReceivedOrder.code) {
        result = a.code.compareTo(b.code);
      } else {
        final at = DateTime.tryParse(a.submitted),
            bt = DateTime.tryParse(b.submitted);
        result = at != null && bt != null
            ? at.compareTo(bt)
            : a.submitted.compareTo(b.submitted);
        if (order == ReceivedOrder.newest) result = -result;
      }
      return result == 0 ? a.id.compareTo(b.id) : result;
    });
    return output;
  }
}
