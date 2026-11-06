import 'dart:async';

import 'package:flutter/material.dart';

import '../../listening/presentation/listening_controller.dart';
import '../../listening/presentation/listening_controls.dart';
import '../../listening/presentation/reading_settings_dialog.dart';
import '../../listening/services/speech_service.dart';
import '../data/document_page.dart';
import '../data/document_store.dart';
import '../data/saved_document.dart';
import 'page_navigation_bar.dart';

/// Reads and edits one page. Shared title/category are edited separately
/// at content level. Listening and editing lock each other.
class SavedDocumentScreen extends StatefulWidget {
  const SavedDocumentScreen({
    super.key,
    required this.document,
    this.pageId,
    this.pageNumber,
    this.initialSentence,
    this.store,
    this.speechService,
    this.onUpdated,
  });

  final SavedDocument document;

  /// Present when this reader was opened for a specific stored page.
  final int? pageId;
  final int? pageNumber;
  final int? initialSentence;

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
  final _textController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  late SavedDocument _saved;

  /// Stored pages in database order; null until loaded or when unavailable.
  final _pageList = ValueNotifier<List<DocumentPage>?>(null);
  List<DocumentPage>? get _pages => _pageList.value;
  set _pages(List<DocumentPage>? value) => _pageList.value = value;
  int? _pageId;
  int? _pageNumber;

  bool _editing = false;
  bool _saving = false;
  bool _transitioning = false;
  bool _exitInProgress = false;
  bool _allowPop = false;
  bool _panelExpanded = true;
  int? _resumeSentence;
  bool _positionErrorShown = false;

  /// Screen-session preference only; never saved.
  final _autoNextPage = ValueNotifier<bool>(false);
  bool _autoPending = false;
  ListeningStatus _lastStatus = ListeningStatus.idle;

  /// Identifies the current automatic move; cancel, dispose and background
  /// change it so late results are ignored.
  int _autoToken = 0;
  String? _error;

  /// Changes whenever edit mode starts or ends, so an answer to an older
  /// confirmation never applies to a newer edit.
  int _editSession = 0;

  DocumentStore get _store => widget.store ?? DocumentStore.instance;

  bool get _hasChanges => _textController.text != _saved.text;

  int get _pageIndex => _pages?.indexWhere((page) => page.id == _pageId) ?? -1;

  bool get _hasPageNavigation => _pageIndex >= 0;

  @override
  void initState() {
    super.initState();
    _saved = widget.document;
    _pageId = widget.pageId;
    _pageNumber = widget.pageNumber;
    _resumeSentence = widget.initialSentence;
    if (_pageId != null) unawaited(_loadPages());

    final speechService =
        widget.speechService ?? (_ownedSpeechService = SpeechService());
    _listening = ListeningController(
      speechService: speechService,
      onSentenceStarted: _saveListeningPosition,
    );
    _listening.addListener(_onListeningChanged);

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _autoToken++;
    WidgetsBinding.instance.removeObserver(this);
    _listening.removeListener(_onListeningChanged);
    _listening.dispose();
    _ownedSpeechService?.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _pageList.dispose();
    _autoNextPage.dispose();
    super.dispose();
  }

  Future<void> _loadPages() async {
    try {
      final pages = await _store.pages(_saved.id);
      if (!mounted) return;
      setState(() => _pages = pages);
    } catch (_) {
      // Without a page list the navigation row stays hidden.
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Moves to the previous (-1) or next (+1) page in stored order.
  Future<void> _navigate(int delta) async {
    if (_transitioning ||
        _saving ||
        _exitInProgress ||
        _listening.status == ListeningStatus.stopping) {
      return;
    }
    setState(() => _transitioning = true);
    final session = _editSession;

    try {
      if (_editing && _hasChanges) {
        final choice = await _confirmChanges(
          content:
              'Sayfayı değiştirmeden önce değişiklikleri kaydetmek '
              'ister misin?',
          discardLabel: 'Kaydetmeden geç',
          saveLabel: 'Kaydet ve geç',
        );
        if (!mounted || session != _editSession) return;
        if (choice == null || choice == _ExitChoice.keepEditing) return;
        if (choice == _ExitChoice.save) {
          final saved = await _persist();
          if (!saved || !mounted) return;
        }
      }

      FocusManager.instance.primaryFocus?.unfocus();
      if (_listening.isActive) {
        await _listening.stop();
        if (!mounted) return;
        if (_listening.status == ListeningStatus.failed) {
          _showMessage(_listening.message ?? 'Okuma durdurulamadı.');
          return;
        }
      }

      final pages = await _store.pages(_saved.id);
      if (!mounted) return;
      final index = pages.indexWhere((page) => page.id == _pageId);
      if (index < 0) {
        _showMessage('Bu sayfa bulunamadı. Sayfa değiştirilemedi.');
        return;
      }
      final targetIndex = index + delta;
      if (targetIndex < 0 || targetIndex >= pages.length) {
        setState(() => _pages = pages);
        return;
      }
      _applyPage(pages, targetIndex);
    } catch (_) {
      if (mounted) {
        _showMessage('Sayfa açılamadı. Mevcut sayfa korundu.');
      }
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  /// Shows the page at [index] of [pages] and scrolls its text to the top.
  /// Does not touch the database.
  void _applyPage(
    List<DocumentPage> pages,
    int index, {
    VoidCallback? alsoSet,
  }) {
    final target = pages[index];
    setState(() {
      _pages = pages;
      _pageId = target.id;
      _pageNumber = index + 1;
      _resumeSentence = null;
      _saved = SavedDocument(
        id: _saved.id,
        title: _saved.title,
        category: _saved.category,
        text: target.text,
        createdAt: _saved.createdAt,
      );
      _editing = false;
      _error = null;
      _editSession++;
      alsoSet?.call();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  void _onListeningChanged() {
    final status = _listening.status;
    final finishedNow =
        status == ListeningStatus.completed &&
        _lastStatus != ListeningStatus.completed;
    _lastStatus = status;
    if (finishedNow && _pageId != null) {
      unawaited(_recordCompletion(_pageId!));
    }
    // Only a natural end of the last sentence reaches `completed`; stop,
    // pause, errors and jumps end in other states.
    if (finishedNow &&
        _autoNextPage.value &&
        !_editing &&
        !_saving &&
        !_transitioning &&
        !_exitInProgress) {
      unawaited(_advanceToNextPage());
    }
  }

  void _saveListeningPosition(int sentenceIndex) {
    final pageId = _pageId;
    if (pageId == null) return;
    unawaited(_savePosition(pageId, sentenceIndex, _saved.text));
  }

  Future<void> _savePosition(int pageId, int index, String text) async {
    try {
      await _store.saveReadingPosition(
        documentId: _saved.id,
        pageId: pageId,
        sentenceIndex: index,
        pageText: text,
      );
    } catch (_) {
      _showPositionError();
    }
  }

  Future<void> _recordCompletion(int pageId) async {
    try {
      await _store.completeReadingPage(documentId: _saved.id, pageId: pageId);
    } catch (_) {
      _showPositionError();
    }
  }

  void _showPositionError() {
    if (!mounted || _positionErrorShown) return;
    _positionErrorShown = true;
    _showMessage('Okuma konumu kaydedilemedi. Okumaya devam edebilirsin.');
  }

  /// Cancels a pending automatic move. A late result of the cancelled move
  /// compares its token and does nothing.
  void _cancelAutoAdvance() {
    _autoToken++;
    if (_autoPending && mounted) {
      setState(() {
        _autoPending = false;
        _transitioning = false;
      });
    }
  }

  void _setAutoNextPage(bool value) {
    if (value == _autoNextPage.value) return;
    if (!value) _cancelAutoAdvance();
    _autoNextPage.value = value;
  }

  /// Opens the next stored page and reads it from its first sentence after the
  /// previous page was read to its end.
  Future<void> _advanceToNextPage() async {
    final current = _pageIndex;
    // No page list (or already the last page): the session simply ends.
    if (current < 0 || current >= _pages!.length - 1) return;

    final token = ++_autoToken;
    setState(() {
      _autoPending = true;
      _transitioning = true;
    });

    bool stale() => !mounted || token != _autoToken;

    try {
      final pages = await _store.pages(_saved.id);
      if (stale()) return;
      final index = pages.indexWhere((page) => page.id == _pageId);
      if (index < 0) {
        _showMessage('Bu sayfa bulunamadı. Otomatik devam durdu.');
        return;
      }
      if (index >= pages.length - 1) {
        setState(() => _pages = pages);
        return;
      }

      final text = pages[index + 1].text;
      final readable = text.trim().isNotEmpty;
      _applyPage(
        pages,
        index + 1,
        alsoSet: () {
          _autoPending = false;
          _transitioning = false;
        },
      );
      if (readable) {
        unawaited(_listening.start(text));
      } else {
        _showMessage('Bu sayfa boş olduğu için otomatik okuma durdu.');
      }
    } catch (_) {
      if (!stale()) {
        _showMessage('Sonraki sayfa açılamadı. Otomatik okuma durdu.');
      }
    } finally {
      if (!stale() && _autoPending) {
        setState(() {
          _autoPending = false;
          _transitioning = false;
        });
      }
    }
  }

  Widget? _buildPageNavigation() {
    if (!_hasPageNavigation) return null;
    final index = _pageIndex;
    final total = _pages!.length;
    final blocked =
        _transitioning ||
        _saving ||
        _listening.status == ListeningStatus.stopping;
    return PageNavigationBar(
      current: index + 1,
      total: total,
      onPrevious: blocked || index == 0 ? null : () => _navigate(-1),
      onNext: blocked || index == total - 1 ? null : () => _navigate(1),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Temporary inactive states, such as system dialogs, do not stop reading.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _cancelAutoAdvance();
      _listening.stop();
    }
  }

  void _startListening() {
    if (_editing || _saving || _transitioning || _listening.isActive) return;
    final initialSentence = _resumeSentence ?? 0;
    _resumeSentence = null;
    _listening.start(_saved.text, initialSentence: initialSentence);
  }

  void _startEditing() {
    if (_editing || _saving || _transitioning || _listening.isActive) return;

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _editSession++;
      _editing = true;
      _error = null;
      _textController.text = _saved.text;
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

  Future<_ExitChoice?> _confirmChanges({
    String content = 'Çıkmadan önce değişiklikleri kaydetmek ister misin?',
    String discardLabel = 'Kaydetmeden çık',
    String saveLabel = 'Kaydet ve çık',
  }) {
    return showDialog<_ExitChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        // Repeated system-back presses must not dismiss the confirmation.
        canPop: false,
        child: AlertDialog(
          title: const Text('Kaydedilmemiş değişiklikler var'),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ExitChoice.keepEditing),
              child: const Text('Düzenlemeye devam et'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ExitChoice.discard),
              child: Text(discardLabel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ExitChoice.save),
              child: Text(saveLabel),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestExit() async {
    if (_saving ||
        _transitioning ||
        _exitInProgress ||
        _allowPop ||
        _listening.status == ListeningStatus.stopping) {
      return;
    }
    _exitInProgress = true;
    final session = _editSession;

    try {
      if (_editing && _hasChanges) {
        final choice = await _confirmChanges();
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

    final text = _textController.text;
    setState(() {
      _saving = true;
      _error = null;
    });

    final bool updated;
    try {
      // Legacy callers without a page id are safe only for single-page content.
      var pageId = _pageId;
      if (pageId == null) {
        final pages = await _store.pages(_saved.id);
        if (pages.length != 1) {
          throw StateError('An explicit page id is required.');
        }
        pageId = pages.single.id;
      }
      updated = await _store.updatePageText(
        documentId: _saved.id,
        pageId: pageId,
        text: text,
      );
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
        title: _saved.title,
        category: _saved.category,
        text: text,
        createdAt: _saved.createdAt,
      );
      _resumeSentence = null;
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
      listenable: Listenable.merge([_listening, _textController]),
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
            tooltip: 'Okuma ayarları',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => showReadingSettings(
              context,
              listening: _listening,
              autoNextPage: _autoNextPage,
              onAutoNextPageChanged: _setAutoNextPage,
              pageChanges: _pageList,
              showAutoNextPage: () => _hasPageNavigation && _pages!.length > 1,
            ),
          ),
          IconButton(
            tooltip: listeningActive ? _lockedHint : 'Düzenle',
            icon: const Icon(Icons.edit_outlined),
            onPressed: listeningActive || _transitioning ? null : _startEditing,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                document.category.label,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (_pageNumber != null) ...[
                const SizedBox(height: 8),
                Text('Sayfa $_pageNumber'),
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
      bottomNavigationBar: _buildBottomBar(document, listeningActive),
    );
  }

  Widget? _buildBottomBar(SavedDocument document, bool listeningActive) {
    final pageNavigation = _buildPageNavigation();
    final controls = document.text.trim().isEmpty
        ? null
        : ListeningControls(
            key: const ValueKey('listening-panel'),
            listening: _listening,
            canStart: !listeningActive && !_transitioning,
            onStart: _startListening,
            expanded: _panelExpanded,
            onToggleExpanded: () =>
                setState(() => _panelExpanded = !_panelExpanded),
            nextPagePending: _autoPending,
            onCancelNextPage: _cancelAutoAdvance,
          );
    if (pageNavigation == null) {
      return controls == null ? null : ListeningSurface(child: controls);
    }
    if (controls == null) return SafeArea(child: pageNavigation);
    return ListeningSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [pageNavigation, controls],
      ),
    );
  }

  Widget _buildEditScreen(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sayfa metnini düzenle'),
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
      bottomNavigationBar: _buildPageNavigation() == null
          ? null
          : SafeArea(child: _buildPageNavigation()!),
    );
  }
}
