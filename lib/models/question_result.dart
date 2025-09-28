/// 실험 중 하나의 질문에 대한 사용자 반응 결과를 저장하는 데이터 모델
///
/// 이 클래스는 사용자가 질문을 전송한 시점부터 응답을 중단한 시점까지의
/// 모든 정보를 포함하여 실험 데이터 분석에 필요한 정보를 제공합니다.
class QuestionResult {
  /// 질문 번호 (1-32)
  /// 각 피험자마다 32개의 질문을 순차적으로 진행
  final int questionNumber;

  /// 실제 질문 내용 텍스트
  /// Google Sheets에서 로드된 질문의 원본 내용
  final String questionText;

  /// 질문 전송 시간
  /// 사용자가 화살표 버튼을 클릭하여 질문을 전송한 정확한 시점
  final DateTime sendTime;

  /// 응답 중단 시간
  /// 사용자가 중지 버튼을 클릭하여 대기를 중단한 정확한 시점
  final DateTime stopTime;

  /// 대기 시간 (밀리초 단위)
  /// sendTime과 stopTime의 차이로 계산된 사용자의 인내심 측정 지표
  final int latencyMs;

  /// QuestionResult 생성자
  ///
  /// 모든 필드가 required이므로 실험 결과의 완전성을 보장
  const QuestionResult({
    required this.questionNumber,
    required this.questionText,
    required this.sendTime,
    required this.stopTime,
    required this.latencyMs,
  });

  /// 디버깅 및 로깅을 위한 문자열 표현
  @override
  String toString() {
    return 'QuestionResult(questionNumber: $questionNumber, '
        'latencyMs: $latencyMs, sendTime: $sendTime, stopTime: $stopTime)';
  }
}