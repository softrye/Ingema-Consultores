import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'received_models.dart';
import '../widgets/dashboard_widgets.dart';

class ReceivedSearchControl extends StatelessWidget {
  const ReceivedSearchControl({
    required this.controller,
    required this.focusNode,
    required this.palette,
    required this.onChanged,
    this.onFilter,
    this.filtered = false,
    this.query = false,
    super.key,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final RenditionsPalette palette;
  final ValueChanged<String> onChanged;
  final VoidCallback? onFilter;
  final bool filtered, query;
  @override
  Widget build(BuildContext context) => Material(
    color: palette.surface,
    borderRadius: BorderRadius.circular(24),
    elevation: 2,
    child: SizedBox(
      height: 48,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 9),
            child: Icon(LucideIcons.search, size: 18, color: palette.accent),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              style: TextStyle(color: palette.primary, fontSize: 13),
              decoration: InputDecoration(
                hintText: query
                    ? 'Buscar en snapshot'
                    : 'RDC, propietario o proyecto',
                hintStyle: TextStyle(color: palette.secondary, fontSize: 12),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Limpiar búsqueda',
              onPressed: () {
                controller.clear();
                onChanged('');
              },
              icon: Icon(LucideIcons.x, size: 17, color: palette.secondary),
            ),
          if (onFilter != null)
            IconButton(
              tooltip: 'Filtros y orden',
              onPressed: onFilter,
              icon: Icon(
                LucideIcons.slidersHorizontal,
                size: 19,
                color: filtered ? palette.accent : palette.secondary,
              ),
            ),
        ],
      ),
    ),
  );
}

Future<bool?> showReceivedFilters(
  BuildContext context,
  ReceivedFilter filter,
  RenditionsPalette palette,
) async {
  final draft = ReceivedFilter()..copyFrom(filter);
  final apply = await showDialog<bool>(
    context: context,
    builder: (_) => ReceivedFilterSheet(filter: draft, palette: palette),
  );
  if (apply == true && draft.valid) filter.copyFrom(draft);
  return apply;
}

class ReceivedFilterSheet extends StatefulWidget {
  const ReceivedFilterSheet({
    required this.filter,
    required this.palette,
    super.key,
  });
  final ReceivedFilter filter;
  final RenditionsPalette palette;
  @override
  State<ReceivedFilterSheet> createState() => _ReceivedFilterSheetState();
}

class _ReceivedFilterSheetState extends State<ReceivedFilterSheet> {
  late final _code = TextEditingController(text: widget.filter.code);
  late final _owner = TextEditingController(text: widget.filter.owner);
  late final _project = TextEditingController(text: widget.filter.project);
  @override
  void dispose() {
    _code.dispose();
    _owner.dispose();
    _project.dispose();
    super.dispose();
  }

  Future<void> _date(String value, ValueChanged<String> update) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black38,
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: ReceivedDatePicker(
          initial: DateTime.tryParse(value) ?? DateTime.now(),
          palette: widget.palette,
        ),
      ),
    );
    if (picked != null && mounted) setState(() => update(backendDate(picked)));
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.filter;
    Widget date(
      String title,
      String value,
      ValueChanged<String> update,
    ) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: OutlinedButton(
        onPressed: () => _date(value, update),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$title  ${value.isEmpty ? 'dd/MM/yyyy' : receivedDate(value)}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const Icon(LucideIcons.calendarDays, size: 17),
          ],
        ),
      ),
    );
    return Dialog(
      backgroundColor: widget.palette.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 390,
          maxHeight: MediaQuery.sizeOf(context).height * .78,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Filtros y orden',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(LucideIcons.x, size: 19),
                  ),
                ],
              ),
              TextField(
                controller: _code,
                onChanged: (v) => f.code = v,
                decoration: const InputDecoration(labelText: 'Código RDC'),
              ),
              TextField(
                controller: _owner,
                onChanged: (v) => f.owner = v,
                decoration: const InputDecoration(labelText: 'Propietario'),
              ),
              TextField(
                controller: _project,
                onChanged: (v) => f.project = v,
                decoration: const InputDecoration(labelText: 'Project'),
              ),
              const SizedBox(height: 8),
              date('Periodo desde', f.periodFrom, (v) => f.periodFrom = v),
              date('Periodo hasta', f.periodTo, (v) => f.periodTo = v),
              date(
                'Presentada desde',
                f.submittedFrom,
                (v) => f.submittedFrom = v,
              ),
              date('Presentada hasta', f.submittedTo, (v) => f.submittedTo = v),
              const SizedBox(height: 10),
              DropdownButtonFormField<ReceivedOrder>(
                key: ValueKey(f.order),
                initialValue: f.order,
                isExpanded: true,
                icon: const Icon(LucideIcons.chevronDown, size: 18),
                decoration: const InputDecoration(labelText: 'Orden'),
                items: const [
                  DropdownMenuItem(
                    value: ReceivedOrder.newest,
                    child: Text(
                      'Presentación más reciente',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  DropdownMenuItem(
                    value: ReceivedOrder.oldest,
                    child: Text(
                      'Presentación más antigua',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  DropdownMenuItem(
                    value: ReceivedOrder.code,
                    child: Text(
                      'Código ascendente',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => f.order = v!),
              ),
              if (!f.valid)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'La fecha desde no puede superar la fecha hasta.',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        f.clear();
                        _code.clear();
                        _owner.clear();
                        _project.clear();
                      });
                    },
                    child: const Text('Limpiar'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: f.valid
                        ? () => Navigator.pop(context, true)
                        : null,
                    icon: const Icon(LucideIcons.refreshCw, size: 16),
                    label: const Text('Actualizar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact Material calendar with Lucide navigation, avoiding a Material icon font.
class ReceivedDatePicker extends StatefulWidget {
  const ReceivedDatePicker({
    required this.initial,
    required this.palette,
    super.key,
  });
  final DateTime initial;
  final RenditionsPalette palette;
  @override
  State<ReceivedDatePicker> createState() => _ReceivedDatePickerState();
}

class _ReceivedDatePickerState extends State<ReceivedDatePicker> {
  late DateTime selected = widget.initial;
  late DateTime month = DateTime(selected.year, selected.month);
  static const months = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];
  @override
  Widget build(BuildContext context) {
    final offset = month.weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    return Dialog(
      backgroundColor: widget.palette.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                receivedDate(backendDate(selected)),
                style: TextStyle(
                  color: widget.palette.accent,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Mes anterior',
                    onPressed: () => setState(
                      () => month = DateTime(month.year, month.month - 1),
                    ),
                    icon: const Icon(LucideIcons.chevronLeft),
                  ),
                  Expanded(
                    child: Text(
                      '${months[month.month - 1]} ${month.year}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Mes siguiente',
                    onPressed: () => setState(
                      () => month = DateTime(month.year, month.month + 1),
                    ),
                    icon: const Icon(LucideIcons.chevronRight),
                  ),
                ],
              ),
              Row(
                children: [
                  for (final d in ['L', 'M', 'X', 'J', 'V', 'S', 'D'])
                    Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: TextStyle(
                            color: widget.palette.secondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: ((offset + days + 6) ~/ 7) * 7,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                ),
                itemBuilder: (context, i) {
                  final day = i - offset + 1;
                  if (day < 1 || day > days) return const SizedBox.shrink();
                  final date = DateTime(month.year, month.month, day);
                  final active =
                      selected.year == date.year &&
                      selected.month == date.month &&
                      selected.day == date.day;
                  return Semantics(
                    selected: active,
                    label: receivedDate(backendDate(date)),
                    button: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(30),
                      onTap: () => setState(() => selected = date),
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active
                              ? widget.palette.accent
                              : Colors.transparent,
                        ),
                        child: Text(
                          '$day',
                          style: TextStyle(
                            color: active
                                ? Colors.white
                                : widget.palette.primary,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, selected),
                    child: const Text('Aceptar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
