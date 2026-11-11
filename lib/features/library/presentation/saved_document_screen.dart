import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../listening/presentation/listening_controller.dart';
import '../../listening/presentation/listening_controls.dart';
import '../../listening/presentation/reading_settings_dialog.dart';
import '../../listening/presentation/reading_preferences.dart';
import '../../listening/presentation/sentence_highlight.dart';
import '../../listening/presentation/sentence_follow.dart';
import '../../listening/services/sentence_splitter.dart';
import '../../listening/services/speech_service.dart';
import '../data/document_page.dart';
import '../data/document_store.dart';
import '../data/saved_document.dart';
import 'page_navigation_bar.dart';
import 'go_to_page_dialog.dart';

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

class _SentenceBubbleLayout extends SingleChildLayoutDelegate {
  const _SentenceBubbleLayout(this.line);

  final Rect line;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    const gap = 4.0;
    final left = (line.center.dx - childSize.width / 2).clamp(
      0.0,
      size.width - childSize.width,
    );
    final above = line.top - childSize.height - gap;
    final top = above >= 0 ? above : line.bottom + gap;
    return Offset(left, top.clamp(0.0, size.height - childSize.height));
  }

  @override
  bool shouldRelayout(_SentenceBubbleLayout oldDelegate) =>
      line != oldDelegate.line;
}

class _SavedDocumentScreenState extends State<SavedDocumentScreen>
    with WidgetsBindingObserver {
  static const _lockedHint = 'Düzenlemek için okumayı durdur';

  late final ListeningController _listening;
  ReadingPreferences? _preferences;
  int _preferencesErrorRevision = 0;
  SpeechService? _ownedSpeechService;

  // Owned here; created once and disposed in dispose().
  final _textController = TextEditingController();
  final _readController = HighlightingTextEditingController(
    neutralReading: true,
  );
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _followKey = GlobalKey<SentenceFollowState>();
  final _followTextKey = GlobalKey();
  final _readerBodyKey = GlobalKey();
  final _sentenceTapGroup = Object();

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
  bool _pageDialogOpen = false;
  bool _exitInProgress = false;
  bool _allowPop = false;
  bool _panelExpanded = true;
  int? _resumeSentence;
  int? _selectedSentence;
  int? _pendingReadFrom;
  int? _selectedOffset;
  Rect? _selectedLine;
  Size? _readerSize;
  bool _anchorUpdateScheduled = false;
  int _readFromToken = 0;
  int? _tapPointer;
  Offset? _tapOrigin;
  Timer? _tapTimer;
  bool _tapMoved = false;
  bool _positionErrorShown = false;

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
    _readController.text = _saved.text;
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
    _readController.attachListening(_listening);
    _listening.addListener(_onListeningChanged);
    _scrollController.addListener(_scheduleAnchorUpdate);

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final preferences = ReadingPreferencesScope.of(context);
    if (_preferences == preferences) return;
    _preferences?.removeListener(_onPreferencesChanged);
    _preferences = preferences;
    preferences.addListener(_onPreferencesChanged);
    if (preferences.ready) {
      unawaited(_listening.setSpeed(preferences.speed));
    } else {
      unawaited(preferences.load());
    }
  }

  void _onPreferencesChanged() {
    final preferences = _preferences!;
    if (preferences.ready && _listening.speed != preferences.speed) {
      unawaited(_listening.setSpeed(preferences.speed));
    }
    if (!preferences.autoNextPage && _autoPending) _cancelAutoAdvance();
    _scheduleAnchorUpdate();
    if (mounted) setState(() {});
    if (_preferencesErrorRevision != preferences.errorRevision) {
      _preferencesErrorRevision = preferences.errorRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showPreferencesError();
      });
    }
  }

  void _showPreferencesError() {
    final preferences = _preferences;
    if (!mounted ||
        preferences == null ||
        ModalRoute.of(context)?.isCurrent != true ||
        !preferences.claimError(preferences.errorRevision)) {
      return;
    }
    _showMessage(preferences.errorMessage!);
  }

  Future<void> _openReadingSettings() async {
    await showReadingSettings(
      context,
      preferences: _preferences!,
      pageChanges: _pageList,
      showAutoNextPage: () => _hasPageNavigation && _pages!.length > 1,
    );
    if (mounted) _showPreferencesError();
  }

  @override
  void dispose() {
    _autoToken++;
    _readFromToken++;
    _tapTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _listening.removeListener(_onListeningChanged);
    _preferences?.removeListener(_onPreferencesChanged);
    _readController.dispose();
    _listening.dispose();
    _ownedSpeechService?.dispose();
    _textController.dispose();
    _scrollController.removeListener(_scheduleAnchorUpdate);
    _scrollController.dispose();
    _pageList.dispose();
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

  /// Moves by a relative offset or a 1-based number in stored order.
  Future<void> _navigate({int? delta, int? pageNumber}) async {
    assert((delta == null) != (pageNumber == null));
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
      final targetIndex = pageNumber == null ? index + delta! : pageNumber - 1;
      if (targetIndex < 0 || targetIndex >= pages.length) {
        setState(() => _pages = pages);
        if (pageNumber != null) {
          _showMessage('Bu sayfa bulunamadı. Sayfa değiştirilemedi.');
        }
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
    _readFromToken++;
    _clearSentenceSelection();
    _readController.text = target.text;
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
    if (status == ListeningStatus.failed || status == ListeningStatus.idle) {
      _pendingReadFrom = null;
    }
    if (finishedNow && _pageId != null) {
      unawaited(_recordCompletion(_pageId!));
    }
    // Only a natural end of the last sentence reaches `completed`; stop,
    // pause, errors and jumps end in other states.
    if (finishedNow &&
        (_preferences?.autoNextPage ?? false) &&
        !_editing &&
        !_saving &&
        !_transitioning &&
        !_exitInProgress) {
      unawaited(_advanceToNextPage());
    }
  }

  void _saveListeningPosition(int sentenceIndex) {
    if (_pendingReadFrom == sentenceIndex) {
      _pendingReadFrom = null;
      if (mounted && _selectedSentence == sentenceIndex) {
        setState(_clearSentenceSelection);
      }
    }
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
        _exitInProgress ||
        _listening.status == ListeningStatus.stopping;
    return PageNavigationBar(
      current: index + 1,
      total: total,
      onPrevious: blocked || index == 0 ? null : () => _navigate(delta: -1),
      onNext: blocked || index == total - 1 ? null : () => _navigate(delta: 1),
      onGoToPage: blocked || _pageDialogOpen ? null : _showGoToPage,
    );
  }

  Future<void> _showGoToPage() async {
    if (_pageDialogOpen ||
        _transitioning ||
        _saving ||
        _exitInProgress ||
        _listening.status == ListeningStatus.stopping ||
        !_hasPageNavigation ||
        _pages!.length <= 1) {
      return;
    }
    _pageDialogOpen = true;
    int? number;
    try {
      number = await showDialog<int>(
        context: context,
        builder: (_) => GoToPageDialog(total: _pages!.length),
      );
    } finally {
      _pageDialogOpen = false;
    }
    if (!mounted || number == null || number == _pageIndex + 1) return;
    await _navigate(pageNumber: number);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Temporary inactive states, such as system dialogs, do not stop reading.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _readFromToken++;
      _cancelAutoAdvance();
      _listening.stop();
    }
  }

  void _startListening() {
    if (_editing ||
        _saving ||
        _transitioning ||
        _listening.isActive ||
        !(_preferences?.ready ?? false)) {
      return;
    }
    _beginListening(_resumeSentence ?? 0);
  }

  void _beginListening(int initialSentence) {
    _resumeSentence = null;
    _followKey.currentState?.newSession();
    _listening.start(_saved.text, initialSentence: initialSentence);
  }

  void _clearSentenceSelection() {
    _tapPointer = null;
    _tapOrigin = null;
    _tapTimer?.cancel();
    _selectedSentence = null;
    _selectedOffset = null;
    _selectedLine = null;
    _readController.selectSentence(null);
  }

  void _dismissSentenceSelection() {
    if (_selectedSentence != null && mounted) {
      setState(_clearSentenceSelection);
    }
  }

  RenderEditable? _readerEditable() {
    RenderEditable? editable;
    void visit(Element element) {
      if (editable != null) return;
      if (element is StatefulElement && element.state is EditableTextState) {
        editable = (element.state as EditableTextState).renderEditable;
        return;
      }
      element.visitChildren(visit);
    }

    _followTextKey.currentContext?.visitChildElements(visit);
    return editable;
  }

  void _scheduleAnchorUpdate() {
    if (_selectedOffset == null || _anchorUpdateScheduled) return;
    _anchorUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorUpdateScheduled = false;
      if (!mounted || _selectedOffset == null) return;
      final render = _readerEditable();
      final body = _readerBodyKey.currentContext?.findRenderObject();
      final offset = _selectedOffset!;
      if (render == null ||
          !render.attached ||
          body is! RenderBox ||
          !body.attached ||
          offset >= _saved.text.length) {
        return;
      }
      var end = offset + 1;
      final unit = _saved.text.codeUnitAt(offset);
      if (unit >= 0xD800 && unit <= 0xDBFF && end < _saved.text.length) end++;
      final boxes = render.getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: end),
      );
      if (boxes.isEmpty) return;
      final box = boxes.first.toRect();
      final line = Rect.fromPoints(
        body.globalToLocal(render.localToGlobal(box.topLeft)),
        body.globalToLocal(render.localToGlobal(box.bottomRight)),
      );
      if (line.bottom <= 0 || line.top >= body.size.height) {
        _dismissSentenceSelection();
      } else if (_selectedLine != line) {
        setState(() => _selectedLine = line);
      }
    });
  }

  void _onTextPointerDown(PointerDownEvent event) {
    if (_tapPointer != null || event.buttons != kPrimaryButton) {
      _tapMoved = true;
      return;
    }
    _tapPointer = event.pointer;
    _tapOrigin = event.position;
    _tapMoved = false;
    _tapTimer?.cancel();
    _tapTimer = Timer(kLongPressTimeout, () {
      _tapMoved = true;
      _dismissSentenceSelection();
    });
  }

  void _onTextPointerMove(PointerMoveEvent event) {
    if (event.pointer == _tapPointer &&
        (event.position - _tapOrigin!).distance > kTouchSlop) {
      _tapMoved = true;
      _dismissSentenceSelection();
    }
  }

  void _onTextPointerUp(PointerUpEvent event) {
    if (event.pointer != _tapPointer) return;
    final isTap = !_tapMoved;
    _tapTimer?.cancel();
    _tapPointer = null;
    _tapOrigin = null;
    if (isTap) _selectSentenceAt(event.position);
  }

  void _onTextPointerCancel(PointerCancelEvent event) {
    if (event.pointer == _tapPointer) {
      _tapPointer = null;
      _tapOrigin = null;
      _tapTimer?.cancel();
    }
  }

  void _selectSentenceAt(Offset globalPosition) {
    if (_editing || _transitioning || _saving || _exitInProgress) return;
    final render = _readerEditable();
    if (render == null || !render.attached) return;
    final text = _saved.text;
    final position = render.getPositionForPoint(globalPosition).offset;
    final local = render.globalToLocal(globalPosition);
    int? hit;
    Rect? hitBox;
    for (final offset in [position, position - 1]) {
      if (offset < 0 || offset >= text.length) continue;
      var start = offset;
      var end = offset + 1;
      final unit = text.codeUnitAt(offset);
      if (unit >= 0xDC00 && unit <= 0xDFFF && start > 0) start--;
      if (unit >= 0xD800 && unit <= 0xDBFF && end < text.length) end++;
      final boxes = render.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      );
      for (final box in boxes) {
        if (box.toRect().contains(local)) {
          hit = start;
          hitBox = box.toRect();
          break;
        }
      }
      if (hit != null) break;
    }
    if (hit == null || text[hit].trim().isEmpty) {
      _dismissSentenceSelection();
      return;
    }
    final sentences = splitSentences(text);
    final index = sentences.indexWhere(
      (sentence) => hit! >= sentence.start && hit < sentence.end,
    );
    if (index < 0) return;
    if (_selectedSentence == index) {
      _dismissSentenceSelection();
      return;
    }
    final body = _readerBodyKey.currentContext?.findRenderObject();
    if (body is! RenderBox || !body.attached || hitBox == null) return;
    final topLeft = body.globalToLocal(render.localToGlobal(hitBox.topLeft));
    final bottomRight = body.globalToLocal(
      render.localToGlobal(hitBox.bottomRight),
    );
    setState(() {
      _selectedSentence = index;
      _selectedOffset = hit;
      _selectedLine = Rect.fromPoints(topLeft, bottomRight);
      _readController.selectSentence(sentences[index]);
    });
  }

  Future<void> _readFromSelection() async {
    final index = _selectedSentence;
    if (index == null ||
        _editing ||
        _saving ||
        _exitInProgress ||
        (_transitioning && !_autoPending) ||
        !(_preferences?.ready ?? false) ||
        (_listening.isActive && !_listening.canStop)) {
      return;
    }
    if (_autoPending) _cancelAutoAdvance();
    final token = ++_readFromToken;
    final pageId = _pageId;
    final text = _saved.text;
    setState(() => _transitioning = true);
    try {
      if (_listening.isActive) {
        await _listening.stop();
        if (!mounted || token != _readFromToken) return;
        if (_listening.status == ListeningStatus.failed) {
          _showMessage(_listening.message ?? 'Okuma durdurulamadı.');
          return;
        }
      }
      if (!mounted ||
          token != _readFromToken ||
          _pageId != pageId ||
          _saved.text != text ||
          _selectedSentence != index) {
        return;
      }
      _pendingReadFrom = index;
      _beginListening(index);
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  void _startEditing() {
    if (_editing || _saving || _transitioning || _listening.isActive) return;

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _readFromToken++;
      _clearSentenceSelection();
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

  Future<void> _cancelEditing() async {
    if (_saving || _exitInProgress) return;
    _exitInProgress = true;
    final session = _editSession;
    try {
      if (_hasChanges) {
        final choice = await _confirmChanges(
          content: 'Düzenlemeyi bırakmadan önce değişiklikleri kaydetmek ister misin?',
          discardLabel: 'Kaydetmeden vazgeç',
          saveLabel: 'Kaydet ve bitir',
        );
        if (!mounted || session != _editSession || _saving) return;
        if (choice == null || choice == _ExitChoice.keepEditing) return;
        if (choice == _ExitChoice.save) {
          await _persist();
          return;
        }
      }
      if (mounted) _leaveEditing();
    } finally {
      _exitInProgress = false;
    }
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
      _readController.text = text;
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
            onPressed: _openReadingSettings,
          ),
          IconButton(
            tooltip: listeningActive ? _lockedHint : 'Düzenle',
            icon: const Icon(Icons.edit_outlined),
            onPressed: listeningActive || _transitioning ? null : _startEditing,
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            if (_readerSize != size) {
              _readerSize = size;
              _scheduleAnchorUpdate();
            }
            return Stack(
              key: _readerBodyKey,
              children: [
                SentenceFollow(
                  key: _followKey,
                  listening: _listening,
                  preferences: _preferences!,
                  textController: _readController,
                  textKey: _followTextKey,
                  scrollController: _scrollController,
                  followTextSizeChanges: true,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is UserScrollNotification &&
                          notification.direction != ScrollDirection.idle) {
                        _dismissSentenceSelection();
                      }
                      return false;
                    },
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
                          KeyedSubtree(
                            key: _followTextKey,
                            child: TapRegion(
                              groupId: _sentenceTapGroup,
                              onTapOutside: (_) => _dismissSentenceSelection(),
                              child: Listener(
                                onPointerDown: _onTextPointerDown,
                                onPointerMove: _onTextPointerMove,
                                onPointerUp: _onTextPointerUp,
                                onPointerCancel: _onTextPointerCancel,
                                child: TextField(
                                  key: const ValueKey('saved-reading-text'),
                                  controller: _readController,
                                  readOnly: true,
                                  showCursor: false,
                                  maxLines: null,
                                  decoration: const InputDecoration.collapsed(
                                    hintText: '',
                                  ),
                                  textAlign:
                                      document.category == DocumentCategory.book
                                      ? TextAlign.justify
                                      : TextAlign.start,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        fontSize:
                                            (Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.fontSize ??
                                                16) *
                                            _preferences!.textSize.multiplier,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_selectedLine case final line?)
                  CustomSingleChildLayout(
                    delegate: _SentenceBubbleLayout(line),
                    child: TapRegion(
                      groupId: _sentenceTapGroup,
                      child: Material(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHigh,
                        elevation: 4,
                        borderRadius: BorderRadius.circular(12),
                        child: TextButton.icon(
                          key: const ValueKey('read-from-sentence'),
                          onPressed:
                              (!_transitioning || _autoPending) &&
                                  !_saving &&
                                  !_exitInProgress &&
                                  (_preferences?.ready ?? false) &&
                                  (!listeningActive || _listening.canStop)
                              ? _readFromSelection
                              : null,
                          icon: const Icon(Icons.play_arrow),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          label: const Text('Buradan oku'),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
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
            canStart:
                !listeningActive &&
                !_transitioning &&
                (_preferences?.ready ?? false),
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
    if (controls == null) {
      return SafeArea(child: pageNavigation);
    }
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
    final document = _saved;
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
                  textAlign: document.category == DocumentCategory.book
                      ? TextAlign.justify
                      : TextAlign.start,
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
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _saving ? null : _cancelEditing,
                  child: const Text('Düzenlemekten vazgeç'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
