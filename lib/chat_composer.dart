// A chat composer widget that allows users to input text messages and send them. It also supports attachments and handles streaming states for ongoing responses. The composer is designed to be responsive and adapts its layout based on the available width, ensuring a consistent user experience across different screen sizes. It uses a TextField for message input, an IconButton for sending messages, and another IconButton for attachments if the callback is provided. The widget also measures its height to inform the chat scroll coordinator for proper scrolling behavior when new messages are added or when the keyboard is shown.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:provider/provider.dart';

import 'responsive_spacing.dart';

/// Chat composer widget that allows users to input text messages and send them, with support for attachments and streaming states.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    this.isStreaming = false,
    this.onStop,
  });
  // Indicates whether a streaming response is currently in progress. When true, the send button will change to a stop button, allowing the user to stop the stream. This state is used to update the UI accordingly and provide feedback to the user about the current status of their message.
  final bool isStreaming;
  // Callback function that is called when the user taps the stop button while a stream is in progress. This allows the parent widget to handle stopping the stream and updating the chat interface accordingly. If this callback is null, the stop button will be disabled, indicating that stopping the stream is not currently available.
  final VoidCallback? onStop;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

/// State class for the ChatComposer widget, managing the internal state of the text input, focus, and handling user interactions such as sending messages and attaching files. It also measures its own height to inform the chat scroll coordinator for proper scrolling behavior when new messages are added or when the keyboard is shown.
class _ChatComposerState extends State<ChatComposer> {
  // Global key to access the context of the composer widget for measuring its height and other properties. This is used to inform the chat scroll coordinator about the height of the composer, allowing it to adjust the scroll position when necessary (e.g., when the keyboard is shown).
  final _key = GlobalKey();
  // UUID generator for creating unique stream IDs when sending messages. This is used to track the state of streaming responses from the Gemini model, allowing the chat interface to update in real-time as responses are generated.
  late final TextEditingController _textController;
  // FocusNode for the text input field, allowing us to manage keyboard interactions and handle key events such as submitting messages with Shift+Enter. This focus node is also used to ensure that the text field is focused when the composer is displayed, providing a smooth user experience for message input.
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    // Initialize the text controller and focus node for the text input field. The focus node is set up to handle key events, allowing users to submit messages using Shift+Enter. The text controller manages the state of the text input, allowing us to clear it after a message is sent and to access the current value when needed.
    _textController = TextEditingController();
    // Set up the focus node to handle key events, specifically to allow submitting messages with Shift+Enter. This provides a convenient way for users to send messages without having to tap the send button, enhancing the user experience for power users who prefer keyboard interactions.
    _focusNode = FocusNode()..onKeyEvent = _handleKeyEvent;
    // Schedule a post-frame callback to measure the height of the composer after the first frame is rendered. This allows us to inform the chat scroll coordinator about the height of the composer, ensuring that the chat view can adjust its scroll position appropriately when new messages are added or when the keyboard is shown.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  /// Override the didUpdateWidget method to re-measure the height of the composer whenever the widget is updated. This ensures that if there are changes to the widget that could affect its height (e.g., changes in streaming state that might show or hide certain UI elements), we can update the chat scroll coordinator with the new height to maintain proper scrolling behavior.
  void didUpdateWidget(covariant ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    // Dispose of the text controller and focus node to clean up resources when the widget is removed from the widget tree. This is important to prevent memory leaks and ensure that any listeners or resources associated with these objects are properly released.
    _textController.dispose();
    // Dispose of the focus node to clean up resources and prevent memory leaks. This is especially important if the focus node has listeners or is used to manage keyboard interactions, as failing to dispose of it could lead to unexpected behavior or resource leaks in the application.
    _focusNode.dispose();
    // Call the superclass dispose method to ensure that any additional cleanup in the widget lifecycle is performed correctly. This is a standard practice in Flutter to ensure that all resources are properly released and that the widget is fully cleaned up when it is removed from the widget tree.
    super.dispose();
  }
  
  // Handles key events for the text input field, specifically to allow submitting messages with Shift+Enter.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isShiftPressed) {
      _handleSubmitted(_textController.text);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafeArea = MediaQuery.paddingOf(context).bottom;
    final onAttachmentTap = context.read<OnAttachmentTapCallback?>();
    final theme = context.select(
      (ChatTheme t) => (
        bodyMedium: t.typography.bodyMedium,
        onSurface: t.colors.onSurface,
        surfaceContainerHigh: t.colors.surfaceContainerHigh,
        surfaceContainerLow: t.colors.surfaceContainerLow,
      ),
    );

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: ClipRect(
        child: Container(
          key: _key,
          color: theme.surfaceContainerLow,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final horizontalPadding =
                  ResponsiveSpacing.composerHorizontalPadding(availableWidth);
              final verticalPadding =
                  ResponsiveSpacing.composerVerticalPadding(availableWidth);
              final gap = ResponsiveSpacing.gap(availableWidth);
              final composerMaxWidth =
                  ResponsiveSpacing.composerMaxWidth(availableWidth);

              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: composerMaxWidth),
                  child: Padding(
                    padding: EdgeInsets.only(bottom: bottomSafeArea).add(
                      EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: verticalPadding,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (onAttachmentTap != null)
                          IconButton(
                            icon: const Icon(Icons.attachment),
                            color: theme.onSurface.withValues(alpha: 0.5),
                            onPressed: onAttachmentTap,
                          )
                        else
                          const SizedBox.shrink(),
                        SizedBox(width: gap),
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            focusNode: _focusNode,
                            minLines: 1,
                            maxLines: 3,
                            autocorrect: true,
                            autofocus: false,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.newline,
                            onSubmitted: _handleSubmitted,
                            style: theme.bodyMedium.copyWith(
                              color: theme.onSurface,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Type a message',
                              hintStyle: theme.bodyMedium.copyWith(
                                color: theme.onSurface.withValues(alpha: 0.5),
                              ),
                              border: const OutlineInputBorder(
                                borderSide: BorderSide.none,
                                borderRadius:
                                    BorderRadius.all(Radius.circular(24)),
                              ),
                              filled: true,
                              fillColor: theme.surfaceContainerHigh
                                  .withValues(alpha: 0.8),
                              hoverColor: Colors.transparent,
                            ),
                          ),
                        ),
                        SizedBox(width: gap),
                        IconButton(
                          icon: widget.isStreaming
                              ? const Icon(Icons.stop_circle)
                              : const Icon(Icons.send),
                          color: theme.onSurface.withValues(alpha: 0.5),
                          onPressed: widget.isStreaming
                              ? widget.onStop
                              : () => _handleSubmitted(_textController.text),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
  
  // Method to measure the height of the composer widget and inform the chat scroll coordinator. This is called after the first frame is rendered and whenever the widget is updated, ensuring that the chat scroll coordinator has the correct height information to adjust the scroll position when necessary (e.g., when the keyboard is shown or when new messages are added).
  void _measure() {
    if (!mounted) return;

    final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final height = renderBox.size.height;
    final bottomSafeArea = MediaQuery.paddingOf(context).bottom;
    context.read<ComposerHeightNotifier>().setHeight(height - bottomSafeArea);
  }
  
  // Method to handle the user submitting a message. This is called when the user presses the send button or submits the text field with Shift+Enter. It trims the input text, checks if it's not empty, and then calls the onMessageSend callback provided by the parent widget to send the message. After sending, it clears the text field for the next input.
  void _handleSubmitted(String text) {
    final value = text.trim();
    if (value.isEmpty) return;

    context.read<OnMessageSendCallback?>()?.call(value);
    _textController.clear();
  }
}