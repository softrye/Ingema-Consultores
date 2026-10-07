import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../renditions_models.dart';

class RenditionsPalette {
  const RenditionsPalette(this.dark);
  final bool dark;

  Color get background =>
      dark ? const Color(0xFF171716) : const Color(0xFFFAFAFA);
  Color get surface => dark ? const Color(0xFF252522) : const Color(0xFFFDFDFD);
  Color get primary => dark ? const Color(0xFFF2F6F5) : const Color(0xFF252522);
  Color get secondary =>
      dark ? const Color(0xFFC2C2BD) : const Color(0xFF686865);
  Color get tertiary =>
      dark ? const Color(0xFF999994) : const Color(0xFF7B7B77);
  Color get accent => dark ? const Color(0xFFE4E4E0) : const Color(0xFF454542);
  Color get accentSoft =>
      dark ? const Color(0xFF383835) : const Color(0xFFECECEA);
  Color get border => dark ? const Color(0xFF454542) : const Color(0xFFDADAD5);
  Color get error => dark ? const Color(0xFFFFA0A5) : const Color(0xFFB63A43);
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    required this.palette,
    required this.title,
    this.trailing,
    super.key,
  });
  final RenditionsPalette palette;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: Text(
          title,
          style: TextStyle(
            color: palette.primary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      if (trailing != null)
        Text(
          trailing!,
          style: TextStyle(color: palette.tertiary, fontSize: 11),
        ),
    ],
  );
}

class CompactMetricsStrip extends StatelessWidget {
  const CompactMetricsStrip({
    required this.palette,
    required this.loaded,
    required this.drafts,
    required this.presented,
    super.key,
  });
  final RenditionsPalette palette;
  final int loaded;
  final int drafts;
  final int presented;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: palette.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: palette.border),
    ),
    child: SizedBox(
      height: 66,
      child: Row(
        children: <Widget>[
          Expanded(
            child: _Metric(value: loaded, label: 'Cargadas', palette: palette),
          ),
          _MetricDivider(palette.border),
          Expanded(
            child: _Metric(
              value: drafts,
              label: 'Borradores',
              palette: palette,
            ),
          ),
          _MetricDivider(palette.border),
          Expanded(
            child: _Metric(
              value: presented,
              label: 'Presentadas',
              palette: palette,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 30, color: color);
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    required this.palette,
  });
  final int value;
  final String label;
  final RenditionsPalette palette;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value',
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          '$value',
          style: TextStyle(
            color: palette.primary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: palette.secondary,
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class CompactStatus extends StatelessWidget {
  const CompactStatus({required this.palette, required this.text, super.key});
  final RenditionsPalette palette;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: palette.accentSoft,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: palette.border),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: palette.accent,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class RecentRenditionRow extends StatelessWidget {
  const RecentRenditionRow({
    required this.palette,
    required this.rendition,
    required this.onTap,
    super.key,
  });
  final RenditionsPalette palette;
  final RenditionData rendition;
  final VoidCallback onTap;

  String get _period {
    if (rendition.periodStart.isEmpty && rendition.periodEnd.isEmpty) {
      return 'Sin periodo';
    }
    final start = compactDate(rendition.periodStart);
    final end = compactDate(rendition.periodEnd);
    return start == end ? start : '$start – $end';
  }

  String get _amount {
    final parts = <String>[];
    if (rendition.totalPen != 0) {
      parts.add('S/ ${rendition.totalPen.toStringAsFixed(2)}');
    }
    if (rendition.totalUsd != 0) {
      parts.add('US\$ ${rendition.totalUsd.toStringAsFixed(2)}');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final project = rendition.primaryProjectName.isEmpty
        ? 'Sin proyecto'
        : rendition.primaryProjectName;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          constraints: const BoxConstraints(minHeight: 62),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: palette.border)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: palette.accentSoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  LucideIcons.fileText,
                  size: 18,
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            rendition.code,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.primary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _StatusLabel(palette: palette, value: rendition.status),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$project · $_period',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.secondary,
                        fontSize: 11.5,
                      ),
                    ),
                    if (_amount.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        _amount,
                        style: TextStyle(
                          color: palette.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(LucideIcons.chevronRight, color: palette.tertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.palette, required this.value});
  final RenditionsPalette palette;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: palette.accentSoft,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      value == 'PRESENTADA' ? 'Presentada' : 'Borrador',
      style: TextStyle(
        color: palette.accent,
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class ProjectStrip extends StatelessWidget {
  const ProjectStrip({
    required this.palette,
    required this.projects,
    super.key,
  });
  final RenditionsPalette palette;
  final List<JsonMap> projects;

  String _name(JsonMap project) {
    for (final value in <String>[
      textField(project, 'name'),
      textField(project, 'projectName', 'project_name'),
      textField(project, 'code'),
    ]) {
      if (value.isNotEmpty) return value;
    }
    return 'Proyecto';
  }

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      return Text(
        'No hay proyectos disponibles.',
        style: TextStyle(color: palette.tertiary, fontSize: 12),
      );
    }
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: min(5, projects.length),
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, index) => Container(
          constraints: const BoxConstraints(maxWidth: 190),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(LucideIcons.folder, color: palette.accent, size: 17),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _name(projects[index]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.primary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QuickTarget extends StatelessWidget {
  const QuickTarget({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasized = false,
    this.selected = false,
    super.key,
  });
  final RenditionsPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool emphasized;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: emphasized || selected
                ? palette.accentSoft
                : palette.surface,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: emphasized || selected ? palette.accent : palette.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 21, color: palette.accent),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: palette.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class CompactEmptyState extends StatelessWidget {
  const CompactEmptyState({
    required this.palette,
    required this.searching,
    required this.onNew,
    super.key,
  });
  final RenditionsPalette palette;
  final bool searching;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: <Widget>[
        Icon(
          searching ? LucideIcons.searchX : LucideIcons.fileText,
          color: palette.tertiary,
          size: 22,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            searching
                ? 'No hay coincidencias.'
                : 'Aún no hay rendiciones sincronizadas.',
            style: TextStyle(color: palette.secondary, fontSize: 12),
          ),
        ),
        if (!searching)
          IconButton(
            onPressed: onNew,
            tooltip: 'Nueva rendición',
            icon: Icon(LucideIcons.filePlus, color: palette.accent),
          ),
      ],
    ),
  );
}

class CompactError extends StatelessWidget {
  const CompactError({
    required this.palette,
    required this.message,
    required this.onRetry,
    super.key,
  });
  final RenditionsPalette palette;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Icon(LucideIcons.circleAlert, size: 18, color: palette.error),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: palette.error, fontSize: 11.5),
        ),
      ),
      TextButton(onPressed: onRetry, child: const Text('Reintentar')),
    ],
  );
}

class RenditionSearchAffordance extends StatelessWidget {
  const RenditionSearchAffordance({
    required this.palette,
    required this.expanded,
    required this.controller,
    required this.focusNode,
    required this.onOpen,
    required this.onClose,
    required this.onChanged,
    super.key,
  });
  final RenditionsPalette palette;
  final bool expanded;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: palette.surface,
    elevation: 4,
    shadowColor: Colors.black26,
    borderRadius: BorderRadius.circular(23),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: expanded ? MediaQuery.sizeOf(context).width - 32 : 128,
      height: expanded ? 46 : 40,
      decoration: BoxDecoration(
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(23),
      ),
      child: expanded
          ? TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: palette.primary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar rendiciones',
                hintStyle: TextStyle(color: palette.tertiary),
                prefixIcon: Icon(
                  LucideIcons.search,
                  color: palette.accent,
                  size: 21,
                ),
                suffixIcon: IconButton(
                  onPressed: onClose,
                  tooltip: 'Cerrar búsqueda',
                  icon: Icon(LucideIcons.x, color: palette.secondary, size: 20),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            )
          : Semantics(
              button: true,
              label: 'Buscar rendiciones',
              child: InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(23),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(LucideIcons.search, color: palette.accent, size: 19),
                    const SizedBox(width: 7),
                    Text(
                      'Buscar',
                      style: TextStyle(
                        color: palette.secondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    ),
  );
}
