import 'package:flutter/material.dart';
import 'dart:math';
import '../widgets/app_header.dart';

enum ChatbotState {
  initial, // 처음 시작 상태 (검은 오버레이 + 시작 버튼)
  loading, // 로딩 상태 (점 3개)
  chatting, // 채팅 상태 (메시지 표시)
  finished // 완료 상태 (검은 오버레이 + 다시하기/다음질문 버튼)
}

enum MessageType { user, bot }

class ChatMessage {
  final String text;
  final MessageType type;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.type,
    required this.timestamp,
  });
}

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  ChatbotState currentState = ChatbotState.initial;
  List<ChatMessage> messages = [];
  final TextEditingController _textController = TextEditingController();
  final Random _random = Random();
  bool isProcessingResponse = false;

  final List<String> _botResponses = [
    '네, 그렇게 생각해볼 수 있겠네요. 더 말씀해 주세요.',
    '흥미로운 관점이군요. 어떤 기분이 드시나요?',
    '그런 상황이라면 정말 어려우셨을 것 같아요.',
    '잘 들었습니다. 그때 어떤 선택을 하셨나요?',
    '말씀하신 것처럼 느끼시는 게 자연스러워요.',
    '더 자세히 설명해 주실 수 있을까요?',
  ];

  void _changeState(ChatbotState newState) {
    setState(() {
      currentState = newState;
    });
  }

  void _sendMessage() {
    if (_textController.text.isNotEmpty && !isProcessingResponse) {
      final userMessage = _textController.text;

      // 키보드 숨기기
      FocusScope.of(context).unfocus();

      setState(() {
        // 사용자 메시지 추가
        messages.add(ChatMessage(
          text: userMessage,
          type: MessageType.user,
          timestamp: DateTime.now(),
        ));
        _textController.clear();
        isProcessingResponse = true; // 응답 처리 중 상태로 변경
        currentState = ChatbotState.chatting; // 채팅 상태로 변경
      });

      // 챗봇 응답 생성 과정 표시
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && isProcessingResponse) {
          setState(() {
            messages.add(ChatMessage(
              text: "잠시만 기다려 주세요.",
              type: MessageType.bot,
              timestamp: DateTime.now(),
            ));
          });
        }
      });
    }
  }

  void _stopProcessing() {
    if (isProcessingResponse) {
      setState(() {
        isProcessingResponse = false;
        currentState = ChatbotState.finished;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 기본 화면 전체
          Column(
            children: [
              const SafeArea(
                bottom: false,
                child: AppHeader(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      if (currentState == ChatbotState.loading) ...[
                        Expanded(
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildDot(),
                                const SizedBox(width: 8),
                                _buildDot(),
                                const SizedBox(width: 8),
                                _buildDot(),
                              ],
                            ),
                          ),
                        ),
                      ] else if (currentState == ChatbotState.chatting ||
                          messages.isNotEmpty) ...[
                        Expanded(
                          child: ListView(
                            padding: EdgeInsets.zero,
                            children: [
                              // 메시지들만 표시
                              ...messages.map((message) {
                                final isUser = message.type == MessageType.user;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12.0),
                                  child: Align(
                                    alignment: isUser
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Container(
                                      constraints: BoxConstraints(
                                        maxWidth:
                                            MediaQuery.of(context).size.width *
                                                0.8,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: isUser
                                            ? Colors.grey.shade200
                                            : Colors.blue,
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Text(
                                        message.text,
                                        style: TextStyle(
                                          color: isUser
                                              ? Colors.black
                                              : Colors.white,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ] else ...[
                        const Expanded(child: SizedBox()),
                      ],
                    ],
                  ),
                ),
              ),
              // 입력창 (항상 표시)
              Container(
                color: Colors.grey.shade50,
                child: SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border:
                          Border(top: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            decoration: InputDecoration(
                              hintText: '메시지를 입력하세요...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            if (isProcessingResponse) {
                              _stopProcessing();
                            } else {
                              _sendMessage();
                            }
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                                isProcessingResponse
                                    ? Icons.stop
                                    : Icons.arrow_forward,
                                color: Colors.white,
                                size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // 전체 화면 오버레이
          if (currentState == ChatbotState.initial) _buildInitialOverlay(),
          if (currentState == ChatbotState.finished) _buildFinishedOverlay(),
        ],
      ),
    );
  }

  Widget _buildDot() {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Colors.grey.shade400,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildInitialOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '평가를 진행할 준비가 되셨을 때,\n아래 [시작] 버튼을 눌러주세요.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => _changeState(ChatbotState.loading),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('시작', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFinishedOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '평가를 진행할 준비가 되셨을 때,\n아래 [시작] 버튼을 눌러주세요.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 40),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => _changeState(ChatbotState.loading),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child:
                              const Text('다시 하기', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () => _changeState(ChatbotState.loading),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child:
                              const Text('다음 질의', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
