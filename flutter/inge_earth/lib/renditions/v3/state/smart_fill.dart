import '../../renditions_models.dart';
import 'package:flutter/services.dart';

String receiptFieldLabel(String field) => const {
  'amount': 'monto', 'expenseDate': 'fecha', 'beneficiary': 'proveedor',
  'ruc': 'RUC', 'supportNumber': 'número de comprobante', 'concept': 'concepto',
  'categoryCode': 'categoría', 'paymentMethodCode': 'medio de pago',
  'supportTypeCode': 'tipo de sustento', 'currencyCode': 'moneda',
  'subtotal': 'subtotal', 'igv': 'IGV', 'justification': 'justificación',
}[field] ?? 'dato del comprobante';

String receiptIssueMessage(JsonMap issue) {
  switch (textField(issue, 'reason')) {
    case 'DATE_OUTSIDE_RENDITION_PERIOD':
      return 'El comprobante está fuera del período de esta rendición.';
    case 'PAYMENT_METHOD_UNKNOWN':
      return '¿Cómo pagaste?';
    case 'SEMANTIC_CONTENT_REQUIRED':
      return 'Completa ${receiptFieldLabel(textField(issue, 'field'))} con una descripción del gasto.';
    case 'TOTAL_COMPONENTS_MISMATCH':
      return 'El subtotal y el IGV no coinciden con el total. Revisa los importes del comprobante.';
    default:
      return 'Revisa ${receiptFieldLabel(textField(issue, 'field'))}; la evidencia no permite confirmarlo.';
  }
}

const coreUnavailableMessage = 'La revisión automática no está disponible. Puedes completar el gasto manualmente y reintentar después.';

/// One review, shared by remote extraction and on-device recognition.
class ReceiptReview {
  ReceiptReview(this.fields, this.issues, {this.unavailable = false});
  final List<JsonMap> fields, issues;
  final bool unavailable;

  factory ReceiptReview.fromResult(JsonMap result, String start, String end) {
    final fields = jsonRows(result['fields']);
    final byField = <String, JsonMap>{};
    for (final issue in jsonRows(result['validation'])) {
      byField[textField(issue, 'field')] = issue;
    }
    for (final row in fields) {
      final field = textField(row, 'field');
      final value = textField(row, 'value');
      if (field == 'expenseDate' && (value.compareTo(start) < 0 || value.compareTo(end) > 0)) {
        byField[field] = {'field': field, 'reason': 'DATE_OUTSIDE_RENDITION_PERIOD'};
      } else if (row['conflict'] == true || row['valid'] != true || row['requiresReview'] == true ||
          ((row['confidence'] as num?) ?? 0) < .90) {
        byField.putIfAbsent(field, () => {'field': field, 'reason': 'FIELD_REQUIRES_EVIDENCE'});
      }
    }
    return ReceiptReview(fields, byField.values.toList(), unavailable:
        (result['warnings'] as List? ?? []).any((v) => v.toString().startsWith('AI_UNAVAILABLE')));
  }

  static bool canAutofill(JsonMap row, Object? current, bool userEdited, {bool defaultValue = false}) =>
      !userEdited && row['valid'] == true && row['conflict'] != true &&
      row['requiresReview'] != true && ((row['confidence'] as num?) ?? 0) >= .90 &&
      (defaultValue || current == null || current.toString().isEmpty || current.toString() == row['value'].toString());
}

bool meaningfulExpenseText(String value) {
  final words = RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]{2,}').allMatches(value);
  final letters = words.map((m) => m.group(0)!.toLowerCase()).join();
  return words.length >= 2 && letters.split('').toSet().length >= 4;
}

class SuggestedExpensePatch {
  const SuggestedExpensePatch({
    required this.field,
    required this.proposedValue,
    required this.confidence,
    required this.sourceAttachment,
  });
  final String field, sourceAttachment;
  final Object proposedValue;
  final double confidence;
}

/// Receipt scanner donor separates acquisition/OCR from domain parsing.
/// The adapter never writes to the form or store; application requires consent.
abstract interface class ReceiptAnalysisAdapter {
  Future<List<SuggestedExpensePatch>> analyze(JsonMap attachment);
}

class LocalReceiptAnalysis implements ReceiptAnalysisAdapter {
  const LocalReceiptAnalysis();
  static const channel = MethodChannel('inge.renditions/host');
  @override
  Future<List<SuggestedExpensePatch>> analyze(JsonMap attachment) async {
    final nativeText = textField(attachment, 'nativeText', 'text');
    if (nativeText.isNotEmpty) return parseReceipt({'text': nativeText}, textField(attachment, 'localId'));
    final path = textField(attachment, 'localUri', 'local_uri');
    if (path.isEmpty) {
      throw StateError('Este sustento no tiene una imagen local.');
    }
    final result = await channel.invokeMapMethod<String, dynamic>(
      'analyzeReceipt',
      path,
    );
    return parseReceipt(
      jsonMap(result),
      textField(attachment, 'localId').isEmpty
          ? path
          : textField(attachment, 'localId'),
    );
  }
}

JsonMap localReceiptResult(List<SuggestedExpensePatch> patches) {
  final groups = <String, List<SuggestedExpensePatch>>{};
  for (final patch in patches) { groups.putIfAbsent(patch.field, () => []).add(patch); }
  return {
    'warnings': ['AI_UNAVAILABLE_LOCAL_READING'],
    'fields': [for (final entry in groups.entries) {
      'field': entry.key, 'value': entry.value.first.proposedValue,
      'confidence': entry.value.first.confidence,
      'valid': entry.value.map((p) => p.proposedValue.toString()).toSet().length == 1,
      'conflict': entry.value.map((p) => p.proposedValue.toString()).toSet().length > 1,
      'requiresReview': entry.value.first.confidence < .90,
      'sources': entry.value.map((p) => p.sourceAttachment).toList(),
    }],
    'validation': [if (!groups.containsKey('paymentMethodCode'))
      {'field': 'paymentMethodCode', 'reason': 'PAYMENT_METHOD_UNKNOWN'}],
  };
}

/// Conservative receipt parsing. Confidence is heuristic, never a save decision.
List<SuggestedExpensePatch> parseReceipt(JsonMap result, String source) {
  final patches = <SuggestedExpensePatch>[];
  final lines = jsonRows(result['lines']);
  final text = textField(result, 'text');
  void suggest(String field, Object value, double confidence) {
    patches.add(SuggestedExpensePatch(
      field: field,
      proposedValue: value,
      confidence: confidence,
      sourceAttachment: source,
    ));
  }

  final usable = lines.isEmpty
      ? text.split('\n').map((t) => <String, dynamic>{'text': t}).toList()
      : lines;
  for (var i = 0; i < usable.length; i++) {
    final row = usable[i];
    final confidence = row['confidence'];
    if (confidence is num && confidence < .65) continue;
    final line = textField(row, 'text').trim();
    final upper = line.toUpperCase();
    String? money(String raw) {
      final split = raw.length - 3;
      if (split < 1) return null;
      final value = '${raw.substring(0, split).replaceAll(RegExp(r'[.,]'), '')}.${raw.substring(split + 1)}';
      return double.tryParse(value) != null ? value : null;
    }
    for (final label in {'subtotal': r'(?:SUB\s*TOTAL|OP\.?\s*GRAVADA|VALOR\s+DE\s+VENTA)', 'igv': r'I\.?G\.?V\.?'}.entries) {
      final match = RegExp('${label.value}\\s*(?:18\\s*%)?\\s*[:=]?\\s*(?:S/\\.?|PEN|USD|US\\\$)?\\s*([0-9]+(?:[.,][0-9]{3})*[.,][0-9]{2})\\b', caseSensitive: false).firstMatch(line);
      if (match != null && money(match[1]!) != null) suggest(label.key, money(match[1]!)!, .95);
    }
    // Stop supplier extraction at buyer details.
    final issuer = usable.take(i + 1).map((r) => textField(r, 'text')).join('\n');
    final ruc = RegExp(r'\bR\.?U\.?C\.?\s*:?\s*(\d{11})\b', caseSensitive: false).firstMatch(line);
    if (ruc != null && !RegExp(r'CLIENTE|ADQUIRENTE|RECEPTOR|SE[ÑN]OR', caseSensitive: false).hasMatch(issuer)) {
      suggest('ruc', ruc[1]!, .95);
      if (i > 0) {
        final name = textField(usable[i - 1], 'text').trim();
        if (meaningfulExpenseText(name) && !RegExp(r'FACTURA|BOLETA|DIRECCI[ÓO]N|\d{4}', caseSensitive: false).hasMatch(name)) suggest('beneficiary', name, .95);
      }
    }
    if (RegExp(r'\bTOTAL\b').hasMatch(upper) &&
        !RegExp(r'SUB\s*TOTAL|IGV|IMPUESTO|VUELTO').hasMatch(upper)) {
      var amounts = RegExp(
        r'\d+(?:[.,]\d{3})*[.,]\d{2}\b',
      ).allMatches(line).toList();
      if (amounts.isEmpty && i + 1 < usable.length) {
        final next = usable[i + 1];
        if (next['confidence'] is! num || (next['confidence'] as num) >= .65) {
          amounts = RegExp(
            r'^\s*(?:S/\.?|USD|US\$|\$)?\s*(\d+(?:[.,]\d{3})*[.,]\d{2})\s*$',
          ).allMatches(textField(next, 'text')).toList();
        }
      }
      if (amounts.isNotEmpty) {
        final match = amounts.last;
        final raw = match.groupCount > 0 ? match.group(1)! : match.group(0)!;
        final split = raw.length - 3;
        final value =
            '${raw.substring(0, split).replaceAll(RegExp(r'[.,]'), '')}.${raw.substring(split + 1)}';
        if ((double.tryParse(value) ?? 0) > 0) suggest('amount', value, .9);
      }
    }
    final date = RegExp(
      r'\b(\d{2})[/.-](\d{2})[/.-](20\d{2})\b',
    ).firstMatch(line);
    if (date != null) {
      final y = int.parse(date[3]!),
          m = int.parse(date[2]!),
          d = int.parse(date[1]!);
      final parsed = DateTime(y, m, d);
      if (parsed.year == y && parsed.month == m && parsed.day == d) {
        suggest('expenseDate', '${date[3]}-${date[2]}-${date[1]}', upper.contains('FECHA') ? .95 : .85);
      }
    }
    final number = RegExp(
      r'\b[FBET]\d{3}\s*-\s*\d{1,12}\b',
      caseSensitive: false,
    ).firstMatch(line);
    if (number != null) {
      suggest('supportNumber', number[0]!.replaceAll(' ', '').toUpperCase(), .95);
    }
  }
  final upper = usable
      .where(
        (row) => row['confidence'] is! num || (row['confidence'] as num) >= .65,
      )
      .map((r) => textField(r, 'text').toUpperCase())
      .join('\n');
  final pen = RegExp(r'S/|\bPEN\b|\bSOLES\b').hasMatch(upper);
  final usd = RegExp(r'\bUSD\b|US\$|D[ÓO]LARES').hasMatch(upper);
  if (pen != usd) suggest('currencyCode', pen ? 'PEN' : 'USD', .95);
  return patches;
}
