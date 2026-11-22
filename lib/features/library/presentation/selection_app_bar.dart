import 'package:material_ui/material_ui.dart';

AppBar selectionAppBar({
  required int count,
  required bool busy,
  required VoidCallback onClose,
  required VoidCallback onSelectAll,
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
        tooltip: 'Tümünü seç',
        onPressed: busy ? null : onSelectAll,
        icon: const Icon(Icons.select_all),
      ),
      IconButton(
        tooltip: 'Seçilenleri sil',
        onPressed: busy || count == 0 ? null : onDelete,
        icon: const Icon(Icons.delete_outline),
      ),
    ],
  );
}
