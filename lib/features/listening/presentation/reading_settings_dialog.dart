import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'listening_controller.dart';
import 'reading_preferences.dart';
import 'page_transition.dart';
import 'reading_page_surface.dart';

Future<void> showReadingSettings(
  BuildContext context, {
  required ReadingPreferences preferences,
  Listenable? pageChanges,
  bool Function()? showAutoNextPage,
  bool appearanceOnly = false,
  bool showPageAnimation = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
      listenable: Listenable.merge([preferences, pageChanges]),
      builder: (context, _) => AlertDialog(
        scrollable: true,
        title: Text(appearanceOnly ? 'Görünüm' : 'Görünüm ve sesli okuma'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _settingsGroup(
              context,
              title: appearanceOnly ? null : 'Görünüm',
              icon: Icons.text_fields,
              children: [
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Yazı boyutu'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ReadingTextSize>(
                      key: const ValueKey('reading-text-size'),
                      value: preferences.textSize,
                      isExpanded: true,
                      items: [
                        for (final size in ReadingTextSize.values)
                          DropdownMenuItem(
                            value: size,
                            child: Text(size.label),
                          ),
                      ],
                      onChanged: preferences.ready
                          ? (size) {
                              if (size != null) preferences.setTextSize(size);
                            }
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Metin hizalaması',
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ReadingTextAlignment>(
                      key: const ValueKey('reading-text-alignment'),
                      value: preferences.textAlignment,
                      isExpanded: true,
                      items: [
                        for (final alignment in ReadingTextAlignment.values)
                          DropdownMenuItem(
                            value: alignment,
                            child: Text(alignment.label),
                          ),
                      ],
                      onChanged: preferences.ready
                          ? (alignment) {
                              if (alignment != null) {
                                preferences.setTextAlignment(alignment);
                              }
                            }
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Satır aralığı'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ReadingLineSpacing>(
                      key: const ValueKey('reading-line-spacing'),
                      value: preferences.lineSpacing,
                      isExpanded: true,
                      items: [
                        for (final spacing in ReadingLineSpacing.values)
                          DropdownMenuItem(
                            value: spacing,
                            child: Text(spacing.label),
                          ),
                      ],
                      onChanged: preferences.ready
                          ? (spacing) {
                              if (spacing != null) {
                                preferences.setLineSpacing(spacing);
                              }
                            }
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Sayfa görünümü',
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ReadingPageView>(
                      key: const ValueKey('reading-page-view'),
                      value: preferences.pageView,
                      isExpanded: true,
                      items: [
                        for (final view in ReadingPageView.values)
                          DropdownMenuItem(
                            value: view,
                            child: Text(view.label),
                          ),
                      ],
                      onChanged: preferences.ready
                          ? (view) {
                              if (view != null) preferences.setPageView(view);
                            }
                          : null,
                    ),
                  ),
                ),
                if (showPageAnimation) ...[
                  const SizedBox(height: 12),
                  _PageAnimationSettings(preferences: preferences),
                ],
              ],
            ),
            if (!appearanceOnly) ...[
              const SizedBox(height: 12),
              _settingsGroup(
                context,
                title: 'Sesli okuma',
                icon: Icons.volume_up_outlined,
                children: [
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'Okuma hızı'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<ReadingSpeed>(
                        key: const ValueKey('reading-speed'),
                        value: preferences.speed,
                        isExpanded: true,
                        items: [
                          for (final speed in ReadingSpeed.values)
                            DropdownMenuItem(
                              value: speed,
                              child: Text(speed.label),
                            ),
                        ],
                        onChanged: preferences.ready
                            ? (speed) {
                                if (speed != null) preferences.setSpeed(speed);
                              }
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    key: const ValueKey('follow-sentence'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Okunan cümleyi takip et'),
                    value: preferences.followSentence,
                    onChanged: preferences.ready
                        ? preferences.setFollowSentence
                        : null,
                  ),
                  if (showAutoNextPage?.call() ?? false) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      key: const ValueKey('auto-next-page'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Sonraki sayfayı otomatik oku'),
                      value: preferences.autoNextPage,
                      onChanged: preferences.ready
                          ? preferences.setAutoNextPage
                          : null,
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Kapat'),
          ),
        ],
      ),
    ),
  );
}

class _PageAnimationSettings extends StatefulWidget {
  const _PageAnimationSettings({required this.preferences});
  final ReadingPreferences preferences;

  @override
  State<_PageAnimationSettings> createState() => _PageAnimationSettingsState();
}

class _PageAnimationSettingsState extends State<_PageAnimationSettings>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _animation = AnimationController(vsync: this);
  final _captureKey = GlobalKey();
  ui.Image? _snapshot;
  bool _second = false;
  bool _playing = false;
  bool _capturing = false;
  int _previewToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _play() async {
    if (_playing || _capturing) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _second = !_second);
      return;
    }
    final effect = widget.preferences.pageAnimationEffect;
    final token = ++_previewToken;
    ui.Image? snapshot;
    if (effect == PageAnimationEffect.turn) {
      setState(() => _capturing = true);
      try {
        snapshot = await capturePage(
          _captureKey,
          MediaQuery.devicePixelRatioOf(context),
        );
      } catch (error, stack) {
        if (mounted) debugPrint('Önizleme görüntüsü alınamadı: $error\n$stack');
      }
      if (!mounted || token != _previewToken) {
        snapshot?.dispose();
        return;
      }
      if (snapshot == null || MediaQuery.disableAnimationsOf(context)) {
        snapshot?.dispose();
        setState(() {
          _capturing = false;
          _second = !_second;
        });
        return;
      }
    }
    setState(() {
      _snapshot = snapshot;
      _capturing = false;
      _second = !_second;
      _playing = true;
    });
    _animation.duration = pageTransitionDuration(effect);
    try {
      await _animation.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    } finally {
      if (mounted && token == _previewToken) {
        setState(() {
          _playing = false;
          _snapshot = null;
        });
        snapshot?.dispose();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.hidden &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached) {
      return;
    }
    _previewToken++;
    _animation.stop(canceled: true);
    final snapshot = _snapshot;
    setState(() {
      _snapshot = null;
      _playing = false;
      _capturing = false;
    });
    snapshot?.dispose();
  }

  @override
  void dispose() {
    _previewToken++;
    WidgetsBinding.instance.removeObserver(this);
    _snapshot?.dispose();
    _animation.dispose();
    super.dispose();
  }

  Widget _sample(bool second) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: ReadingPageSurface(
        view: widget.preferences.pageView,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Text(second ? 'Örnek sayfa 2' : 'Örnek sayfa 1'),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final preferences = widget.preferences;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('page-animation-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Sayfa geçiş animasyonu'),
          value: preferences.pageAnimationEnabled,
          onChanged: preferences.ready && !_playing && !_capturing
              ? preferences.setPageAnimationEnabled
              : null,
        ),
        if (preferences.pageAnimationEnabled) ...[
          RadioGroup<PageAnimationEffect>(
            groupValue: preferences.pageAnimationEffect,
            onChanged: (value) {
              if (value != null && !_playing && !_capturing) {
                preferences.setPageAnimationEffect(value);
              }
            },
            child: Column(
              children: [
                for (final effect in PageAnimationEffect.values)
                  RadioListTile<PageAnimationEffect>(
                    value: effect,
                    enabled: !_playing && !_capturing,
                    contentPadding: EdgeInsets.zero,
                    title: Text(effect.label),
                    secondary: _EffectThumbnail(effect: effect),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 110,
            child: ReadingPageTransition(
              animation: _animation,
              effect: preferences.pageAnimationEffect,
              forward: _second,
              previous: _playing ? _sample(!_second) : null,
              snapshot: _snapshot,
              paperColor: readingPagePaperColor(context, preferences.pageView),
              child: RepaintBoundary(key: _captureKey, child: _sample(_second)),
            ),
          ),
          TextButton.icon(
            onPressed: _playing || _capturing ? null : _play,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Önizlemeyi oynat'),
          ),
        ],
      ],
    );
  }
}

class _EffectThumbnail extends StatelessWidget {
  const _EffectThumbnail({required this.effect});
  final PageAnimationEffect effect;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 3,
            top: 5,
            child: Container(
              width: 22,
              height: 28,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 1,
            child: Icon(
              switch (effect) {
                PageAnimationEffect.fade => Icons.blur_on,
                PageAnimationEffect.slide => Icons.swap_vert,
                PageAnimationEffect.turn => Icons.arrow_back,
              },
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _settingsGroup(
  BuildContext context, {
  required String? title,
  required IconData icon,
  required List<Widget> children,
}) {
  final theme = Theme.of(context);

  return Material(
    color: theme.colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Semantics(
              header: true,
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      icon,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleSmall),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          ...children,
        ],
      ),
    ),
  );
}
