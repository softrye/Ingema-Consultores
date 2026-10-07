import 'package:flutter/material.dart';

import '../renditions_bridge.dart';
import '../renditions_models.dart';
import 'widgets/dashboard_widgets.dart';

/// Existing-record route. The next editing pass uses this same bridge's
/// `update` command with localId and the complete saved header (never `create`).
class RenditionDetailV2 extends StatefulWidget {
  const RenditionDetailV2({
    required this.bridge,
    required this.selected,
    required this.palette,
    required this.onBack,
    super.key,
  });

  final RenditionsBridge bridge;
  final RenditionData selected;
  final RenditionsPalette palette;
  final VoidCallback onBack;

  @override
  State<RenditionDetailV2> createState() => _RenditionDetailV2State();
}

class _RenditionDetailV2State extends State<RenditionDetailV2> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _start;
  late final TextEditingController _end;
  late RenditionData _baseline;
  bool _saving = false;
  String _message = '';
  RenditionsBridge get bridge => widget.bridge;
  RenditionData get selected => widget.selected;
  RenditionsPalette get palette => widget.palette;
  VoidCallback get onBack => widget.onBack;

  @override
  void initState() {
    super.initState();
    _baseline = rendition;
    _start = TextEditingController(text: _baseline.periodStart);
    _end = TextEditingController(text: _baseline.periodEnd);
  }

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  String? _dateError(String? text) {
    final date = DateTime.tryParse(text ?? '');
    return date == null || date.toIso8601String().substring(0, 10) != text
        ? 'Usa una fecha válida: AAAA-MM-DD'
        : null;
  }

  Future<void> _save() async {
    if (!isEditing || _saving || !_form.currentState!.validate()) return;
    if (_start.text.compareTo(_end.text) > 0) {
      setState(() => _message = 'El inicio debe ser anterior o igual al fin.');
      return;
    }
    setState(() {
      _saving = true;
      _message = '';
    });
    try {
      final result = await bridge.command('update', {
        'localId': _baseline.localId,
        'expectedRowVersion': _baseline.rowVersion,
        'periodStart': _start.text,
        'periodEnd': _end.text,
        'projectIds': _baseline.projectIds,
        'primaryProjectId': _baseline.primaryProjectId,
        'documentParentNodeId': _baseline.documentParentNodeId,
        'spaceId': _baseline.spaceId,
        'synchronize': true,
      });
      if (!mounted) return;
      final saved = RenditionData(jsonMap(result['current']));
      if (saved.localId != _baseline.localId) {
        throw const RenditionCommandException(
          'IDENTITY_MISMATCH',
          'No se pudo confirmar la identidad guardada.',
        );
      }
      setState(() {
        _baseline = saved;
        _message = 'Cambios guardados localmente. Sincronización pendiente.';
      });
    } catch (error) {
      if (mounted)
        setState(
          () => _message = error is RenditionCommandException
              ? error.message
              : 'No se pudo guardar la rendición.',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  RenditionData get rendition =>
      bridge.current?.localId == selected.localId ? bridge.current! : selected;
  bool get isEditing =>
      !rendition.readOnly &&
      !rendition.hasConflict &&
      rendition.syncState != 'SYNCING' &&
      !bridge.busy;

  @override
  Widget build(BuildContext context) {
    final saved = rendition;
    final expenses = jsonRows(
      saved.raw['expenses'],
    ).map(ExpenseData.new).where((row) => !row.archived).toList();
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                tooltip: 'Volver a Rendiciones',
                icon: Icon(Icons.arrow_back, color: palette.primary),
              ),
              Expanded(
                child: Text(
                  'Detalle de rendición',
                  style: TextStyle(
                    color: palette.primary,
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            saved.code,
            style: TextStyle(
              color: palette.primary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '${saved.status} · ${saved.syncState}',
            style: TextStyle(color: palette.primary),
          ),
          const SizedBox(height: 16),
          Text(
            saved.primaryProjectName.isEmpty
                ? 'Proyecto sin nombre disponible'
                : saved.primaryProjectName,
            style: TextStyle(color: palette.primary),
          ),
          Text(
            '${compactDate(saved.periodStart)} — ${compactDate(saved.periodEnd)}',
            style: TextStyle(color: palette.primary),
          ),
          const SizedBox(height: 16),
          Form(
            key: _form,
            child: Column(
              children: [
                TextFormField(
                  controller: _start,
                  enabled: isEditing && !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Inicio del período (AAAA-MM-DD)',
                  ),
                  validator: _dateError,
                ),
                TextFormField(
                  controller: _end,
                  enabled: isEditing && !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Fin del período (AAAA-MM-DD)',
                  ),
                  validator: _dateError,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: isEditing && !_saving ? _save : null,
                  child: Text(_saving ? 'Guardando…' : 'Guardar cambios'),
                ),
              ],
            ),
          ),
          if (_message.isNotEmpty)
            Text(_message, style: TextStyle(color: palette.primary)),
          if (bridge.lastError.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(bridge.lastError, style: TextStyle(color: palette.primary)),
          ],
          if (saved.readOnly || saved.hasConflict) ...[
            const SizedBox(height: 12),
            Text(
              saved.readOnly
                  ? 'Esta rendición es de solo lectura.'
                  : 'Hay cambios pendientes de reconciliación.',
              style: TextStyle(color: palette.primary),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Gastos guardados (${expenses.length})',
            style: TextStyle(
              color: palette.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (expenses.isEmpty)
            Text(
              'No hay gastos guardados en esta rendición.',
              style: TextStyle(color: palette.primary),
            ),
          for (final expense in expenses)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                expense.concept,
                style: TextStyle(color: palette.primary),
              ),
              subtitle: Text(
                compactDate(expense.date),
                style: TextStyle(color: palette.primary),
              ),
              trailing: Text(
                '${expense.currency} ${expense.amount.toStringAsFixed(2)}',
                style: TextStyle(color: palette.primary),
              ),
            ),
        ],
      ),
    );
  }
}
