import '../../renditions_models.dart';

bool similarExpense(JsonMap candidate, JsonMap existing) {
  String normalized(Object? value) => (value ?? '').toString().trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  const keys = {
    'projectId': 'project_id', 'expenseDate': 'expense_date', 'categoryCode': 'category_code',
    'currencyCode': 'currency_code', 'concept': 'concept', 'beneficiary': 'beneficiary',
    'supportTypeCode': 'support_type_code', 'supportNumber': 'support_number',
  };
  if (existing['archived'] == true) return false;
  String field(JsonMap row, String camel, String snake) => normalized(row[camel] ?? row[snake]);
  Set<String> hashes(JsonMap row) => {
    for (final a in [row, ...jsonRows(row['attachments'])])
      for (final key in ['sha256', 'contentHash', 'content_hash', 'documentFingerprint', 'document_fingerprint'])
        if (normalized(a[key]).isNotEmpty) normalized(a[key]),
  };
  if (hashes(candidate).intersection(hashes(existing)).isNotEmpty) return true;
  final numberA = field(candidate, 'supportNumber', 'support_number').replaceAll(RegExp(r'[^a-z0-9]'), '');
  final numberB = field(existing, 'supportNumber', 'support_number').replaceAll(RegExp(r'[^a-z0-9]'), '');
  final amountA = double.tryParse(normalized(candidate['amount']).replaceAll(',', '.'));
  final amountB = double.tryParse(normalized(existing['amount']).replaceAll(',', '.'));
  final sameAmount = amountA != null && amountB != null && (amountA - amountB).abs() < .005;
  final rucA = normalized(candidate['ruc']), rucB = normalized(existing['ruc']);
  final typeA = field(candidate, 'supportTypeCode', 'support_type_code');
  final typeB = field(existing, 'supportTypeCode', 'support_type_code');
  if (numberA.isNotEmpty && numberA == numberB && sameAmount &&
      field(candidate, 'currencyCode', 'currency_code') == field(existing, 'currencyCode', 'currency_code') &&
      (rucA.isEmpty || rucB.isEmpty || rucA == rucB) &&
      (typeA.isEmpty || typeB.isEmpty || typeA == typeB) &&
      ((rucA.isNotEmpty && rucA == rucB) ||
        (field(candidate, 'expenseDate', 'expense_date').isNotEmpty &&
         field(candidate, 'expenseDate', 'expense_date') == field(existing, 'expenseDate', 'expense_date')))) {
    return true;
  }
  for (final entry in keys.entries) {
    if (normalized(candidate[entry.key]) != normalized(existing[entry.key] ?? existing[entry.value])) return false;
  }
  final a = double.tryParse(normalized(candidate['amount']).replaceAll(',', '.'));
  final b = double.tryParse(normalized(existing['amount']).replaceAll(',', '.'));
  return a != null && b != null && (a - b).abs() < 0.005;
}

/// Form state only. Persistence, monetary totals, CAS and transitions stay native.
class RenditionEditorState {
  RenditionEditorState({this.baseline}) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    start = baseline?.periodStart ?? today;
    end = baseline?.periodEnd ?? today;
    projects = [...?baseline?.projectIds];
    primary = baseline?.primaryProjectId ?? '';
    folder = baseline?.documentParentNodeId ?? '';
    folderName = baseline?.documentParentNodeName ?? '';
    space = baseline?.spaceId ?? '';
  }
  final RenditionData? baseline;
  late String start, end, primary, folder, folderName, space;
  late List<String> projects;
  int step = 0;
  static bool validDate(String value) {
    final date = DateTime.tryParse(value);
    return date != null && date.toIso8601String().substring(0, 10) == value;
  }

  bool get periodValid =>
      validDate(start) && validDate(end) && start.compareTo(end) <= 0;
  bool get projectsValid => projects.isNotEmpty && projects.contains(primary);
  bool get valid =>
      periodValid && projectsValid && folder.isNotEmpty && space.isNotEmpty;
  void setPrimary(String id) {
    if (!projects.contains(id) || primary == id) return;
    primary = id;
    folder = folderName = space = '';
  }

  void toggleProject(String id) {
    if (projects.contains(id)) {
      projects.remove(id);
      if (primary == id) {
        primary = projects.isEmpty ? '' : projects.first;
        folder = folderName = space = '';
      }
    } else {
      projects.add(id);
      if (primary.isEmpty) setPrimary(id);
    }
  }

  bool includesExpenseDate(String date) =>
      validDate(date) && date.compareTo(start) >= 0 && date.compareTo(end) <= 0;
  JsonMap get payload => {
    if (baseline != null) 'localId': baseline!.localId,
    if (baseline != null) 'expectedRowVersion': baseline!.rowVersion,
    'periodStart': start,
    'periodEnd': end,
    'projectIds': [...projects],
    'primaryProjectId': primary,
    'documentParentNodeId': folder,
    'spaceId': space,
    'synchronize': true,
  };
}
