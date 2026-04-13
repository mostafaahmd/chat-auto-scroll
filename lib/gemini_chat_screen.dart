import 'dart:async';

import 'package:cross_cache/cross_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart'
    hide InMemoryChatController;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flyer_chat_image_message/flyer_chat_image_message.dart';
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart';
import 'package:flyer_chat_text_stream_message/flyer_chat_text_stream_message.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'chat_composer.dart';
import 'chat_scroll_coordinator.dart';
import 'gemini_stream_manager.dart';
import 'in_memory_chat_controller.dart';
import 'responsive_spacing.dart';

// Duration to wait after the last chunk is received before marking the stream as complete.
// This allows the final chunk animation to finish before the message is converted to
// a regular text message, which keeps the UI feeling smoother.
const Duration _kChunkAnimationDuration = Duration(milliseconds: 350);

// Prompt used for image-only attachment messages so Gemini responds with a human-friendly
// description instead of raw OCR-like JSON, coordinates, or bounding boxes.
const String _kImageAnalysisPrompt = '''
Describe this image in clear, natural language.
Focus on the main visible content and any important readable text.
Do not return JSON, coordinates, bounding boxes, markdown tables, or code.
Keep the answer concise, user-friendly, and easy to read.
''';

// Main chat screen widget that integrates with the Gemini API to provide a generative AI chat experience.
// It manages the chat state, handles user input, and displays streaming responses from the Gemini model.
class GeminiChatScreen extends StatefulWidget {
  final String geminiApiKey;

  const GeminiChatScreen({super.key, required this.geminiApiKey});

  @override
  State<GeminiChatScreen> createState() => _GeminiChatScreenState();
}

class _GeminiChatScreenState extends State<GeminiChatScreen> {
  // Unique identifier generator for messages and streams.
  final _uuid = const Uuid();

  // Cross-platform cache used by the chat UI, primarily for rendering images.
  final _crossCache = CrossCache();

  // Scroll controller for the chat list. The ChatScrollCoordinator uses this to track
  // whether the user is near the bottom and whether auto-follow should stay active.
  final _scrollController = ScrollController();

  // Simple in-memory chat controller that stores and updates chat messages for this demo.
  final _chatController = InMemoryChatController();

  // Current user and assistant user definitions.
  final _currentUser = const User(id: 'me');
  final _agent = const User(id: 'agent');

  // Gemini model and active chat session.
  late final GenerativeModel _model;
  late ChatSession _chatSession;

  // Stream manager responsible for animating and finalizing streamed assistant messages.
  late final GeminiStreamManager _streamManager;

  // Scroll coordinator responsible for sticky-bottom behavior.
  late final ChatScrollCoordinator _scrollCoordinator;

  // Whether the assistant is currently streaming a response.
  bool _isStreaming = false;

  // Active subscription for the current streamed response.
  StreamSubscription? _currentStreamSubscription;

  // Identifier for the currently active stream.
  String? _currentStreamId;

  @override
  void initState() {
    super.initState();

    // Initialize the manager that tracks streamed text chunks and updates the visible
    // stream message as new content arrives.
    _streamManager = GeminiStreamManager(
      chatController: _chatController,
      chunkAnimationDuration: _kChunkAnimationDuration,
    );

    // Initialize the Gemini model used for both text and multimodal (image + text) requests.
    _model = GenerativeModel(
      model: 'gemini-2.5-flash-lite',
      apiKey: widget.geminiApiKey,
      safetySettings: [
        SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.none),
      ],
    );

    // Start a persistent chat session so text turns keep conversational context.
    _chatSession = _model.startChat();

    // Initialize and attach the scroll coordinator so it can observe scroll changes
    // and decide when auto-follow should remain active.
    _scrollCoordinator = ChatScrollCoordinator(_scrollController);
    _scrollCoordinator.attach();
  }

  @override
  void dispose() {
    // Cancel any active response stream.
    _currentStreamSubscription?.cancel();

    // Detach the scroll coordinator and dispose all owned resources.
    _scrollCoordinator.detach();
    _streamManager.dispose();
    _chatController.dispose();
    _scrollController.dispose();
    _crossCache.dispose();

    super.dispose();
  }

  // Stops the currently active assistant stream when the user taps the stop button.
  void _stopCurrentStream() {
    if (_currentStreamSubscription == null || _currentStreamId == null) return;

    _currentStreamSubscription!.cancel();
    _currentStreamSubscription = null;

    setState(() {
      _isStreaming = false;
    });

    _streamManager.errorStream(_currentStreamId!, 'Stream stopped by user');
    _scrollCoordinator.scheduleScrollToBottom(jump: true);
    _currentStreamId = null;
  }

  // Handles stream errors by converting the active streamed message into an error text message
  // and resetting the streaming state.
  void _handleStreamError(
    String streamId,
    dynamic error,
    TextStreamMessage? streamMessage,
  ) async {
    debugPrint('Generation error for $streamId: $error');

    if (streamMessage != null) {
      await _streamManager.errorStream(streamId, error);
      _scrollCoordinator.scheduleScrollToBottom(jump: true);
    }

    if (mounted) {
      setState(() {
        _isStreaming = false;
      });
    }

    _currentStreamSubscription = null;
    _currentStreamId = null;
  }

  // Resolves the MIME type for an image selected via image_picker.
  // If the picker does not provide a valid image MIME type, we infer it from the file name/path.
  String _resolveImageMimeType(XFile image) {
    final reportedMimeType = image.mimeType;
    if (reportedMimeType != null && reportedMimeType.startsWith('image/')) {
      return reportedMimeType;
    }

    final candidate = '${image.name} ${image.path}'.toLowerCase();

    if (candidate.contains('.png')) return 'image/png';
    if (candidate.contains('.webp')) return 'image/webp';
    if (candidate.contains('.gif')) return 'image/gif';
    if (candidate.contains('.heic')) return 'image/heic';
    if (candidate.contains('.heif')) return 'image/heif';

    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Gemini Chat')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final messageHorizontalPadding =
                ResponsiveSpacing.messageHorizontalPadding(availableWidth);
            final messageVerticalPadding =
                ResponsiveSpacing.messageVerticalPadding(availableWidth);

            return ChangeNotifierProvider.value(
              value: _streamManager,
              child: Chat(
                builders: Builders(
                  chatAnimatedListBuilder: (context, itemBuilder) {
                    return ChatAnimatedList(
                      scrollController: _scrollController,
                      itemBuilder: itemBuilder,
                      initialScrollToEndMode: InitialScrollToEndMode.jump,
                      shouldScrollToEndWhenSendingMessage: false,
                      shouldScrollToEndWhenAtBottom: false,

                      // Show the default package scroll-to-bottom button immediately
                      // when the user scrolls away from the bottom.
                      scrollToBottomAppearanceDelay: Duration.zero,
                      scrollToBottomAppearanceThreshold: kBottomLockThreshold,
                    );
                  },
                  imageMessageBuilder:
                      (
                        context,
                        message,
                        index, {
                        required bool isSentByMe,
                        MessageGroupStatus? groupStatus,
                      }) => FlyerChatImageMessage(
                        message: message,
                        index: index,
                        showTime: false,
                        showStatus: false,
                      ),
                  composerBuilder: (context) => ChatComposer(
                    isStreaming: _isStreaming,
                    onStop: _stopCurrentStream,
                  ),
                  textMessageBuilder:
                      (
                        context,
                        message,
                        index, {
                        required bool isSentByMe,
                        MessageGroupStatus? groupStatus,
                      }) => FlyerChatTextMessage(
                        message: message,
                        index: index,
                        showTime: false,
                        showStatus: false,
                        receivedBackgroundColor: Colors.transparent,
                        padding: message.authorId == _agent.id
                            ? EdgeInsets.zero
                            : EdgeInsets.symmetric(
                                horizontal: messageHorizontalPadding,
                                vertical: messageVerticalPadding,
                              ),
                      ),
                  textStreamMessageBuilder:
                      (
                        context,
                        message,
                        index, {
                        required bool isSentByMe,
                        MessageGroupStatus? groupStatus,
                      }) {
                        final streamState = context
                            .watch<GeminiStreamManager>()
                            .getState(message.streamId);

                        return FlyerChatTextStreamMessage(
                          message: message,
                          index: index,
                          streamState: streamState,
                          chunkAnimationDuration: _kChunkAnimationDuration,
                          showTime: false,
                          showStatus: false,
                          receivedBackgroundColor: Colors.transparent,
                          padding: message.authorId == _agent.id
                              ? EdgeInsets.zero
                              : EdgeInsets.symmetric(
                                  horizontal: messageHorizontalPadding,
                                  vertical: messageVerticalPadding,
                                ),
                        );
                      },
                ),
                chatController: _chatController,
                crossCache: _crossCache,
                currentUserId: _currentUser.id,
                onAttachmentTap: _handleAttachmentTap,
                onMessageSend: _handleMessageSend,
                resolveUser: (id) => Future.value(switch (id) {
                  'me' => _currentUser,
                  'agent' => _agent,
                  _ => null,
                }),
                theme: ChatTheme.fromThemeData(theme),
              ),
            );
          },
        ),
      ),
    );
  }

  // Handles text message sending from the composer.
  // The user's message is inserted immediately, then we start streaming the assistant response.
  void _handleMessageSend(String text) async {
    await _chatController.insertMessage(
      TextMessage(
        id: _uuid.v4(),
        authorId: _currentUser.id,
        createdAt: DateTime.now().toUtc(),
        text: text,
        metadata: isOnlyEmoji(text) ? {'isOnlyEmoji': true} : null,
      ),
    );

    _scrollCoordinator.scheduleScrollToBottom(jump: false);
    _sendContent(Content.text(text));
  }

  // Handles image attachments from the composer.
  // The selected image is inserted into the chat as a user image message, then sent to Gemini
  // together with a clear text instruction so the model responds in natural language instead
  // of raw OCR-like JSON or coordinate data.
  void _handleAttachmentTap() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 90,
    );
    if (image == null) return;

    final bytes = await image.readAsBytes();
    if (bytes.isEmpty) return;

    final mimeType = _resolveImageMimeType(image);

    await _chatController.insertMessage(
      ImageMessage(
        id: _uuid.v4(),
        authorId: _currentUser.id,
        createdAt: DateTime.now().toUtc(),
        source: image.path,
      ),
    );

    _scrollCoordinator.scheduleScrollToBottom(jump: false);

    _sendContent(
      Content.multi([
        TextPart(_kImageAnalysisPrompt),
        DataPart(mimeType, bytes),
      ]),
    );
  }

  // Sends content to Gemini and streams the assistant response into a TextStreamMessage.
  // This works for both regular text turns and multimodal image + instruction turns.
  void _sendContent(Content content) async {
    final streamId = _uuid.v4();
    _currentStreamId = streamId;

    setState(() {
      _isStreaming = true;
    });

    final streamMessage = TextStreamMessage(
      id: streamId,
      authorId: _agent.id,
      createdAt: DateTime.now().toUtc(),
      streamId: streamId,
    );

    await _chatController.insertMessage(streamMessage);
    _streamManager.startStream(streamId, streamMessage);
    _scrollCoordinator.scheduleScrollToBottom(jump: true);

    var receivedAnyText = false;

    try {
      final response = _chatSession.sendMessageStream(content);

      _currentStreamSubscription = response.listen(
        (chunk) async {
          final textChunk = chunk.text;
          if (textChunk == null || textChunk.isEmpty) return;

          receivedAnyText = true;
          _streamManager.addChunk(streamId, textChunk);
          _scrollCoordinator.scheduleScrollToBottom(jump: true);
        },
        onDone: () async {
          if (receivedAnyText) {
            await _streamManager.completeStream(streamId);
          } else {
            await _streamManager.errorStream(
              streamId,
              'No text response returned by Gemini',
            );
          }

          if (mounted) {
            setState(() {
              _isStreaming = false;
            });
          }

          _currentStreamSubscription = null;
          _currentStreamId = null;
        },
        onError: (error) async {
          _handleStreamError(streamId, error, streamMessage);
        },
      );
    } catch (error) {
      _handleStreamError(streamId, error, streamMessage);
    }
  }
}
