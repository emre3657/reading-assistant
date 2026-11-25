import 'package:material_ui/material_ui.dart';

class GoToPageDialog extends StatefulWidget {
  const GoToPageDialog({super.key, required this.total});

  final int total;

  @override
  State<GoToPageDialog> createState() => _GoToPageDialogState();
}

class _GoToPageDialogState extends State<GoToPageDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_submitted && _formKey.currentState!.validate()) {
      _submitted = true;
      Navigator.of(context).pop(int.parse(_controller.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final form = Form(
      key: _formKey,
      child: TextFormField(
        key: const ValueKey('page-number-input'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Sayfa numarası',
          helperText: 'Geçerli aralık: 1–${widget.total}',
        ),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (text.isEmpty) return 'Sayfa numarası girin.';
          if (!RegExp(r'^[0-9]+$').hasMatch(text)) {
            return 'Geçerli bir tam sayı girin.';
          }
          final number = int.tryParse(text);
          if (number == null || number < 1 || number > widget.total) {
            return '1–${widget.total} arasında bir sayfa numarası girin.';
          }
          return null;
        },
        onFieldSubmitted: (_) => _submit(),
      ),
    );
    final actions = [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Vazgeç'),
      ),
      TextButton(onPressed: _submit, child: const Text('Git')),
    ];
    return AlertDialog(
      insetPadding: landscape
          ? const EdgeInsets.symmetric(horizontal: 24, vertical: 8)
          : null,
      scrollable: landscape,
      title: const Text('Sayfaya git'),
      content: landscape
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                form,
                const SizedBox(height: 8),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: actions,
                ),
              ],
            )
          : SingleChildScrollView(child: form),
      actions: landscape ? null : actions,
    );
  }
}
