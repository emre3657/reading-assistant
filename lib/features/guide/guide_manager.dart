import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../library/data/document_store.dart';

enum GuideGroup {
  home('guide_home'),
  text('guide_text'),
  resume('guide_resume'),
  readFrom('guide_read_from'),
  bookmark('guide_bookmark');

  const GuideGroup(this.key);
  final String key;
}

class GuideManager extends ChangeNotifier {
  GuideManager(this.store);

  final DocumentStore store;
  final RouteObserver<ModalRoute<dynamic>> routes = RouteObserver();
  final Map<GuideGroup, int> _progress = {};
  Set<String> _completed = {};
  Future<void> _writes = Future.value();
  bool _ready = false;
  bool _disposed = false;
  bool _restartHomePending = false;
  GuideGroup? _active;
  String? _error;
  int _errorRevision = 0;

  bool get ready => _ready;
  bool get restartHomePending => _restartHomePending;
  GuideGroup? get active => _active;
  String? get error => _error;
  int get errorRevision => _errorRevision;
  Future<void> get pendingWrites => _writes;
  bool completed(GuideGroup group) => _completed.contains(group.key);
  int progress(GuideGroup group) => _progress[group] ?? 0;

  Future<void> load() async {
    try {
      _completed = await store.completedGuides();
    } catch (error, stack) {
      debugPrint('Kullanım rehberi okunamadı: $error\n$stack');
      _completed = GuideGroup.values.map((group) => group.key).toSet();
      _report('Kullanım rehberi yüklenemedi. Uygulamayı kullanabilirsin.');
    } finally {
      _ready = true;
      if (!_disposed) notifyListeners();
    }
  }

  bool begin(GuideGroup group) {
    if (_disposed || !_ready || _active != null || completed(group)) {
      return false;
    }
    _active = group;
    notifyListeners();
    return true;
  }

  void advance(GuideGroup group, int index) {
    if (_disposed || _active != group) return;
    _progress[group] = index;
    notifyListeners();
  }

  void suspend(GuideGroup group) {
    if (_disposed || _active != group) return;
    _active = null;
    notifyListeners();
  }

  void complete(GuideGroup group, {bool skip = false}) {
    if (_disposed || _active != group) return;
    _active = null;
    if (group == GuideGroup.home) _restartHomePending = false;
    final groups =
        skip &&
            (group == GuideGroup.resume ||
                group == GuideGroup.readFrom ||
                group == GuideGroup.bookmark)
        ? {GuideGroup.resume, GuideGroup.readFrom, GuideGroup.bookmark}
        : {group};
    for (final item in groups) {
      _progress.remove(item);
      _completed.add(item.key);
    }
    notifyListeners();
    _queue(() => store.completeGuides(groups.map((item) => item.key).toSet()));
  }

  void restart() {
    if (_disposed) return;
    _active = null;
    _progress.clear();
    _completed = {};
    _restartHomePending = true;
    notifyListeners();
    _queue(store.resetGuides);
  }

  void _queue(Future<void> Function() operation) {
    _writes = _writes.then((_) async {
      try {
        await operation();
      } catch (error, stack) {
        debugPrint('Kullanım rehberi kaydedilemedi: $error\n$stack');
        _report(
          'Kullanım rehberi kaydedilemedi. Daha sonra tekrar gösterilebilir.',
        );
      }
    });
  }

  void _report(String message) {
    _error = message;
    _errorRevision++;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class GuideScope extends InheritedWidget {
  const GuideScope({super.key, required this.manager, required super.child});

  final GuideManager manager;

  static GuideManager? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GuideScope>()?.manager;

  @override
  bool updateShouldNotify(GuideScope oldWidget) => manager != oldWidget.manager;
}
