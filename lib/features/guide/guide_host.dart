import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'guide_manager.dart';

class GuideStep {
  const GuideStep(this.target, this.message, {this.title});
  final GlobalKey target;
  final String message;
  final String? title;
}

class GuideOffer {
  const GuideOffer({
    required this.group,
    required this.enabled,
    required this.steps,
    this.nextGroup,
    this.previousGroup,
  });
  final GuideGroup group;
  final bool enabled;
  final List<GuideStep> steps;
  final GuideGroup? nextGroup;
  final GuideGroup? previousGroup;
}

class GuideHost extends StatefulWidget {
  const GuideHost({super.key, required this.offers, required this.child});
  final List<GuideOffer> offers;
  final Widget child;

  @override
  State<GuideHost> createState() => _GuideHostState();
}

class _GuideHostState extends State<GuideHost>
    with RouteAware, WidgetsBindingObserver {
  final _stackKey = GlobalKey();
  GuideManager? _manager;
  ModalRoute<dynamic>? _route;
  GuideGroup? _group;
  Rect? _target;
  bool _scheduled = false;
  int _revision = 0;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (foreground) {
      _schedule();
    } else {
      _suspend();
    }
  }

  GuideOffer? get _offer {
    for (final offer in widget.offers) {
      if (offer.group == _group) return offer;
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final manager = GuideScope.maybeOf(context);
    final route = ModalRoute.of(context);
    if (_manager != manager || _route != route) {
      _manager?.removeListener(_schedule);
      if (_route != null) _manager?.routes.unsubscribe(this);
      _manager = manager;
      _route = route;
      manager?.addListener(_schedule);
      if (manager != null && route != null) {
        manager.routes.subscribe(this, route);
      }
    }
    MediaQuery.of(context);
    _schedule();
  }

  @override
  void didUpdateWidget(GuideHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  @override
  void didPushNext() => _suspend();

  @override
  void didPopNext() => _schedule();

  @override
  void didPop() => _suspend();

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) unawaited(_reconcile());
    });
  }

  bool get _available =>
      _foreground &&
      _route?.isCurrent == true &&
      MediaQuery.viewInsetsOf(context).bottom == 0;

  Future<void> _reconcile() async {
    final manager = _manager;
    if (manager == null || !manager.ready) return;
    if (_group != null &&
        (!_available || _offer?.enabled != true || manager.active != _group)) {
      _suspend();
    }
    if (!_available) return;
    if (_group == null) {
      if (manager.active != null) return;
      for (final offer in widget.offers) {
        if (!offer.enabled || manager.completed(offer.group)) continue;
        if (offer.group == GuideGroup.text && manager.restartHomePending) {
          continue;
        }
        final previous = offer.previousGroup;
        if (previous != null &&
            !manager.completed(previous) &&
            widget.offers.any(
              (item) => item.group == previous && item.enabled,
            )) {
          continue;
        }
        final index = manager.progress(offer.group);
        if (index >= offer.steps.length ||
            offer.steps[index].target.currentContext == null) {
          continue;
        }
        setState(() => _group = offer.group);
        if (!manager.begin(offer.group)) {
          setState(() => _group = null);
          return;
        }
        break;
      }
    }
    final offer = _offer;
    if (offer == null) return;
    final index = manager.progress(offer.group);
    final targetContext = offer.steps[index].target.currentContext;
    if (targetContext == null) {
      _suspend();
      return;
    }
    final revision = ++_revision;
    await Scrollable.ensureVisible(targetContext, duration: Duration.zero);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        revision != _revision ||
        !_available ||
        _group != offer.group ||
        manager.active != offer.group) {
      return;
    }
    final targetBox = targetContext.mounted
        ? targetContext.findRenderObject()
        : null;
    final stackBox = _stackKey.currentContext?.findRenderObject();
    if (targetBox is! RenderBox ||
        !targetBox.hasSize ||
        stackBox is! RenderBox ||
        !stackBox.hasSize) {
      _suspend();
      return;
    }
    final origin = targetBox.localToGlobal(Offset.zero, ancestor: stackBox);
    final bounds = origin & targetBox.size;
    final visible = bounds.intersect(Offset.zero & stackBox.size);
    if (visible.isEmpty) {
      _suspend();
      return;
    }
    final highlight = Rect.fromLTWH(
      visible.left,
      visible.top,
      visible.width,
      math.min(visible.height, math.max(60, stackBox.size.height * 0.3)),
    ).inflate(4).intersect(Offset.zero & stackBox.size);
    if (_target != highlight) setState(() => _target = highlight);
  }

  void _suspend() {
    _revision++;
    final group = _group;
    final needsUpdate = group != null || _target != null;
    _group = null;
    if (group != null) _manager?.suspend(group);
    if (needsUpdate && mounted) setState(() => _target = null);
  }

  void _finish({bool skip = true}) {
    final group = _group;
    if (group == null) return;
    _revision++;
    _group = null;
    setState(() => _target = null);
    _manager?.complete(group, skip: skip);
  }

  void _next() {
    final offer = _offer;
    final manager = _manager;
    if (offer == null || manager == null) return;
    final next = manager.progress(offer.group) + 1;
    if (next == offer.steps.length) {
      _finish(skip: false);
      return;
    }
    _revision++;
    setState(() => _target = null);
    manager.advance(offer.group, next);
    _schedule();
  }

  @override
  void dispose() {
    _revision++;
    _manager?.removeListener(_schedule);
    _manager?.routes.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    final group = _group;
    if (group != null) _manager?.suspend(group);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = _manager;
    final offer = _offer;
    final target = _target;
    final engaged = offer != null && manager?.active == _group;
    final active = engaged && target != null;
    final index = active ? manager!.progress(offer.group) : 0;
    final previous =
        active &&
        offer.previousGroup != null &&
        manager!.completed(offer.previousGroup!);
    final next =
        active &&
        offer.nextGroup != null &&
        !manager!.completed(offer.nextGroup!) &&
        widget.offers.any(
          (item) => item.group == offer.nextGroup && item.enabled,
        );
    final stepNumber = index + 1 + (previous ? 1 : 0);
    final stepCount =
        (offer?.steps.length ?? 0) + (previous ? 1 : 0) + (next ? 1 : 0);
    final title = active ? offer.steps[index].title : null;
    return PopScope(
      canPop: !engaged,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && engaged) {
          scheduleMicrotask(() {
            if (mounted) _finish();
          });
        }
      },
      child: Stack(
        key: _stackKey,
        children: [
          ExcludeFocus(
            excluding: engaged,
            child: ExcludeSemantics(excluding: engaged, child: widget.child),
          ),
          if (engaged)
            const Positioned.fill(child: ModalBarrier(dismissible: false)),
          if (active) ...[
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SpotlightPainter(
                    target,
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            CustomSingleChildLayout(
              delegate: _GuidePlacement(target, MediaQuery.paddingOf(context)),
              child: Semantics(
                container: true,
                liveRegion: true,
                label:
                    'Adım $stepNumber/$stepCount. ${title == null ? '' : '$title. '}${offer.steps[index].message}',
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 8,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ExcludeSemantics(
                            child: Text('Adım $stepNumber/$stepCount'),
                          ),
                          if (title != null) ...[
                            const SizedBox(height: 8),
                            ExcludeSemantics(
                              child: Text(
                                title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          ExcludeSemantics(
                            child: Text(offer.steps[index].message),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () => _finish(),
                                child: const Text('Atla'),
                              ),
                              FilledButton(
                                onPressed: _next,
                                child: Text(
                                  index + 1 == offer.steps.length && !next
                                      ? 'Tamam'
                                      : 'İleri',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter(this.target, this.border);
  final Rect target;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(target, const Radius.circular(10));
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(hole);
    canvas.drawPath(path, Paint()..color = const Color(0xb3000000));
    canvas.drawRRect(
      hole,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      target != oldDelegate.target || border != oldDelegate.border;
}

class _GuidePlacement extends SingleChildLayoutDelegate {
  _GuidePlacement(this.target, this.padding);
  final Rect target;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final above = math.max(0.0, target.top - padding.top - 16);
    final below = math.max(
      0.0,
      constraints.maxHeight - padding.bottom - target.bottom - 16,
    );
    return BoxConstraints(
      maxWidth: math.max(0.0, math.min(360.0, constraints.maxWidth - 24)),
      maxHeight: math.max(0.0, math.max(above, below)),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final above = target.top - padding.top - 16;
    final below = size.height - padding.bottom - target.bottom - 16;
    final y = below >= childSize.height || below >= above
        ? target.bottom + 8
        : target.top - childSize.height - 8;
    final x = (target.center.dx - childSize.width / 2)
        .clamp(12.0, math.max(12.0, size.width - childSize.width - 12))
        .toDouble();
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_GuidePlacement oldDelegate) =>
      target != oldDelegate.target || padding != oldDelegate.padding;
}
