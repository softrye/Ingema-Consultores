import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../renditions_bridge.dart';
import '../../renditions_models.dart';
import '../../v2/received/received_models.dart';
import '../components/nothing_components.dart';
import '../state/rendition_editor_state.dart';
import '../state/smart_fill.dart';

class ExpenseEditor extends StatefulWidget {
  const ExpenseEditor({
    required this.bridge,
    required this.rendition,
    required this.onBack,
    required this.onSaved,
    required this.onChanged,
    this.onExistingExpense,
    this.expense,
    this.analysis = const LocalReceiptAnalysis(),
    super.key,
  });
  final RenditionsBridge bridge;
  final RenditionData rendition;
  final ExpenseData? expense;
  final VoidCallback onBack, onSaved, onChanged;
  final ValueChanged<ExpenseData>? onExistingExpense;
  final ReceiptAnalysisAdapter analysis;
  @override
  State<ExpenseEditor> createState() => ExpenseEditorViewState();
}

class ExpenseEditorViewState extends State<ExpenseEditor> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> fields;
  late String project, date, currency, category, payment, support, _savedId;
  final List<JsonMap> pendingAttachments = [];
  bool saving = false, analyzing = false, picking = false;
  String error = '';
  final Map<String, JsonMap> fieldEvidence = {};
  final List<JsonMap> fieldIssues = [];
  final Set<String> _autoApplied = {};
  final Set<String> _userEdited = {};
  bool _reviewVisible = false, _coreUnavailable = false;
  bool get busy => saving || picking;
  int _analysisGeneration = 0;
  Timer? _autosave;
  bool _finished = false;
  bool _draftPersisted = false;
  late String _intentId;
  String get _draftKey => 'expense:${widget.rendition.localId}:${widget.expense?.localId ?? 'new'}';
  JsonMap get _values => {
    'clientIntentId': _intentId, 'projectId': project, 'expenseDate': date,
    'categoryCode': category, 'currencyCode': currency,
    'paymentMethodCode': payment, 'supportTypeCode': support,
    for (final f in fields.entries) f.key: f.key == 'amount'
        ? f.value.text.replaceAll(',', '.') : f.value.text,
  };
  Future<void> _persistDraft() async {
    if (_finished || widget.rendition.readOnly) return;
    _draftPersisted = false;
    try {
      await widget.bridge.command('saveEditorDraft', {'key': _draftKey, 'draft': {
        ..._values, 'renditionLocalId': widget.rendition.localId,
        for (final f in fields.entries) f.key: f.value.text,
        'savedId': _savedId, 'pendingAttachments': [...pendingAttachments],
        'fieldEvidence': fieldEvidence, 'fieldIssues': fieldIssues,
        'autoApplied': _autoApplied.toList(),
        'userEdited': _userEdited.toList(),
        'reviewVisible': _reviewVisible, 'coreUnavailable': _coreUnavailable,
      }});
      _draftPersisted = true;
    } catch (e) { if (mounted) setState(() => error = 'No se pudo autoguardar: $e'); }
  }
  void _scheduleDraft() {
    if (busy || _finished) return;
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 650), _persistDraft);
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) { _autosave?.cancel(); unawaited(_persistDraft()); }
  }
  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    _savedId = e?.localId ?? '';
    fields = {
      for (final entry in <String, String>{
        'amount': e?.amount.toStringAsFixed(2) ?? '',
        'concept': e?.concept ?? '',
        'beneficiary': e?.beneficiary ?? '',
        'ruc': textField(e?.raw ?? {}, 'ruc'),
        'subtotal': textField(e?.raw ?? {}, 'subtotal'),
        'igv': textField(e?.raw ?? {}, 'igv'),
        'paymentMethodDetail': e?.paymentMethodDetail ?? '',
        'supportNumber': e?.supportNumber ?? '',
        'supportDetail': e?.supportDetail ?? '',
        'justification': e?.justification ?? '',
      }.entries)
        entry.key: TextEditingController(text: entry.value),
    };
    project = e?.projectId ?? widget.rendition.primaryProjectId;
    date = e?.date ?? widget.rendition.periodStart;
    currency = e?.currency ?? 'PEN';
    category = e?.categoryCode ?? '';
    payment = e?.paymentMethodCode ?? '';
    support = e?.supportTypeCode ?? '';
    final draft = jsonMap(widget.bridge.editorDrafts[_draftKey]);
    _intentId = textField(draft, 'clientIntentId');
    if (_intentId.isEmpty) _intentId = 'expense-${DateTime.now().microsecondsSinceEpoch}';
    if (draft.isNotEmpty) {
      _savedId = textField(draft, 'savedId');
      project = textField(draft, 'projectId'); date = textField(draft, 'expenseDate');
      currency = textField(draft, 'currencyCode'); category = textField(draft, 'categoryCode');
      payment = textField(draft, 'paymentMethodCode'); support = textField(draft, 'supportTypeCode');
      for (final f in fields.entries) {
        if (draft.containsKey(f.key)) f.value.text = draft[f.key].toString();
      }
      pendingAttachments.addAll(jsonRows(draft['pendingAttachments']));
      final evidence = jsonMap(draft['fieldEvidence']);
      for (final entry in evidence.entries) { fieldEvidence[entry.key] = jsonMap(entry.value); }
      fieldIssues.addAll(jsonRows(draft['fieldIssues']));
      _autoApplied.addAll((draft['autoApplied'] as List? ?? []).map((v) => v.toString()));
      _userEdited.addAll((draft['userEdited'] as List? ?? []).map((v) => v.toString()));
      _reviewVisible = draft['reviewVisible'] == true;
      _coreUnavailable = draft['coreUnavailable'] == true;
    }
    for (final f in fields.values) { f.addListener(_scheduleDraft); }
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _autosave?.cancel();
    unawaited(_persistDraft());
    WidgetsBinding.instance.removeObserver(this);
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void changed() {
    setState(() {});
    widget.onChanged();
    _scheduleDraft();
  }

  Future<void> attach() async {
    if (busy) return;
    picking = true;
    error = '';
    changed();
    try {
      final attachment = await widget.bridge.pickAttachment();
      if (attachment != null && mounted) pendingAttachments.add(attachment);
    } catch (e) {
      if (mounted) error = e.toString();
    } finally {
      if (mounted) {
        picking = false;
        changed();
      }
    }
    if (mounted && pendingAttachments.isNotEmpty) await smartFill();
  }

  Future<void> smartFill() async {
    if (busy || analyzing) return;
    final generation = ++_analysisGeneration;
    final sources = [
      ...pendingAttachments,
      if (widget.expense != null)
        ...jsonRows(widget.expense!.raw['attachments']),
    ];
    if (sources.isEmpty) {
      error = 'Adjunta documentos para proponer campos.';
      changed();
      return;
    }
    analyzing = true;
    error = '';
    changed();
    try {
      JsonMap result;
      try {
        result = await widget.bridge.command('coreAnalyze', {
        'attachments': sources,
        'context': {
          'project_id': project, 'entity_id': _savedId.isEmpty ? _intentId : _savedId,
          'entity': {'rendition_id': widget.rendition.localId},
          'current_fields': _values,
          'rules': {
            'period_start': widget.rendition.periodStart,
            'period_end': widget.rendition.periodEnd,
            'categories': widget.bridge.catalogsOf('CATEGORY'),
            'support_types': widget.bridge.catalogsOf('SUPPORT_TYPE'),
            'payment_methods': widget.bridge.catalogsOf('PAYMENT_METHOD'),
          },
          'related_history': widget.bridge.expenses
              .where((e) => e.localId != _savedId)
              .take(20).map((e) => e.raw).toList(),
        },
        }).timeout(const Duration(seconds: 65));
      } catch (_) {
        if (!mounted || generation != _analysisGeneration) return;
        final patches = <SuggestedExpensePatch>[];
        for (final source in sources) {
          try { patches.addAll(await widget.analysis.analyze(source).timeout(const Duration(seconds: 12))); }
          catch (_) { /* Preserve readable sources and all current values. */ }
        }
        result = localReceiptResult(patches);
      }
      if (!mounted || generation != _analysisGeneration) return;
      final review = ReceiptReview.fromResult(result, widget.rendition.periodStart, widget.rendition.periodEnd);
      fieldIssues..clear()..addAll(review.issues);
      _reviewVisible = true;
      _coreUnavailable = review.unavailable;
      fieldEvidence.clear();
      for (final row in jsonRows(result['fields'])) {
        fieldEvidence[textField(row, 'field')] = row;
      }
      final patches = jsonRows(result['fields'])
          .where((r) => r['conflict'] != true && r['valid'] == true
              && ((r['confidence'] as num?) ?? 0) >= .70)
          .map((r) => SuggestedExpensePatch(
            field: textField(r, 'field'), proposedValue: r['value'] ?? '',
            confidence: (r['confidence'] as num?)?.toDouble() ?? 0,
            sourceAttachment: (r['sources'] as List? ?? []).join(', '),
          )).toList();
      if (!mounted) return;
      if (mounted) {
        for (final p in patches) {
          final value = p.proposedValue.toString();
          final evidence = fieldEvidence[p.field] ?? {};
          final current = _values[p.field]?.toString() ?? '';
          final untouchedDefault = widget.expense == null &&
              ((p.field == 'expenseDate' && date == widget.rendition.periodStart) ||
               (p.field == 'currencyCode' && currency == 'PEN'));
          if (!ReceiptReview.canAutofill(evidence, current, _userEdited.contains(p.field),
              defaultValue: untouchedDefault || _autoApplied.contains(p.field))) {
            continue;
          }
          if (fields.containsKey(p.field)) fields[p.field]!.text = value;
          if (p.field == 'expenseDate') date = value;
          if (p.field == 'currencyCode' && ['PEN', 'USD'].contains(value)) {
            currency = value;
          }
          if (p.field == 'categoryCode' && _hasCode('CATEGORY', value)) {
            category = value;
          }
          if (p.field == 'paymentMethodCode' &&
              _hasCode('PAYMENT_METHOD', value)) {
            payment = value;
          }
          if (p.field == 'supportTypeCode' && _hasCode('SUPPORT_TYPE', value)) {
            support = value;
          }
          _autoApplied.add(p.field);
        }
      }
    } catch (e) {
      if (mounted && generation == _analysisGeneration) {
        _reviewVisible = true;
        _coreUnavailable = true;
      }
    } finally {
      if (mounted && generation == _analysisGeneration) {
        analyzing = false;
        changed();
      }
    }
  }

  bool _hasCode(String kind, String value) =>
      widget.bridge.catalogsOf(kind).any((r) => textField(r, 'code') == value);

  void _applyEvidence(String key, JsonMap row) {
    final value = textField(row, 'value');
    if (fields.containsKey(key)) fields[key]!.text = value;
    else if (key == 'expenseDate' && RenditionEditorState.validDate(value)) { date = value; }
    else if (key == 'currencyCode' && ['PEN', 'USD'].contains(value)) { currency = value; }
    else if (key == 'categoryCode' && _hasCode('CATEGORY', value)) { category = value; }
    else if (key == 'supportTypeCode' && _hasCode('SUPPORT_TYPE', value)) { support = value; }
    else if (key == 'paymentMethodCode' && _hasCode('PAYMENT_METHOD', value)) { payment = value; }
    else { return; }
    _autoApplied.add(key);
  }

  Widget _reviewCard() => NothingCard(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(_coreUnavailable ? 'Revisión pendiente' : 'Revisión completada',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(_coreUnavailable ? coreUnavailableMessage : fieldIssues.isEmpty
          ? 'Los datos principales del comprobante coinciden.'
          : 'Encontré ${fieldIssues.length} ${fieldIssues.length == 1 ? 'dato que necesita' : 'datos que necesitan'} revisión.'),
      for (final issue in fieldIssues) Text('• ${receiptIssueMessage(issue)}'),
      for (final entry in fieldEvidence.entries)
        if (!_autoApplied.contains(entry.key) && entry.value['valid'] == true &&
            receiptFieldLabel(entry.key) != 'dato del comprobante')
          TextButton(onPressed: busy ? null : () {
            // Explicit confirmation also covers low confidence and conflicts.
            _applyEvidence(entry.key, entry.value);
            _userEdited.add(entry.key);
            fieldIssues.removeWhere((issue) => textField(issue, 'field') == entry.key &&
                textField(issue, 'reason') != 'DATE_OUTSIDE_RENDITION_PERIOD');
            changed();
          }, child: Text('Confirmar ${receiptFieldLabel(entry.key)}: ${textField(entry.value, 'value')}'
              '${_userEdited.contains(entry.key) ? ' (reemplaza tu dato)' : ''}')),
      Wrap(spacing: 8, children: [
        if (_coreUnavailable)
          TextButton(onPressed: busy ? null : smartFill, child: const Text('Reintentar revisión')),
        TextButton(onPressed: busy ? null : () {
          for (final entry in fieldEvidence.entries) {
            if (ReceiptReview.canAutofill(entry.value, _values[entry.key], _userEdited.contains(entry.key),
                defaultValue: _autoApplied.contains(entry.key))) _applyEvidence(entry.key, entry.value);
          }
          if (fieldIssues.isEmpty) _reviewVisible = false;
          changed();
        }, child: Text(fieldIssues.isEmpty ? 'Aceptar' : 'Aplicar datos válidos')),
      ]),
    ],
  ));

  Future<void> save() async {
    if (busy || !_formKey.currentState!.validate()) return;
    final period = RenditionEditorState(baseline: widget.rendition);
    if (!period.includesExpenseDate(date)) {
      error =
          'La fecha del gasto debe estar dentro del período de la rendición.';
      changed();
      return;
    }
    ++_analysisGeneration;
    analyzing = false;
    saving = true;
    error = '';
    changed();
    try {
      _autosave?.cancel();
      await _persistDraft();
      if (!mounted || !_draftPersisted) return;
      final duplicates = widget.bridge.expenses.where((e) => e.localId != _savedId &&
          similarExpense({..._values, 'attachments': pendingAttachments}, e.raw)).toList();
      if (_savedId.isEmpty && duplicates.isNotEmpty) {
        final decision = await showDialog<String>(context: context, builder: (context) => AlertDialog(
          title: const Text('Posible comprobante duplicado'),
          content: const Text('Este comprobante parece estar registrado en esta rendición.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context, 'view'), child: const Text('Ver gasto existente')),
            FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Registrar de todas formas'))],
        ));
        if (!mounted) return;
        if (decision == 'view') { widget.onExistingExpense?.call(duplicates.first); return; }
        if (decision != 'save') return;
      }
      final result = await widget.bridge.command('saveExpense', {
        'localId': widget.rendition.localId,
        'expenseLocalId': _savedId,
        if (_savedId.isNotEmpty && widget.expense != null)
          'expectedExpenseRowVersion': widget.expense!.rowVersion,
        'expense': {
          'clientIntentId': _intentId,
          'projectId': project,
          'expenseDate': date,
          'categoryCode': category,
          'currencyCode': currency,
          'paymentMethodCode': payment,
          'supportTypeCode': support,
          'receiptEvidence': fieldEvidence,
          for (final f in fields.entries)
            f.key: f.key == 'amount'
                ? f.value.text.replaceAll(',', '.')
                : f.value.text,
        },
        'synchronize': true,
      });
      if (!mounted) return;
      _savedId = textField(result, 'localId');
      if (_savedId.isEmpty) {
        throw const RenditionCommandException(
          'EXPENSE_ID_MISSING',
          'No se confirmó la identidad del gasto.',
        );
      }
      // Remove only confirmed attachments: retries cannot recreate the expense.
      while (pendingAttachments.isNotEmpty) {
        final attachment = pendingAttachments.first;
        await widget.bridge.command('attachSupport', {
          'localId': widget.rendition.localId,
          'expenseLocalId': _savedId,
          'attachment': {
            ...attachment,
            'clientIntentId': '$_intentId:${attachment['localUri']}',
            'supportTypeCode': support,
            'documentNumber': fields['supportNumber']!.text,
          },
        });
        if (!mounted) return;
        pendingAttachments.removeAt(0);
      }
      _finished = true;
      await widget.bridge.command('saveEditorDraft', {'key': _draftKey, 'draft': <String, dynamic>{}});
      if (!mounted) return;
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        error =
            '${_savedId.isNotEmpty ? 'El gasto está guardado. ' : ''}${e.toString()}';
      }
    } finally {
      if (mounted) {
        saving = false;
        changed();
      }
    }
  }

  Future<void> pickDate() async {
    final start = DateTime.tryParse(widget.rendition.periodStart),
        end = DateTime.tryParse(widget.rendition.periodEnd);
    if (start == null || end == null || end.isBefore(start)) return;
    var initial = DateTime.tryParse(date) ?? start;
    if (initial.isBefore(start) || initial.isAfter(end)) initial = start;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: start,
      lastDate: end,
    );
    if (picked != null && mounted) {
      date = backendDate(picked);
      _autoApplied.remove('expenseDate');
      _userEdited.add('expenseDate');
      changed();
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        NothingHeading(
          widget.expense == null ? 'Nuevo gasto' : 'Editar gasto',
          '${receivedDate(widget.rendition.periodStart)} — ${receivedDate(widget.rendition.periodEnd)}',
          onBack: busy ? null : widget.onBack,
        ),
        if (busy) const LinearProgressIndicator(minHeight: 2),
        if (analyzing) Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 10, 2, 6),
            child: Row(children: [
              NothingThreeBalls(),
              SizedBox(width: 12),
              Expanded(child: Text('Analizando comprobante…',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            ]),
          ),
          const NothingNotice('Puedes completar el gasto mientras esperas.'),
          TextButton(onPressed: () {
            ++_analysisGeneration;
            analyzing = false;
            _coreUnavailable = _reviewVisible = true;
            changed();
          }, child: const Text('Continuar manualmente')),
        ]),
        if (error.isNotEmpty) NothingNotice(error),
        if (_reviewVisible && !analyzing) _reviewCard(),
        const NothingSection('Datos del gasto'),
        _dropdown('Proyecto', project, [
          for (final id in widget.rendition.projectIds)
            (
              id,
              textField(widget.bridge.project(id) ?? {}, 'name').isEmpty
                  ? (id == widget.rendition.primaryProjectId
                        ? widget.rendition.primaryProjectName
                        : id)
                  : textField(widget.bridge.project(id)!, 'name'),
            ),
        ], (v) => project = v),
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: InkWell(
            onTap: busy ? null : pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Fecha',
                suffixIcon: Icon(LucideIcons.calendarDays, size: 20),
              ),
              child: Text(receivedDate(date)),
            ),
          ),
        ),
        _catalog('Categoría', 'CATEGORY', category, (v) => category = v),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: _dropdown('Moneda', currency, const [
                ('PEN', 'PEN'),
                ('USD', 'USD'),
              ], (v) => currency = v),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _field('amount', 'Monto', required: true, numeric: true),
            ),
          ],
        ),
        _field('concept', 'Concepto', required: true),
        _field('beneficiary', 'Proveedor o beneficiario'),
        _field('ruc', 'RUC del proveedor'),
        Row(children: [
          Expanded(child: _field('subtotal', 'Subtotal del comprobante', numeric: true)),
          const SizedBox(width: 12),
          Expanded(child: _field('igv', 'IGV del comprobante', numeric: true)),
        ]),
        const NothingSection('Pago y sustento'),
        _catalog(
          'Medio de pago',
          'PAYMENT_METHOD',
          payment,
          (v) => payment = v,
        ),
        _field('paymentMethodDetail', 'Detalle del medio'),
        _catalog(
          'Tipo de sustento',
          'SUPPORT_TYPE',
          support,
          (v) => support = v,
        ),
        _field('supportNumber', 'N.º de comprobante / operación'),
        _field('supportDetail', 'Detalle del sustento'),
        _field('justification', 'Justificación', lines: 3),
        NothingSection(
          'Sustentos',
          action: TextButton.icon(
            onPressed: busy ? null : attach,
            icon: const Icon(LucideIcons.plus, size: 18),
            label: const Text('Adjuntar'),
          ),
        ),
        for (final a in pendingAttachments)
          NothingCard(
            child: Row(
              children: [
                const Icon(LucideIcons.paperclip, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(textField(a, 'fileName'))),
                IconButton(
                  tooltip: 'Quitar adjunto sin guardar',
                  onPressed: busy
                      ? null
                      : () {
                          pendingAttachments.remove(a);
                          changed();
                        },
                  icon: const Icon(LucideIcons.x, size: 18),
                ),
              ],
            ),
          ),
        if (widget.expense != null)
          for (final a in jsonRows(widget.expense!.raw['attachments']))
            NothingCard(
              child: Text(
                '${textField(a, 'fileName', 'file_name')} · ${textField(a, 'phase')}',
              ),
            ),
        const NothingNotice(
          'Los sustentos se analizan al adjuntarlos. Revisa los campos marcados; los datos que escribiste se conservan.',
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(saving ? 'Guardando…' : 'Guardar gasto'),
        ),
      ],
    ),
  );
  Widget _field(
    String id,
    String label, {
    bool required = false,
    bool numeric = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextFormField(
      controller: fields[id],
      enabled: !busy,
      maxLines: lines,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: (_) { _autoApplied.remove(id); _userEdited.add(id); },
      decoration: InputDecoration(labelText: label,
        helperText: _autoApplied.contains(id) ? 'Completado desde el sustento · revisa antes de guardar' : null),
      validator: (value) {
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
        if (['concept', 'justification'].contains(id) && (value ?? '').trim().isNotEmpty &&
            !meaningfulExpenseText(value!)) return 'Describe el gasto con palabras completas';
        return null;
      },
    ),
  );
  Widget _catalog(
    String label,
    String kind,
    String value,
    ValueChanged<String> change,
  ) => _dropdown(
    label,
    value,
    widget.bridge
        .catalogsOf(kind)
        .map((r) => (textField(r, 'code'), textField(r, 'name')))
        .toList(),
    change,
  );
  Widget _dropdown(
    String label,
    String value,
    List<(String, String)> choices,
    ValueChanged<String> change,
  ) {
    final known = choices.any((c) => c.$1 == value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label:$value'),
        icon: const Icon(LucideIcons.chevronDown, size: 20),
        initialValue: known ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          helperText: choices.isEmpty
              ? 'Sin catálogo disponible. Sincroniza para cargarlo.'
              : null,
        ),
        items: [
          for (final c in choices)
            DropdownMenuItem(
              value: c.$1,
              child: Text(c.$2, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: busy
            ? null
            : (v) {
                if (v != null) {
                  change(v);
                  final key = const {'Proyecto': 'projectId', 'Moneda': 'currencyCode',
                    'Categoría': 'categoryCode', 'Medio de pago': 'paymentMethodCode',
                    'Tipo de sustento': 'supportTypeCode'}[label];
                  if (key != null) { _autoApplied.remove(key); _userEdited.add(key); }
                  changed();
                }
              },
        validator: (v) =>
            v == null || v.isEmpty ? 'Selecciona una opción' : null,
      ),
    );
  }
}
