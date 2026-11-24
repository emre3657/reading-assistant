import 'package:material_ui/material_ui.dart';

AppBar selectionAppBar({
  required int count,
  required bool busy,
  required VoidCallback onClose,
  required VoidCallback onDelete,
}) {
  return AppBar(
    leading: IconButton(
      tooltip: 'Seçimden çık',
      onPressed: busy ? null : onClose,
      icon: const Icon(Icons.close),
    ),
    title: Text('$count seçili', overflow: TextOverflow.ellipsis),
    actions: [
      IconButton(
        tooltip: 'Seçilenleri sil',
        onPressed: busy || count == 0 ? null : onDelete,
        icon: const Icon(Icons.delete_outline),
      ),
    ],
  );
}

Widget selectAllCheckbox({
  required int selectedCount,
  required int totalCount,
  required bool busy,
  required VoidCallback onToggle,
}) {
  final bool? value = selectedCount == 0 || totalCount == 0
      ? false
      : selectedCount == totalCount
      ? true
      : null;
  final enabled = !busy && totalCount > 0;
  return Semantics(
    container: true,
    label: 'Tümünü seç',
    checked: value == true,
    mixed: value == null,
    enabled: enabled,
    onTap: enabled ? onToggle : null,
    child: ExcludeSemantics(
      child: CheckboxListTile(
        title: const Text('Tümünü seç'),
        controlAffinity: ListTileControlAffinity.leading,
        value: value,
        tristate: true,
        onChanged: enabled ? (_) => onToggle() : null,
      ),
    ),
  );
}
