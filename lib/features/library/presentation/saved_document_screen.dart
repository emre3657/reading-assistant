import 'dart:async';

import 'package:flutter/material.dart';

import '../../listening/presentation/listening_controller.dart';
import '../../listening/presentation/listening_controls.dart';
import '../../listening/services/speech_service.dart';
import '../data/document_store.dart';
import '../data/saved_document.dart';

/// Shows one saved document in reading mode (with listening) and lets the user
/// edit and update the same record. Listening and editing lock each other.
class SavedDocumentScreen extends StatefulWidget {
  const SavedDocumentScreen({
    super.key,
    required this.document,
    this.pageId,
    this.pageNumber,
    this.store,
    this.speechService,
    this.onUpdated,
  });

  final SavedDocument document;

  /// Present when this reader was opened for a specific stored page.
  final int? pageId;
  final int? pageNumber;

  /// Defaults to [DocumentStore.instance].
  final DocumentStore? store;

  /// An injected service remains owned by its caller.
  final SpeechService? speechService;

  /// Called after the record was updated successfully.
  final VoidCallback? onUpdated;

  @override
  State<SavedDocumentScreen> createState() => _SavedDocumentScreenState();
}

enum _ExitChoice { keepEditing, discard, save }

class _SavedDocumentScreenState extends State<SavedDocumentScreen>
    with WidgetsBindingObserver {
  static const _lockedHint = 'Düzenlemek için okumayı durdur';

  late final ListeningController _listening;
  SpeechService? _ownedSpeechService;

  // Owned here; created once and disposed in dispose().
  final _titleController = TextEditingController();
  final _textController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late SavedDocument _saved;
  DocumentCategory _category = DocumentCategory.note;

  bool _editing = false;
  bool _saving = false;
  bool _exitInProgress = false;
  bool _allowPop = false;
  bool _moreControlsOpen = false;
  String? _error;

  /// Changes whenever edit mode starts or ends, so an answer to an older
  /// confirmation never applies to a newer edit.
  int _editSession = 0;

  DocumentStore get _store => widget.store ?? DocumentStore.instance;

  bool get _hasChanges =>
      _titleController.text.trim() != _saved.title ||
      _category != _saved.category ||
      _textController.text != _saved.text;

  @override
  void initState() {
    super.initState();
    _saved = widget.document;

    final speechService =
        widget.speechService ?? (_ownedSpeechService = SpeechService());
    _listening = ListeningController(speechService: speechService);

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _listening.dispose();
    _ownedSpeechService?.dispose();
    _titleController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Temporary inactive states, such as system dialogs, do not stop reading.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _listening.stop();
    }
  }

  void _startListening() {
    if (_editing || _saving || _listening.isActive) return;
    _listening.start(_saved.text);
  }

  void _startEditing() {
    if (_editing || _saving || _listening.isActive) return;

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _editSession++;
      _editing = true;
      _error = null;
      _titleController.text = _saved.title;
      _textController.text = _saved.text;
      _category = _saved.category;
    });
  }

  void _leaveEditing() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _editSession++;
      _editing = false;
      _error = null;
    });
  }

  Future<_ExitChoice?> _confirmExit() {
    return showDialog<_ExitChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        // Repeated system-back presses must not dismiss the confirmation.
        canPop: false,
        child: AlertDialog(
          title: const Text('Kaydedilmemiş değişiklikler var'),
          content: const Text(
            'Çıkmadan önce değişiklikleri kaydetmek ister misin?',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ExitChoice.keepEditing),
              child: const Text('Düzenlemeye devam et'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ExitChoice.discard),
              child: const Text('Kaydetmeden çık'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ExitChoice.save),
              child: const Text('Kaydet ve çık'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestExit() async {
    if (_saving ||
        _exitInProgress ||
        _allowPop ||
        _listening.status == ListeningStatus.stopping) {
      return;
    }
    _exitInProgress = true;
    final session = _editSession;

    try {
      if (_editing && _hasChanges) {
        final choice = await _confirmExit();
        if (!mounted || session != _editSession || _saving) return;
        if (choice == null || choice == _ExitChoice.keepEditing) return;
        if (choice == _ExitChoice.save) {
          final saved = await _persist();
          // Validation/database errors keep the editable form and its text.
          if (!saved || !mounted) return;
        }
      }

      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      if (_listening.isActive) {
        await _listening.stop();
        if (!mounted) return;
        if (_listening.status == ListeningStatus.failed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_listening.message ?? 'Okuma durdurulamadı.'),
            ),
          );
          return;
        }
      }

      // Rebuild PopScope before asking Navigator to leave the route.
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      _exitInProgress = false;
    }
  }

  Future<void> _save() async {
    if (_exitInProgress) return;
    final saved = await _persist();
    if (!saved || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Kayıt güncellendi.')));
  }

  /// Returns true only when a changed record was successfully updated.
  /// An unchanged form leaves editing without a write or success notice.
  Future<bool> _persist() async {
    if (!_editing || _saving) return false;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return false;

    if (!_hasChanges) {
      _leaveEditing();
      return false;
    }

    final title = _titleController.text.trim();
    final category = _category;
    final text = _textController.text;
    setState(() {
      _saving = true;
      _error = null;
    });

    final bool updated;
    try {
      final pageId = widget.pageId;
      if (pageId == null) {
        updated = await _store.update(
          id: _saved.id,
          title: title,
          category: category,
          text: text,
        );
      } else {
        updated = await _store.updatePage(
          documentId: _saved.id,
          pageId: pageId,
          title: title,
          category: category,
          text: text,
        );
      }
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _saving = false;
        _error = 'Kayıt güncellenemedi. Değişikliklerin korundu, tekrar deneyebilirsin.';
      });
      return false;
    }

    if (!mounted) return false;
    if (!updated) {
      setState(() {
        _saving = false;
        _error = 'Kayıt bulunamadı, güncellenemedi. Değişikliklerin korundu.';
      });
      return false;
    }

    setState(() {
      _saved = SavedDocument(
        id: _saved.id,
        title: title,
        category: category,
        text: text,
        createdAt: _saved.createdAt,
      );
      _saving = false;
      _editing = false;
      _error = null;
      _editSession++;
    });
    widget.onUpdated?.call();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _listening,
        _titleController,
        _textController,
      ]),
      builder: (context, _) {
        return PopScope(
          canPop: _allowPop,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_requestExit());
          },
          child: _editing
              ? _buildEditScreen(context)
              : _buildReadScreen(context),
        );
      },
    );
  }

  Widget _buildReadScreen(BuildContext context) {
    final listeningActive = _listening.isActive;
    final document = _saved;

    return Scaffold(
      appBar: AppBar(
        title: Text(document.title),
        leading: BackButton(onPressed: () => unawaited(_requestExit())),
        actions: [
          IconButton(
            tooltip: listeningActive ? _lockedHint : 'Düzenle',
            icon: const Icon(Icons.edit_outlined),
            onPressed: listeningActive ? null : _startEditing,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                document.category.label,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (widget.pageNumber != null) ...[
                const SizedBox(height: 8),
                Text('Sayfa ${widget.pageNumber}'),
              ],
              const SizedBox(height: 16),
              SelectableText(
                document.text,
                textAlign: document.category == DocumentCategory.book
                    ? TextAlign.justify
                    : TextAlign.start,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: document.text.trim().isEmpty
          ? null
          : ListeningControls(
              key: const ValueKey('listening-panel'),
              listening: _listening,
              canStart: !listeningActive,
              onStart: _startListening,
              expanded: _moreControlsOpen,
              onToggleExpanded: () =>
                  setState(() => _moreControlsOpen = !_moreControlsOpen),
            ),
    );
  }

  Widget _buildEditScreen(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kaydı düzenle'),
        leading: BackButton(
          onPressed: _saving ? null : () => unawaited(_requestExit()),
        ),
        actions: [
          TextButton(
            key: const ValueKey('save-document'),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Kaydediliyor…' : 'Kaydet'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('document-title'),
                  controller: _titleController,
                  enabled: !_saving,
                  maxLength: 120,
                  textAlign: TextAlign.start,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Başlık',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Bir başlık yaz.'
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<DocumentCategory>(
                  key: ValueKey(_editSession),
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Kategori',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final category in DocumentCategory.values)
                      DropdownMenuItem(
                        value: category,
                        child: Text(category.label),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _category = value);
                          }
                        },
                ),
                const SizedBox(height: 16),
                if (widget.pageId != null) ...[
                  const Text(
                    'Başlık ve kategori içeriğin tamamına, metin yalnızca bu sayfaya uygulanır.',
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  key: const ValueKey('document-text'),
                  controller: _textController,
                  enabled: !_saving,
                  textAlign: TextAlign.start,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 8,
                  maxLines: null,
                  decoration: const InputDecoration(
                    labelText: 'Metin',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Metin boş olamaz.'
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ),
                ],
                if (_saving) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(semanticsLabel: 'Kaydediliyor'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
