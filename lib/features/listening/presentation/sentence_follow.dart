import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'listening_controller.dart';
import 'reading_preferences.dart';

class SentenceFollow extends StatefulWidget {
  const SentenceFollow({
    super.key,
    required this.listening,
    required this.preferences,
    required this.textController,
    required this.textKey,
    required this.scrollController,
    required this.child,
    this.followTextSizeChanges = false,
  });

  final ListeningController listening;
  final ReadingPreferences preferences;
  final TextEditingController textController;
  final GlobalKey textKey;
  final ScrollController scrollController;
  final Widget child;
  final bool followTextSizeChanges;

  @override
  SentenceFollowState createState() => SentenceFollowState();
}

class SentenceFollowState extends State<SentenceFollow> {
  final _viewportKey = GlobalKey();
  bool _suspended = false;
  bool _wasSpeaking = false;
  bool _wasEnabled = false;
  bool _animating = false;
  int _token = 0;
  (String, int, int)? _sentence;
  ReadingTextSize? _textSize;
  ReadingTextAlignment? _textAlignment;

  @override
  void initState() {
    super.initState();
    widget.listening.addListener(_changed);
    widget.preferences.addListener(_changed);
    widget.textController.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(covariant SentenceFollow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferences != widget.preferences) {
      oldWidget.preferences.removeListener(_changed);
      widget.preferences.addListener(_changed);
      _changed();
    }
  }

  void newSession() {
    _cancel();
    _suspended = false;
    _sentence = null;
    _wasSpeaking = false;
  }

  void _cancel() {
    _token++;
    if (_animating && widget.scrollController.hasClients) {
      final position = widget.scrollController.position;
      position.jumpTo(position.pixels);
    }
    _animating = false;
  }

  void _changed() {
    final listening = widget.listening;
    final enabled =
        widget.preferences.ready && widget.preferences.followSentence;
    final speaking = listening.status == ListeningStatus.speaking;
    final span = listening.sentenceForText(widget.textController.text);
    final text = widget.textController.text;
    final content = span == null ? null : text.substring(span.start, span.end);
    final sentence = span == null
        ? null
        : (
            text,
            span.start + content!.length - content.trimLeft().length,
            span.start + content.trimRight().length,
          );
    final changed = sentence != _sentence;
    final resumed = speaking && !_wasSpeaking;
    final enabledNow = enabled && !_wasEnabled;
    final sizeChanged = _textSize != widget.preferences.textSize;
    final alignmentChanged = _textAlignment != widget.preferences.textAlignment;
    _textSize = widget.preferences.textSize;
    _textAlignment = widget.preferences.textAlignment;
    _sentence = sentence;
    _wasSpeaking = speaking;
    _wasEnabled = enabled;
    if (!enabled || !speaking || changed) _cancel();
    if (enabled &&
        speaking &&
        !_suspended &&
        sentence != null &&
        (changed ||
            resumed ||
            enabledNow ||
            ((sizeChanged || alignmentChanged) &&
                widget.followTextSizeChanges))) {
      _schedule(sentence);
    }
    if (mounted) setState(() {});
  }

  void _schedule((String, int, int) sentence, {bool explicit = false}) {
    final token = ++_token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          token != _token ||
          _sentence != sentence ||
          !widget.preferences.ready ||
          !widget.preferences.followSentence ||
          _suspended ||
          (!explicit && widget.listening.status != ListeningStatus.speaking)) {
        return;
      }
      _scrollTo(sentence);
    });
  }

  EditableTextState? _editable() {
    EditableTextState? result;
    void visit(Element element) {
      if (result != null) return;
      if (element is StatefulElement && element.state is EditableTextState) {
        result = element.state as EditableTextState;
        return;
      }
      element.visitChildren(visit);
    }

    widget.textKey.currentContext?.visitChildElements(visit);
    return result;
  }

  void _scrollTo((String, int, int) sentence) {
    final editable = _editable()?.renderEditable;
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (editable == null ||
        viewport is! RenderBox ||
        !editable.attached ||
        !viewport.attached ||
        !widget.scrollController.hasClients) {
      return;
    }
    final boxes = editable.getBoxesForSelection(
      TextSelection(baseOffset: sentence.$2, extentOffset: sentence.$3),
    );
    if (boxes.isEmpty) return;
    final top = viewport
        .globalToLocal(
          editable.localToGlobal(Offset(boxes.first.left, boxes.first.top)),
        )
        .dy;
    final bottom = viewport
        .globalToLocal(
          editable.localToGlobal(Offset(boxes.last.right, boxes.last.bottom)),
        )
        .dy;
    final firstBottom = viewport
        .globalToLocal(
          editable.localToGlobal(Offset(boxes.first.right, boxes.first.bottom)),
        )
        .dy;
    final height = viewport.size.height;
    final delta = bottom - top > height
        ? (top < 0 || firstBottom > height ? top : 0.0)
        : top < 0
        ? top
        : bottom > height
        ? bottom - height
        : 0.0;
    if (delta == 0) return;
    final position = widget.scrollController.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.5) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      position.jumpTo(target);
    } else {
      _animating = true;
      final token = _token;
      unawaited(
        position
            .animateTo(
              target,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            )
            .whenComplete(() {
              if (mounted && token == _token) _animating = false;
            }),
      );
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == 0 &&
        notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle &&
        widget.preferences.ready &&
        widget.preferences.followSentence &&
        widget.listening.isActive) {
      _token++;
      _animating = false;
      if (!_suspended) setState(() => _suspended = true);
    }
    return false;
  }

  void _returnToSentence() {
    _cancel();
    setState(() => _suspended = false);
    final sentence = _sentence;
    if (sentence != null) _schedule(sentence, explicit: true);
  }

  @override
  void dispose() {
    _cancel();
    widget.listening.removeListener(_changed);
    widget.preferences.removeListener(_changed);
    widget.textController.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showReturn =
        _suspended &&
        widget.preferences.ready &&
        widget.preferences.followSentence &&
        widget.listening.isActive &&
        _sentence != null;
    return Column(
      children: [
        if (showReturn)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _returnToSentence,
              icon: const Icon(Icons.my_location),
              label: const Text('Okunan cümleye dön'),
            ),
          ),
        Expanded(
          child: KeyedSubtree(
            key: _viewportKey,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: widget.child,
            ),
          ),
        ),
      ],
    );
  }
}
