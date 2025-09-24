import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../services/sheets_service.dart';
import '../models/question_result.dart';

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
  bool isProcessingResponse = false;

  // 실험 관련 변수들
  int? subjectNumber;
  List<String> questions = [];
  int currentQuestionIndex = 0;
  List<QuestionResult> results = [];
  DateTime? sendTime;
  bool isFinishing = false; // 실험 종료 중인지 표시

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSubjectData();
    });
  }

  void _loadSubjectData() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args != null && args is int) {
      subjectNumber = args;
      _loadQuestions();
    }
  }

  Future<void> _loadQuestions() async {
    if (subjectNumber != null) {
      try {
        questions = await SheetsService.getQuestionsForSubject(subjectNumber!);
        // 질문 로드만 하고, 입력창에는 설정하지 않음
      } catch (e) {
        // 에러 발생 시 기본 질문들 사용 (테스트용)
        questions = [
          "첫 번째 질문입니다.",
          "두 번째 질문입니다.",
          "세 번째 질문입니다.",
          "네 번째 질문입니다.",
        ];
      }
    }
  }

  void _setCurrentQuestion() {
    if (currentQuestionIndex < questions.length) {
      setState(() {
        _textController.text = questions[currentQuestionIndex];
      });
    }
  }

  void _changeState(ChatbotState newState) {
    setState(() {
      currentState = newState;
    });
  }

  void _sendMessage() {
    if (_textController.text.isNotEmpty && !isProcessingResponse) {
      final userMessage = _textController.text;
      sendTime = DateTime.now(); // 발송 시간 기록

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
    if (isProcessingResponse && sendTime != null) {
      final stopTime = DateTime.now();
      final latencyMs = stopTime.difference(sendTime!).inMilliseconds;

      // 현재 질문의 결과 저장
      results.add(QuestionResult(
        questionNumber: currentQuestionIndex + 1,
        questionText: questions[currentQuestionIndex],
        sendTime: sendTime!,
        stopTime: stopTime,
        latencyMs: latencyMs,
      ));

      setState(() {
        isProcessingResponse = false;
        currentState = ChatbotState.finished;
      });
    }
  }

  void _nextQuestion() {
    currentQuestionIndex++;
    messages.clear();

    if (currentQuestionIndex < questions.length) {
      _setCurrentQuestion(); // 질문 먼저 설정
      _changeState(ChatbotState.loading); // 그다음 상태 변경
    } else {
      // 모든 질문 완료 - 실험 종료
      _finishExperiment();
    }
  }

  void _retryCurrentQuestion() {
    // 현재 질문의 결과 삭제
    if (results.isNotEmpty) {
      results.removeLast();
    }

    // 메시지 초기화하고 현재 질문 다시 설정
    messages.clear();
    _setCurrentQuestion(); // 질문 먼저 설정
    _changeState(ChatbotState.loading); // 그다음 상태 변경
  }

  Future<void> _finishExperiment() async {
    setState(() {
      isFinishing = true; // 로딩 상태 시작
    });

    if (subjectNumber != null && results.isNotEmpty) {
      try {
        await SheetsService.recordAllResults(
          subjectNumber: subjectNumber!,
          results: results,
        );
        // 저장 성공 시 첫 화면으로 돌아가기
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/');
        }
      } catch (e) {
        setState(() {
          isFinishing = false; // 로딩 상태 종료
        });
        // 저장 실패 시 재시도 팝업 표시
        _showSaveErrorDialog();
      }
    } else {
      setState(() {
        isFinishing = false; // 로딩 상태 종료
      });
    }
  }

  void _showSaveErrorDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // 뒤로가기로 닫을 수 없도록
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          '데이터 저장 실패',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        content: const Text(
          '실험 데이터 저장에 실패했습니다.\n네트워크 연결을 확인하고 다시 시도해주세요.',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 16,
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _finishExperiment(); // 재시도
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.black87,
              backgroundColor: Colors.grey.shade100,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text(
              '다시 시도',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
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
                            maxLines: null, // 자동 줄바꿈
                            minLines: 1,
                            keyboardType: TextInputType.multiline,
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
                    onPressed: () {
                      _setCurrentQuestion(); // 시작할 때 질문 설정
                      _changeState(ChatbotState.loading);
                    },
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
                          onPressed: _retryCurrentQuestion,
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
                          onPressed: isFinishing ? null : _nextQuestion,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: isFinishing && currentQuestionIndex >= 3
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text('저장 중...', style: TextStyle(fontSize: 16)),
                                  ],
                                )
                              : Text(
                                  currentQuestionIndex >= 3 ? '실험 종료' : '다음 질의',
                                  style: const TextStyle(fontSize: 16),
                                ),
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
