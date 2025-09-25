import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../services/sheets_service.dart';
import '../models/question_result.dart';

enum ChatbotState {
  initial, // 처음 시작 상태 (검은 오버레이 + 시작 버튼)
  loading, // 로딩 상태 (점 3개)
  chatting, // 채팅 상태 (메시지 표시)
  finished, // 완료 상태 (검은 오버레이 + 다시하기/다음질문 버튼)
  resting // 16번째 질문 후 10분 휴식 상태
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
  final List<ChatMessage> messages = [];
  final TextEditingController _textController = TextEditingController();
  bool isProcessingResponse = false;

  int? subjectNumber;
  List<String> questions = [];
  int currentQuestionIndex = 0;
  final List<QuestionResult> results = [];
  DateTime? sendTime;
  bool isFinishing = false;

  // 휴식 타이머 관련 변수들
  DateTime? restStartTime;
  int remainingRestSeconds = 0;
  Timer? restTimer;
  bool restCompleted = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSubjectData());
  }

  @override
  void dispose() {
    _textController.dispose();
    restTimer?.cancel();
    super.dispose();
  }

  void _loadSubjectData() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args != null && args is int) {
      subjectNumber = args;
      _loadQuestions();
    }
  }

  Future<void> _loadQuestions() async {
    if (subjectNumber == null) return;
    try {
      final questionTexts =
          await SheetsService.getQuestionsForSubject(subjectNumber!);
      setState(() {
        questions = questionTexts;
      });
    } catch (_) {
      setState(() {
        questions = List.generate(32, (index) => "테스트 질문 ${index + 1}번입니다.");
      });
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
    restCompleted = false; // 다음 질문으로 넘어갈 때 휴식 완료 상태 초기화

    // 16번째 질문 완료 후 10분 휴식
    if (currentQuestionIndex == 16) {
      _startRestPeriod();
      return;
    }

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

  void _startRestPeriod() {
    restStartTime = DateTime.now();
    // remainingRestSeconds = 10 * 60; // 10분 = 600초
    remainingRestSeconds = 10; // 10분 = 600초
    _changeState(ChatbotState.resting);

    // 1초마다 남은 시간 업데이트
    restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        remainingRestSeconds--;
        if (remainingRestSeconds <= 0) {
          timer.cancel();
          _endRestPeriod();
        }
      });
    });
  }

  void _endRestPeriod() {
    restTimer?.cancel();
    restStartTime = null;
    remainingRestSeconds = 0;
    restCompleted = true;

    // 휴식 완료 후 finished 상태로 전환 (사용자가 "다음 질의" 버튼을 클릭할 때까지 대기)
    _changeState(ChatbotState.finished);
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
          isFinishing = false;
        });
        _showSaveErrorDialog();
      }
    } else {
      setState(() {
        isFinishing = false;
      });
    }
  }

  void _showSaveErrorDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
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
              _finishExperiment();
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
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF7F9FB), Color(0xFFE0E6ED)],
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                const SafeArea(bottom: false, child: AppHeader()),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        if (currentState == ChatbotState.loading) ...[
                          const Expanded(child: SizedBox()),
                        ] else if (currentState == ChatbotState.chatting ||
                            messages.isNotEmpty) ...[
                          Expanded(
                            child: ListView(
                              padding: EdgeInsets.zero,
                              children: messages.map((m) {
                                final isUser = m.type == MessageType.user;
                                final bubble = isUser
                                    ? _UserChip(text: m.text)
                                    : _BotBubble(text: m.text);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12.0),
                                  child: Align(
                                    alignment: isUser
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: bubble,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ] else ...[
                          const Expanded(child: SizedBox()),
                        ],
                      ],
                    ),
                  ),
                ),
                Container(
                  color: Colors.transparent,
                  child: SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _textController,
                              maxLines: null,
                              minLines: 1,
                              keyboardType: TextInputType.multiline,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF20262E),
                                height: 1.3,
                              ),
                              decoration: InputDecoration(
                                hintText: '질문을 입력하세요.',
                                hintStyle: const TextStyle(
                                  color: Color(0xFF9AA3AB),
                                  fontSize: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(999),
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
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: _sendButtonColor(),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isProcessingResponse
                                    ? Icons.stop
                                    : Icons.arrow_forward,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (currentState == ChatbotState.initial) _buildInitialOverlay(),
            if (currentState == ChatbotState.finished) _buildFinishedOverlay(),
            if (currentState == ChatbotState.resting) _buildRestingOverlay(),
          ],
        ),
      ),
    );
  }

  Color _sendButtonColor() {
    if (isProcessingResponse) return const Color(0xFF3B82F6);
    return _textController.text.trim().isEmpty
        ? const Color(0xFFE6E9EF)
        : const Color(0xFF3B82F6);
  }

  Widget _buildInitialOverlay() => Positioned.fill(
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
                        fontSize: 18,
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
                        _setCurrentQuestion();
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

  Widget _buildFinishedOverlay() => Positioned.fill(
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
                    child: Text(
                      restCompleted
                          ? '10분 휴식이 완료되었습니다.\n17번째 질문을 시작할 준비가 되시면\n아래 [다음 질의] 버튼을 눌러주세요.'
                          : '평가를 진행할 준비가 되셨을 때,\n아래 [시작] 버튼을 눌러주세요.',
                      style: const TextStyle(
                        fontSize: 18,
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
                            child: const Text('다시 하기',
                                style: TextStyle(fontSize: 16)),
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
                            child: isFinishing && currentQuestionIndex >= 31
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Text('저장 중...',
                                          style: TextStyle(fontSize: 16)),
                                    ],
                                  )
                                : Text(
                                    currentQuestionIndex >= 31
                                        ? '실험 종료'
                                        : '다음 질의',
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

  Widget _buildRestingOverlay() => Positioned.fill(
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
                    child: Column(
                      children: [
                        const Text(
                          '16개 질문이 완료되었습니다.\n10분간 휴식을 취해주세요.',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _formatRestTime(remainingRestSeconds),
                          style: const TextStyle(
                            fontSize: 32,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  const Text(
                    '휴식이 끝나면 자동으로 17번째 질문부터 시작됩니다.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  String _formatRestTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}

class _UserChip extends StatelessWidget {
  final String text;
  const _UserChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EDF3),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          color: Color(0xFF27313A),
        ),
      ),
    );
  }
}

class _BotBubble extends StatelessWidget {
  final String text;
  const _BotBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF20262E),
              height: 1.4,
            ),
          ),
          const SizedBox(width: 13),
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 0.8,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF9AA3AB)),
              strokeCap: StrokeCap.round,
            ),
          ),
        ],
      ),
    );
  }
}
