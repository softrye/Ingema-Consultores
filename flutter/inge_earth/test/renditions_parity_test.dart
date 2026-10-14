import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inge_earth/renditions/rendition_features.dart';
import 'package:inge_earth/renditions/rendition_money.dart';
import 'package:inge_earth/renditions/renditions_bridge.dart';
import 'package:inge_earth/renditions/renditions_flow.dart';
import 'package:inge_earth/renditions/renditions_models.dart';
import 'package:inge_earth/renditions/v3/state/smart_fill.dart';

import '../../../tests/renditions/vectors/policy.dart';

// Paridad Web -> Android con los vectores compartidos (copia de
// packages/test-vectors de E1PT04m0/ingeplus en tests/renditions/vectors),
// reglas de fondo/tipo de cambio y la IA de Rendiciones apagada.
// Fixtures sintéticos: no prueban Supabase real.
JsonMap vectors(String name) =>
    jsonDecode(File('../../tests/renditions/vectors/$name').readAsStringSync()) as JsonMap;

RenditionData working({
  bool write = true,
  String status = 'OBSERVADO',
  String sync = 'SYNCED',
  int rowVersion = 7,
  String remoteId = '00000000-0000-4000-8000-000000000001',
}) =>
    RenditionData({
      'localId': 'local-1', 'remoteId': remoteId, 'rowVersion': rowVersion,
      'status': status, 'can_edit_content': write, 'syncState': sync,
      'funding': {'enabled': true, 'pen': 0, 'usd': 100},
      'exchangeRate': {'rate': 3.75, 'mode': 'AUTOMATIC'},
    });

void main() {
  test('shared money vectors: PostgreSQL ties-away cents and common fund', () {
    final money = vectors('money.json');
    for (final row in money['cases'] as List<dynamic>) {
      if (row['error'] == true) {
        expect(() => moneyCents(row['input']), throwsFormatException, reason: '${row['input']}');
      } else {
        expect(moneyCents(row['input']), row['cents'], reason: '${row['input']}');
      }
    }
    for (final row in money['fundCases'] as List<dynamic>) {
      final model = RenditionData({
        'funding': {'enabled': true, 'pen': row['fundPen'], 'usd': row['fundUsd']},
        'total_pen': row['spentPen'], 'total_usd': row['spentUsd'],
        'exchangeRate': {'rate': row['rate']},
      });
      expect(model.fundBalanceCents.pen, row['balancePenCents']);
      expect(model.fundBalanceCents.usd, row['balanceUsdCents']);
    }
    // Fondo deshabilitado: saldo no determinable, nunca 0 por ausencia.
    final disabled = RenditionData({'funding': {'enabled': false}, 'total_pen': 10});
    expect(disabled.fundBalanceCents.pen, isNull);
    expect(disabled.fundBalanceCents.usd, isNull);
  });

  test('shared calculation vectors hydrate the Dart DTO', () {
    for (final fixture in vectors('renditions-calculation.json')['cases'] as List<dynamic>) {
      final expected = fixture['expected'] as JsonMap;
      if (fixture['expenses'] == null || expected['pen'] == null) continue;
      for (final raw in fixture['expenses'] as List<dynamic>) {
        final model = ExpenseData({'amount': raw['amount'], 'currency_code': raw['currency'],
            'review_status': raw['reviewStatus'], 'archived': raw['archived']});
        expect(model.amount, double.parse(raw['amount'] as String));
        expect(contractCurrencies, contains(model.currency));
      }
      final header = RenditionData({'total_pen': expected['pen'], 'total_usd': expected['usd'],
          'expense_count': expected['count'], 'row_version': 7});
      expect(header.totalPen, double.parse(expected['pen'] as String));
      expect(header.totalUsd, double.parse(expected['usd'] as String));
    }
  });

  test('shared state vectors: effective permission decides editability', () {
    final protocol = vectors('protocol.json');
    for (final fixture in protocol['stateCases'] as List<dynamic>) {
      expect(contractActiveStates, contains(fixture['status']));
      final input = Map<String, dynamic>.from(fixture as Map)..remove('id');
      expect(RenditionData(input).readOnly, fixture['androidReadOnly'], reason: '${fixture['id']}');
    }
    for (final fixture in protocol['conflictCases'] as List<dynamic>) {
      expect(RenditionData({'sync_state': fixture['state']}).hasConflict, fixture['conflict']);
    }
    for (final fixture in protocol['attachmentCases'] as List<dynamic>) {
      expect(AttachmentData({'status': fixture['status']}).phase, fixture['status']);
    }
  });

  test('financial writes follow permission, conflict and identity', () {
    expect(financialWritable(working()), isTrue);
    expect(financialWritable(working(write: false)), isFalse);
    expect(financialWritable(working(status: 'EN_REVISION')), isFalse);
    expect(financialWritable(working(sync: 'CONFLICT')), isFalse);
    expect(financialWritable(working(sync: 'SYNCING')), isFalse);
    expect(financialWritable(working(), openLocalId: 'other'), isFalse);
    expect(financialWritable(working(), busy: true), isFalse);
    expect(financialWritable(null), isFalse);
  });

  test('saveFinancial arguments: PEN/USD fund, manual FX and CAS', () {
    final fund = fundingValues(enabled: true, pen: ' 75.00 ', usd: '100.00');
    expect(fund, {'enabled': true, 'pen': '75.00', 'usd': '100.00'});
    expect(fundingValues(enabled: false, pen: '75', usd: '1'), {'enabled': false, 'pen': '0', 'usd': '0'});
    expect(fundingError(fund), isNull);
    expect(fundingError({'enabled': true, 'pen': '-1', 'usd': '0'}), isNotNull);
    expect(fundingError({'enabled': true, 'pen': 'NaN', 'usd': '0'}), isNotNull);
    final args = saveFinancialArgs(renditionLocalId: 'local-1', kind: 'funding_set', values: fund, expectedRowVersion: 7);
    expect(args, {'localId': 'local-1', 'kind': 'funding_set', 'values': fund, 'expectedRowVersion': 7});
    expect(() => saveFinancialArgs(renditionLocalId: 'l', kind: 'other', values: {}, expectedRowVersion: 1),
        throwsA(isA<RenditionCommandException>()));
    expect(manualExchangeValues('3,75'), {'mode': 'MANUAL', 'rate': '3.75', 'quoted_on': null});
    expect(manualRateError('3.437'), isNull);
    expect(manualRateError('0'), isNotNull);
    expect(manualRateError('1000000'), isNotNull);
    expect(manualRateError('abc'), isNotNull);
    expect(financialDraftKey('local-1'), 'financial:local-1');
  });

  test('automatic BCRP/SBS quote is validated, never invented', () {
    final now = DateTime.utc(2026, 10, 14, 15);
    final day = limaDay(now);
    expect(day, '2026-10-14');
    expect(limaDay(DateTime.utc(2026, 10, 15, 3)), '2026-10-14');
    final valid = automaticExchangeValues(
        {'rate': '3.437', 'quotedOn': day, 'checkedAt': now.toIso8601String(), 'source': 'BCRP_SBS_VENTA'}, now);
    expect(valid, {'mode': 'AUTOMATIC', 'rate': '3.437', 'quoted_on': day, 'checked_at': now.toIso8601String()});
    for (final bad in <JsonMap>[
      {'rate': '3.437', 'quotedOn': day, 'checkedAt': '$now', 'source': 'OTHER'},
      {'rate': '3.437', 'quotedOn': '2026-10-15', 'checkedAt': '$now', 'source': 'BCRP_SBS_VENTA'},
      {'rate': '3.437', 'quotedOn': '2026-08-01', 'checkedAt': '$now', 'source': 'BCRP_SBS_VENTA'},
      {'rate': '0', 'quotedOn': day, 'checkedAt': '$now', 'source': 'BCRP_SBS_VENTA'},
      {'rate': null, 'quotedOn': day, 'checkedAt': '$now', 'source': 'BCRP_SBS_VENTA'},
      {'rate': '3.437', 'quotedOn': day, 'source': 'BCRP_SBS_VENTA'},
      {},
    ]) {
      expect(() => automaticExchangeValues(bad, now), throwsA(isA<RenditionCommandException>()), reason: '$bad');
    }
  });

  test('quote refresh throttling and late-quote discard', () {
    final now = DateTime.utc(2026, 10, 14, 15);
    final current = working();
    expect(quoteRefreshDue(current: current, automatic: true, dirty: false, now: now), isTrue);
    expect(quoteRefreshDue(current: current, automatic: false, dirty: false, now: now), isFalse);
    expect(quoteRefreshDue(current: working(write: false), automatic: true, dirty: false, now: now, force: true), isFalse);
    expect(quoteRefreshDue(current: working(remoteId: ''), automatic: true, dirty: false, now: now), isFalse);
    expect(quoteRefreshDue(current: working(sync: 'PENDING'), automatic: true, dirty: false, now: now), isFalse);
    expect(quoteRefreshDue(current: current, automatic: true, dirty: true, now: now), isFalse);
    expect(quoteRefreshDue(current: current, automatic: true, dirty: true, now: now, force: true), isTrue);
    expect(quoteRefreshDue(current: current, automatic: true, dirty: false, now: now,
        lastAttempt: now.subtract(const Duration(minutes: 2))), isFalse);
    expect(quoteRefreshDue(current: current, automatic: true, dirty: false, now: now,
        lastAttempt: now.subtract(const Duration(minutes: 10)),
        lastSuccess: now.subtract(const Duration(minutes: 30)), lastQuoteDay: limaDay(now)), isFalse);
    expect(quoteRefreshDue(current: current, automatic: true, dirty: false, now: now,
        lastAttempt: now.subtract(const Duration(minutes: 10)),
        lastSuccess: now.subtract(const Duration(hours: 2)), lastQuoteDay: limaDay(now)), isTrue);

    bool applies(RenditionData? after, {int rev = 0, int session = 0}) => quoteStillApplicable(
        before: current, now: after, revisionBefore: 0, revisionNow: rev, sessionBefore: 0, sessionNow: session);
    expect(applies(working()), isTrue);
    expect(applies(working(write: false)), isFalse, reason: 'revocación');
    expect(applies(working(rowVersion: 8)), isFalse, reason: 'CAS cambió');
    expect(applies(working(), rev: 1), isFalse, reason: 'edición del usuario');
    expect(applies(working(), session: 1), isFalse, reason: 'cambio de cuenta');
    expect(applies(null), isFalse);
  });

  test('Renditions AI is disabled by default and nothing depends on it', () async {
    expect(renditionsAiEnabled, isFalse);
    expect(() => ensureRenditionsAi(), throwsA(isA<RenditionCommandException>()
        .having((e) => e.code, 'code', renditionsAiDisabledCode)));
    expect(() => coreAnalyzeArgs(attachments: [], projectId: 'p', entityId: 'i', renditionLocalId: 'r',
            currentFields: {}, periodStart: 's', periodEnd: 'e', categories: [], supportTypes: [],
            paymentMethods: [], history: [], savedId: ''),
        throwsA(isA<RenditionCommandException>()));
    expect(acceptedReceiptPatches({'fields': [
      {'field': 'amount', 'value': '10', 'valid': true, 'confidence': .99},
    ]}), isEmpty, reason: 'sin Smart Fill automático');
    await expectLater(const LocalReceiptAnalysis().analyze({'nativeText': 'TOTAL S/ 10.00'}),
        throwsA(isA<RenditionCommandException>()));
    // Guardar un gasto no requiere IA.
    final args = saveExpenseArgs(renditionLocalId: 'r', savedId: '', values: {'amount': '10.00'}, receiptEvidence: {});
    expect(args['synchronize'], isTrue);
    expect(financialWritable(working()), isTrue);
  });
}
