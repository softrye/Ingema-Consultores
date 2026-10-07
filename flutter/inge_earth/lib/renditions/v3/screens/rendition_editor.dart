import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../renditions_bridge.dart';
import '../../renditions_models.dart';
import '../../v2/received/received_models.dart';
import '../components/nothing_components.dart';
import '../state/rendition_editor_state.dart';

class RenditionEditor extends StatefulWidget {
  const RenditionEditor({
    required this.bridge,
    required this.onSaved,
    required this.onBack,
    required this.onChanged,
    this.rendition,
    this.projectSelectionOnly = false,
    this.onProjectSelected,
    super.key,
  });
  final RenditionsBridge bridge;
  final RenditionData? rendition;
  final bool projectSelectionOnly;
  final ValueChanged<JsonMap>? onProjectSelected;
  final ValueChanged<RenditionData> onSaved;
  final VoidCallback onBack, onChanged;
  @override
  State<RenditionEditor> createState() => RenditionEditorViewState();
}

class RenditionEditorViewState extends State<RenditionEditor> with WidgetsBindingObserver {
  late final RenditionEditorState form = RenditionEditorState(
    baseline: widget.rendition,
  );
  bool saving = false, foldersOpen = false, loading = false;
  String error = '', _space = '';
  List<JsonMap> folders = [];
  final List<JsonMap> _path = [];
  bool get canSave => form.valid && !saving && !loading;
  Timer? _autosave;
  bool _finished = false;
  String get _draftKey => 'header:${widget.rendition?.localId ?? 'new'}';
  @override
  void initState() {
    super.initState();
    if (widget.projectSelectionOnly) form.step = 1;
    final draft = widget.projectSelectionOnly ? <String, dynamic>{}
        : jsonMap(widget.bridge.editorDrafts[_draftKey]);
    if (draft.isNotEmpty) {
      form.start = textField(draft, 'periodStart'); form.end = textField(draft, 'periodEnd');
      form.projects = (draft['projectIds'] as List? ?? []).map((e) => e.toString()).toList();
      form.primary = textField(draft, 'primaryProjectId'); form.folder = textField(draft, 'documentParentNodeId');
      form.folderName = textField(draft, 'folderName'); form.space = textField(draft, 'spaceId');
    }
    WidgetsBinding.instance.addObserver(this);
  }
  Future<void> _persistDraft() async {
    if (widget.projectSelectionOnly || _finished || widget.rendition?.readOnly == true) return;
    try {
      await widget.bridge.command('saveEditorDraft', {'key': _draftKey, 'draft': {
        ...form.payload, 'renditionLocalId': widget.rendition?.localId ?? '', 'folderName': form.folderName,
      }});
    } catch (e) { if (mounted) setState(() => error = 'No se pudo autoguardar: $e'); }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) { _autosave?.cancel(); unawaited(_persistDraft()); }
  }
  @override
  void dispose() {
    _autosave?.cancel(); unawaited(_persistDraft());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  void changed() {
    setState(() {});
    widget.onChanged();
    if (!saving && !_finished) {
      _autosave?.cancel();
      _autosave = Timer(const Duration(milliseconds: 650), _persistDraft);
    }
  }

  bool back() {
    if (saving) return true;
    if (foldersOpen) {
      foldersOpen = false;
      changed();
      return true;
    }
    if (form.step > (widget.projectSelectionOnly ? 1 : 0)) {
      form.step--;
      changed();
      return true;
    }
    return false;
  }

  void goBack() {
    if (!back()) widget.onBack();
  }

  Future<void> pickDate(bool start) async {
    final value = start ? form.start : form.end;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(value) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    if (start) {
      form.start = backendDate(picked);
    } else {
      form.end = backendDate(picked);
    }
    changed();
  }

  Future<void> openLocation() async {
    if (!form.projectsValid || loading || saving) return;
    form.step = 2;
    loading = true;
    error = '';
    changed();
    try {
      final workspace = await widget.bridge.command('projectWorkspace', {
        'projectId': form.primary,
      });
      if (!mounted) return;
      _space = textField(workspace, 'spaceId', 'space_id');
      if (_space.isEmpty) {
        throw const RenditionCommandException(
          'NO_WORKSPACE',
          'El proyecto no tiene un espacio documental disponible.',
        );
      }
      _path.clear();
      await _loadFolders('');
      if (mounted) foldersOpen = true;
    } catch (e) {
      if (mounted) error = e.toString();
    } finally {
      if (mounted) {
        loading = false;
        changed();
      }
    }
  }

  Future<void> _loadFolders(String parent) async {
    final result = await widget.bridge.command('listFolders', {
      'spaceId': _space,
      'parentId': parent,
    });
    if (mounted) folders = jsonRows(result['folders']);
  }

  Future<void> enter(JsonMap folder) async {
    if (loading) return;
    loading = true;
    error = '';
    changed();
    try {
      await _loadFolders(textField(folder, 'id'));
      if (mounted) _path.add(folder);
    } catch (e) {
      if (mounted) error = e.toString();
    } finally {
      if (mounted) {
        loading = false;
        changed();
      }
    }
  }

  Future<void> up() async {
    if (_path.isEmpty || loading) return;
    loading = true;
    error = '';
    changed();
    final parent = _path.length < 2
        ? ''
        : textField(_path[_path.length - 2], 'id');
    try {
      await _loadFolders(parent);
      if (mounted) _path.removeLast();
    } catch (e) {
      if (mounted) error = e.toString();
    } finally {
      if (mounted) {
        loading = false;
        changed();
      }
    }
  }

  Future<void> selectFolder(JsonMap row) async {
    if (loading) return;
    loading = true;
    error = '';
    changed();
    try {
      final result = await widget.bridge.command('folderCapabilities', {
        'spaceId': _space,
        'nodeId': row['id'],
      });
      if (!mounted) return;
      if (result['node_kind'] != 'FOLDER' ||
          result['lifecycle'] != 'ACTIVE' ||
          result['can_accept_child'] != true ||
          result['space_id'] != _space ||
          result['node_id'] != row['id']) {
        throw const RenditionCommandException(
          'INVALID_FOLDER',
          'Esta carpeta no está activa o no admite documentos. Elige otra ubicación.',
        );
      }
      form.folder = textField(row, 'id');
      form.folderName = textField(row, 'name');
      form.space = _space;
      foldersOpen = false;
      if (widget.projectSelectionOnly) {
        widget.onProjectSelected?.call({
          'projectId': form.primary,
          'projectName': textField(widget.bridge.project(form.primary) ?? {}, 'name'),
          'spaceId': _space,
          'documentParentNodeId': form.folder,
          'folderName': form.folderName,
          'folderPath': [..._path.map((r) => textField(r, 'name')), form.folderName].join('/'),
        });
      }
    } catch (e) {
      if (mounted) error = e.toString();
    } finally {
      if (mounted) {
        loading = false;
        changed();
      }
    }
  }

  Future<void> save() async {
    if (!canSave) return;
    saving = true;
    error = '';
    changed();
    try {
      final result = await widget.bridge.command(
        form.baseline == null ? 'create' : 'update',
        form.payload,
      );
      if (!mounted) return;
      final saved = RenditionData(jsonMap(result['current']));
      if (saved.localId.isEmpty ||
          (form.baseline != null && saved.localId != form.baseline!.localId)) {
        throw const RenditionCommandException(
          'IDENTITY_MISMATCH',
          'No se pudo confirmar la identidad guardada.',
        );
      }
      _finished = true;
      _autosave?.cancel();
      await widget.bridge.command('saveEditorDraft', {'key': _draftKey, 'draft': <String, dynamic>{}});
      if (mounted) widget.onSaved(saved);
    } catch (e) {
      if (mounted) error = e.toString();
    } finally {
      if (mounted) {
        saving = false;
        changed();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.bridge.project(form.primary);
    final projectName = project == null
        ? (form.baseline?.primaryProjectName ?? '')
        : textField(project, 'name');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        NothingHeading(
          foldersOpen
              ? 'Ubicación documental'
              : widget.projectSelectionOnly ? 'Proyecto de calicata' : (form.baseline == null
                    ? 'Nueva rendición'
                    : 'Editar rendición'),
          foldersOpen
              ? 'Proyecto: $projectName'
              : 'Configura la información de tu rendición.',
          onBack: goBack,
          trailing: foldersOpen || widget.projectSelectionOnly ? null : Text('${form.step + 1} / 3'),
        ),
        if (loading || saving) const LinearProgressIndicator(minHeight: 2),
        if (error.isNotEmpty) NothingNotice(error),
        if (foldersOpen) ...[
          Row(
            children: [
              IconButton(
                onPressed: _path.isEmpty || loading ? null : up,
                tooltip: 'Subir carpeta',
                icon: const Icon(LucideIcons.arrowUp),
              ),
              Expanded(
                child: Text(
                  _path.isEmpty
                      ? projectName
                      : _path.map((r) => textField(r, 'name')).join(' / '),
                ),
              ),
            ],
          ),
          if (_path.isNotEmpty)
            FilledButton(
              onPressed: loading ? null : () => selectFolder(_path.last),
              child: const Text('Usar esta carpeta'),
            ),
          const SizedBox(height: 12),
          for (final folder in folders)
            NothingCard(
              child: Row(
                children: [
                  const Icon(LucideIcons.folder, size: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Text(textField(folder, 'name'))),
                  IconButton(
                    onPressed: loading ? null : () => selectFolder(folder),
                    tooltip: 'Seleccionar ${textField(folder, 'name')}',
                    icon: const Icon(LucideIcons.check),
                  ),
                  IconButton(
                    onPressed: loading ? null : () => enter(folder),
                    tooltip: 'Abrir ${textField(folder, 'name')}',
                    icon: const Icon(LucideIcons.chevronRight),
                  ),
                ],
              ),
            ),
          if (folders.isEmpty && !loading)
            const NothingNotice(
              'No hay más subcarpetas. Puedes usar la carpeta actual si admite documentos.',
            ),
          const NothingNotice(
            'La raíz del proyecto no es seleccionable. Se verifican permisos y estado al elegir una carpeta.',
          ),
        ] else ...[
          if (!widget.projectSelectionOnly) Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Column(
                    children: [
                      NothingStatus('0${i + 1}', solid: i == form.step),
                      const SizedBox(height: 6),
                      Text(
                        ['Período', 'Proyectos', 'Ubicación'][i],
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (form.step == 0) ...[
            const NothingSection('Período del proyecto'),
            const Text('Indica el período de tu comisión o viaje.'),
            const SizedBox(height: 20),
            _date('Fecha inicial', form.start, () => pickDate(true)),
            _date('Fecha final', form.end, () => pickDate(false)),
            NothingNotice(
              form.periodValid
                  ? 'Los gastos deben estar dentro de este período.'
                  : 'La fecha final debe ser mayor o igual a la fecha inicial.',
            ),
          ],
          if (form.step == 1) ...[
            const NothingSection('Proyectos asociados'),
            for (final p in widget.bridge.projects)
              NothingCard(
                padding: EdgeInsets.zero,
                child: CheckboxListTile(
                  value: form.projects.contains(textField(p, 'id')),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(textField(p, 'name')),
                  subtitle: Text(textField(p, 'code')),
                  secondary: form.primary == textField(p, 'id')
                      ? const NothingStatus('PRINCIPAL', solid: true)
                      : null,
                  onChanged: saving
                      ? null
                      : (_) {
                          form.toggleProject(textField(p, 'id'));
                          if (widget.projectSelectionOnly) {
                            form.projects = [textField(p, 'id')];
                            form.setPrimary(textField(p, 'id'));
                          }
                          changed();
                        },
                ),
              ),
            if (widget.bridge.projects.isEmpty)
              const NothingNotice(
                'No hay proyectos cargados. Sincroniza para consultar tus proyectos disponibles.',
              ),
            const NothingNotice(
              'El primer proyecto seleccionado será el principal. Puedes cambiarlo en el siguiente paso.',
            ),
          ],
          if (form.step == 2) ...[
            const NothingSection('Ubicación documental'),
            DropdownButtonFormField<String>(
              icon: const Icon(LucideIcons.chevronDown, size: 20),
              initialValue: form.projects.contains(form.primary)
                  ? form.primary
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Proyecto principal',
              ),
              items: [
                for (final id in form.projects)
                  DropdownMenuItem(
                    value: id,
                    child: Text(
                      textField(widget.bridge.project(id) ?? {}, 'name').isEmpty
                          ? id
                          : textField(widget.bridge.project(id)!, 'name'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: saving
                  ? null
                  : (id) {
                      if (id != null) {
                        form.setPrimary(id);
                        changed();
                      }
                    },
            ),
            const SizedBox(height: 18),
            NothingCard(
              onTap: loading || saving ? null : openLocation,
              child: Row(
                children: [
                  const Icon(LucideIcons.folder),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      form.folder.isEmpty
                          ? 'Seleccionar carpeta'
                          : (form.folderName.isEmpty
                                ? 'Carpeta guardada'
                                : form.folderName),
                    ),
                  ),
                  const Icon(LucideIcons.chevronRight),
                ],
              ),
            ),
            const NothingNotice(
              'Esta carpeta será el destino de la rendición y sus documentos.',
            ),
          ],
          const SizedBox(height: 18),
          if (!widget.projectSelectionOnly || form.step < 2) FilledButton(
            onPressed: saving
                ? null
                : form.step == 2
                ? (canSave ? save : null)
                : (form.step == 0 ? form.periodValid : form.projectsValid)
                ? () {
                    form.step++;
                    changed();
                  }
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  form.step == 2
                      ? (saving
                            ? 'Guardando…'
                            : form.baseline == null
                            ? 'Guardar borrador'
                            : 'Guardar cambios')
                      : 'Continuar',
                ),
                const SizedBox(width: 12),
                const Icon(LucideIcons.arrowRight, size: 20),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _date(String label, String value, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: InkWell(
      onTap: saving ? null : onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(LucideIcons.calendarDays, size: 20),
        ),
        child: Text(receivedDate(value)),
      ),
    ),
  );
}
