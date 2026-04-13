import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

const double kBottomLockThreshold = 48;

class ChatScrollCoordinator extends ChangeNotifier {
  ChatScrollCoordinator(this.scrollController);

  final ScrollController scrollController;

  bool _stickToBottom = true;
  bool _isPerformingAutoScroll = false;
  bool _scrollToBottomScheduled = false;

  bool get stickToBottom => _stickToBottom;
  bool get shouldShowJumpToBottom => !_stickToBottom;

  void attach() {
    scrollController.addListener(_handleScrollChange);
  }

  void detach() {
    scrollController.removeListener(_handleScrollChange);
  }

  void _setStickToBottom(bool value) {
    if (_stickToBottom == value) return;
    _stickToBottom = value;
    notifyListeners();
  }

  void _handleScrollChange() {
    if (!scrollController.hasClients || _isPerformingAutoScroll) return;

    final isNearBottom =
        scrollController.position.extentAfter <= kBottomLockThreshold;

    if (isNearBottom && !_stickToBottom) {
      _setStickToBottom(true);
      scheduleScrollToBottom(force: true, jump: true);
      return;
    }

    if (!isNearBottom && _stickToBottom) {
      _setStickToBottom(false);
    }
  }

  void scheduleScrollToBottom({
    bool jump = true,
    bool force = false,
  }) {
    if (_scrollToBottomScheduled) return;
    if (!_stickToBottom && !force) return;

    _scrollToBottomScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _scrollToBottomScheduled = false;
      await scrollToBottom(jump: jump, force: force);
    });
  }

  Future<void> scrollToBottom({
    bool jump = true,
    bool force = false,
  }) async {
    if (!scrollController.hasClients) return;
    if (!_stickToBottom && !force) return;

    final position = scrollController.position;
    final target = position.maxScrollExtent;

    if ((target - position.pixels).abs() < 0.5) {
      if (force) _setStickToBottom(true);
      return;
    }

    _isPerformingAutoScroll = true;
    try {
      if (jump) {
        scrollController.jumpTo(target);
      } else {
        await scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }

      if (force) {
        _setStickToBottom(true);
      }
    } finally {
      _isPerformingAutoScroll = false;
    }
  }
}