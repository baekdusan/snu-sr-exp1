import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../services/sheets_service.dart';
import '../models/question_result.dart';

enum ChatbotState { initial, loading, chatting, finished, resting, quiz }

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

  // 트라이얼 관리 (실제 + 더미)
  int currentTrialIndex = 0; // 0..36 (총 37트라이얼)
  int actualQuestionIndex = 0; // 0..31 (실제 32문항)

  final List<QuestionResult> results = [];
  DateTime? sendTime;
  bool isFinishing = false;

  // 휴식 타이머 관련 변수들
  DateTime? restStartTime;
  int remainingRestSeconds = 0;
  Timer? restTimer;
  bool restCompleted = false;

  // 퀴즈 관련 변수들
  List<String> quizOptions = [];
  final Random _rnd = Random();
  final Map<int, int> quizResults = {}; // {trialNo: 1 or 0}

  // 더미 퀴즈 5개 (트라이얼 위치는 1-based)
  final Map<int, Map<String, dynamic>> dummyTrials = {
    4: {
      "dummyQuestion": "지난 주말에 친구들과 본 영화 제목이 뭐였지?",
      "options": [
        "지난 주말에 가족들과 본 영화 제목이 뭐였지?",
        "지난 달에 친구들과 본 드라마 제목이 뭐였지?",
        "지난 주말에 친구들과 본 공연 이름이 뭐였지?",
        "어제 친구들과 본 영화 제목이 뭐였지?",
      ]
    },
    9: {
      "dummyQuestion": "내가 마지막으로 택시를 탄 날은 언제였지?",
      "options": [
        "내가 마지막으로 버스를 탄 날은 언제였지?",
        "내가 어제 택시를 탄 날은 언제였지?",
        "내가 마지막으로 지하철을 탄 날은 언제였지?",
        "내가 이번 달에 택시를 탄 날은 언제였지?",
      ]
    },
    20: {
      "dummyQuestion": "지난 주에 내가 갔다 왔던 카페가 어디였지?",
      "options": [
        "지난 달에 내가 갔다 왔던 카페가 어디였지?",
        "지난 주에 내가 갔다 왔던 음식점이 어디였지?",
        "지난 달에 내가 갔다 왔던 칵테일바가 어디였지?",
        "지난 주에 내가 갔다 왔던 식당이 어디였지?",
      ]
    },
    24: {
      "dummyQuestion": "최근에 가장 많이 쓴 앱은 무엇이지?",
      "options": [
        "최근에 가장 많이 본 앱은 무엇이지?",
        "최근에 가장 많이 쓴 웹사이트는 무엇이지?",
        "지난 달에 가장 많이 쓴 앱은 무엇이지?",
        "최근에 가장 많이 쓴 게임은 무엇이지?",
      ]
    },
    28: {
      "dummyQuestion": "지난 주 평일에 점심으로 먹은 메뉴는 뭐였지?",
      "options": [
        "지난 주말에 점심으로 먹은 메뉴는 뭐였지?",
        "지난 주 평일에 저녁으로 먹은 메뉴는 뭐였지?",
        "지난 달 평일에 점심으로 먹은 메뉴는 뭐였지?",
        "어제 점심으로 먹은 메뉴는 뭐였지?",
      ]
    },
  };

  static const int totalTrials = 32 + 5; // 실제32 + 더미5 = 37

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
      setState(() => questions = questionTexts);
    } catch (_) {
      setState(() {
        questions = List.generate(32, (i) => "테스트 질문 ${i + 1}번입니다.");
      });
    }
  }

  // 현재 트라이얼에 맞는 텍스트필드 표시
  void _setCurrentPromptInField() {
    final trialNo = currentTrialIndex + 1; // 1-based
    if (dummyTrials.containsKey(trialNo)) {
      _textController.text = dummyTrials[trialNo]!["dummyQuestion"];
    } else if (actualQuestionIndex < questions.length) {
      _textController.text = questions[actualQuestionIndex];
    } else {
      _textController.text = '';
    }
  }

  void _changeState(ChatbotState s) => setState(() => currentState = s);

  // 실험 완료 확인 (다음 트라이얼이 37번째인지 확인)
  bool _isExperimentComplete() {
    return currentTrialIndex >= 36; // 37번째 트라이얼이면 종료
  }

  // 발송/중지 버튼 - 발송
  void _sendMessage() {
    if (_textController.text.isEmpty || isProcessingResponse) return;

    final trialNo = currentTrialIndex + 1;
    sendTime = DateTime.now();
    FocusScope.of(context).unfocus();

    // 더미 트라이얼 → 메시지 쌓지 않고 퀴즈로 진입
    if (dummyTrials.containsKey(trialNo)) {
      _startQuiz(trialNo);
      return;
    }

    // 실제 트라이얼 → 기존 채팅 로직
    final userMessage = _textController.text;
    setState(() {
      messages.add(ChatMessage(
        text: userMessage,
        type: MessageType.user,
        timestamp: DateTime.now(),
      ));
      _textController.clear();
      isProcessingResponse = true;
    });

    setState(() {
      messages.add(ChatMessage(
        text: "잠시만 기다려 주세요.",
        type: MessageType.bot,
        timestamp: DateTime.now(),
      ));
      currentState = ChatbotState.chatting;
    });
  }

  // 발송/중지 버튼 - 중지
  void _stopProcessing() {
    if (!isProcessingResponse || sendTime == null) return;

    final stopTime = DateTime.now();
    final latencyMs = stopTime.difference(sendTime!).inMilliseconds;

    // 실제 질문만 저장(더미는 저장 X)
    print(
        '🔍 _stopProcessing: actualQuestionIndex=$actualQuestionIndex, questions.length=${questions.length}');
    if (actualQuestionIndex >= 0 && actualQuestionIndex < questions.length) {
      results.add(QuestionResult(
        questionNumber: actualQuestionIndex + 1,
        questionText: questions[actualQuestionIndex],
        sendTime: sendTime!,
        stopTime: stopTime,
        latencyMs: latencyMs,
      ));
      print('💾 결과 저장됨: ${actualQuestionIndex + 1}번째 질문, 총 ${results.length}개');
    } else {
      print(
          '❌ 결과 저장 안됨: actualQuestionIndex=$actualQuestionIndex, questions.length=${questions.length}');
    }

    setState(() {
      isProcessingResponse = false;
      currentState = ChatbotState.finished; // finished 오버레이
    });
  }

  // finished 오버레이: 다음 질의
  void _nextQuestion() {
    // 휴식 완료 상태가 아닐 때만 트라이얼 진행
    if (!restCompleted) {
      // 방금 끝난 것이 실제였는지/더미였는지 판별 위해 이전 트라이얼 번호 보존
      final prevTrialNo = currentTrialIndex + 1;
      final wasDummy = dummyTrials.containsKey(prevTrialNo);

      // 트라이얼 진행
      currentTrialIndex++;

      // 실제였으면 실제 인덱스 증가
      if (!wasDummy) {
        actualQuestionIndex++;
      }

      // 18번째 트라이얼 완료 시 휴식 진입
      if (currentTrialIndex == 18) {
        _startRestPeriod();
        return;
      }
    }

    messages.clear();
    restCompleted = false;

    // 37개 트라이얼 모두 완료 확인
    if (currentTrialIndex >= 37) {
      _finishExperiment();
      return;
    }

    // 다음 트라이얼 진행
    _setCurrentPromptInField();
    _changeState(ChatbotState.loading);
  }

  // finished 오버레이: 다시 하기
  void _retryCurrentQuestion() {
    // 실제 질문인 경우만 되돌림
    if (results.isNotEmpty) results.removeLast();
    messages.clear();
    _setCurrentPromptInField();
    _changeState(ChatbotState.loading);
  }

  // 10분 휴식(데모용 10초)
  void _startRestPeriod() {
    restStartTime = DateTime.now();
    remainingRestSeconds = 600; // 실제 600초
    _changeState(ChatbotState.resting);

    restTimer?.cancel();
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
    _changeState(ChatbotState.finished); // 휴식 끝나면 finished 오버레이
  }

  // ====== QUIZ ======
  void _startQuiz(int trialNo) {
    final quizData = dummyTrials[trialNo];
    if (quizData == null) return;

    // 옵션 5개: 정답 + 오답4 → 한 번만 셔플해서 고정
    final correct = quizData["dummyQuestion"] as String;
    final List<String> opts = List<String>.from(quizData["options"]);
    opts.add(correct);
    opts.shuffle(_rnd);
    setState(() {
      quizOptions = opts;
      currentState = ChatbotState.quiz;
      // 텍스트 필드는 퀴즈 진입 시 비움(중복 메시지 방지)
      _textController.clear();
    });
  }

  void _answerQuiz(String selected) {
    final trialNo = currentTrialIndex + 1;
    final quizData = dummyTrials[trialNo]!;
    final correct = quizData["dummyQuestion"] as String;
    final isCorrect = (selected == correct);

    // 1/0 기록
    quizResults[trialNo] = isCorrect ? 1 : 0;

    // 트라이얼 소비
    currentTrialIndex++;

    // 18번째 끝났다면 바로 휴식 진입
    if (currentTrialIndex == 18) {
      _startRestPeriod();
      return;
    }

    // 다음으로
    setState(() {
      currentState = ChatbotState.initial; // 항상 initial로 복귀 → 시작 버튼 누르면 다음 로딩
    });
  }
  // ====== QUIZ END ======

  Future<void> _finishExperiment() async {
    setState(() => isFinishing = true);
    try {
      await SheetsService.recordAllResults(
        subjectNumber: subjectNumber ?? -1,
        results: results,
        quizResults: quizResults,
      );
      if (mounted) Navigator.pushReplacementNamed(context, '/');
    } catch (_) {
      setState(() => isFinishing = false);
      _showSaveErrorDialog();
    }
  }

  void _showSaveErrorDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('데이터 저장 실패'),
        content: const Text('실험 데이터 저장에 실패했습니다.\n네트워크 연결을 확인하고 다시 시도해주세요.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _finishExperiment();
            },
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
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
                                    padding:
                                        const EdgeInsets.only(bottom: 12.0),
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
                                      : Icons.arrow_upward,
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
              if (currentState == ChatbotState.finished)
                _buildFinishedOverlay(),
              if (currentState == ChatbotState.resting) _buildRestingOverlay(),
              if (currentState == ChatbotState.quiz) _buildQuizOverlay(),
            ],
          ),
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

  // ====== 오버레이들 ======
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
                          fontSize: 18, color: Colors.white, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        _setCurrentPromptInField();
                        _changeState(ChatbotState.loading);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
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
                          : (_isExperimentComplete()
                              ? '실험이 완료되었습니다.\n아래 [실험 종료] 버튼을 눌러주세요.'
                              : '평가를 진행할 준비가 되셨을 때,\n아래 버튼을 눌러주세요.'),
                      style: const TextStyle(
                          fontSize: 18, color: Colors.white, height: 1.5),
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
                                  borderRadius: BorderRadius.circular(8)),
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
                              backgroundColor: _isExperimentComplete()
                                  ? Colors.red
                                  : Colors.blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: isFinishing && _isExperimentComplete()
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
                                    _isExperimentComplete() ? '실험 종료' : '다음 질의',
                                    style: const TextStyle(fontSize: 16)),
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
                          '전체 32개 트라이얼 중 16개가 끝났습니다.\n10분간 휴식을 취해주세요.',
                          style: TextStyle(
                              fontSize: 18, color: Colors.white, height: 1.5),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _formatRestTime(remainingRestSeconds),
                          style: const TextStyle(
                              fontSize: 32,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  const Text(
                    '휴식이 끝나면 17번째 트라이얼부터 재개됩니다.',
                    style: TextStyle(fontSize: 14, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  String _formatRestTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildQuizOverlay() {
    final trialNo = currentTrialIndex + 1;
    final quizData = dummyTrials[trialNo];
    if (quizData == null) return const SizedBox();

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "조금 전에 읽으신 질의를 선택해주세요.",
                  style: TextStyle(fontSize: 18, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ...quizOptions.map((opt) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.all(16),
                        ),
                        onPressed: () => _answerQuiz(opt),
                        child: Text(opt, textAlign: TextAlign.center),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ▼▼▼ 상태 클래스 바깥(원본 UI 유지) ▼▼▼
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
          borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: const TextStyle(fontSize: 16, color: Color(0xFF27313A))),
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
                height: 1.4),
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
