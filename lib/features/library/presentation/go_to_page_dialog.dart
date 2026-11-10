import 'package:flutter/material.dart';

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
    return AlertDialog(
      title: const Text('Sayfaya git'),
      content: SingleChildScrollView(
        child: Form(
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
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        TextButton(onPressed: _submit, child: const Text('Git')),
      ],
    );
  }
}
