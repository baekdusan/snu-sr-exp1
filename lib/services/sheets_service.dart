import 'package:gsheets/gsheets.dart';
import '../models/question_result.dart';

/// Google Sheets API를 사용한 실험 데이터 관리 서비스
///
/// 이 서비스는 다음 기능을 제공합니다:
/// - 피험자별 질문 데이터 로드 및 캐싱
/// - 실험 결과 데이터를 Google Sheets에 저장
/// - 네트워크 효율성을 위한 배치 처리
class SheetsService {
  // Google Sheets 스프레드시트 ID
  static const _spreadsheetId = '1-rsl18qwNWtQmSjiOVeSkDoriNmVwwYUVURb2bJi6qk';

  // 워크시트 이름 상수
  static const _queryWorksheet = 'query'; // 질문 데이터가 저장된 시트
  static const _outputWorksheet = 'output'; // 실험 결과가 저장될 시트

  // Google Sheets API 인스턴스들
  static GSheets? _gsheets;
  static Spreadsheet? _spreadsheet;
  static Worksheet? _querySheet;
  static Worksheet? _outputSheet;

  /// 질문 데이터 캐시 (피험자ID → 질문내용)
  ///
  /// 네트워크 요청을 최소화하기 위해 앱 시작 시 모든 질문을 메모리에 로드
  /// Key: "1-1", "1-2", ... "64-4" 형태의 피험자ID-질문번호
  /// Value: 해당 질문의 내용 텍스트
  static final Map<String, String> _questionsCache = {};

  /// Google Sheets API 초기화 및 질문 데이터 캐시 로드
  ///
  /// 이 메서드는 다음 작업을 수행합니다:
  /// 1. Google Service Account 인증 정보로 API 연결
  /// 2. 지정된 스프레드시트 및 워크시트에 접근
  /// 3. 전체 질문 데이터를 메모리에 캐시
  ///
  /// 실험 앱 시작 시 한 번만 호출되며, 이후 모든 질문 조회는 캐시를 사용
  static Future<void> init() async {
    try {
      print('🔑 인증 정보 설정 중...'); // 개발용 로깅, 프로덕션에서는 제거 권장

      // Google Service Account 인증 정보
      // 실제 운영 환경에서는 환경변수나 보안 저장소 사용 권장
      const credentials = r'''
{
  "type": "",
  "project_id": "",
  "private_key_id": "",
  "private_key": "",
  "client_email": "",
  "client_id": "",
  "auth_uri": "",
  "token_uri": "",
  "auth_provider_x509_cert_url": "",
  "client_x509_cert_url": "",
  "universe_domain": ""
}
''';

      print('📱 GSheets 객체 생성 중...');
      _gsheets = GSheets(credentials);

      print('📊 스프레드시트 연결 중... (ID: $_spreadsheetId)');
      _spreadsheet = await _gsheets!.spreadsheet(_spreadsheetId);

      print('📝 query 시트 찾는 중...');
      _querySheet = _spreadsheet!.worksheetByTitle(_queryWorksheet);

      print('📈 output 시트 찾는 중...');
      _outputSheet = _spreadsheet!.worksheetByTitle(_outputWorksheet);

      print('✅ 시트 초기화 완료!');

      // 네트워크 효율성을 위해 모든 질문을 미리 로드하여 캐시에 저장
      await _loadAllQuestions();
    } catch (e) {
      print('❌ 시트 초기화 실패: $e');
      rethrow; // 초기화 실패 시 상위 레벨에서 처리하도록 예외 재전파
    }
  }

  /// 내부 메서드: Google Sheets에서 전체 질문 데이터 로드 및 캐시
  ///
  /// query 시트의 모든 행을 읽어 피험자ID-질문내용 매핑을 만들어 캐시에 저장
  /// 이후 질문 조회 시 O(1) 시간복잡도로 빠른 응답 가능
  static Future<void> _loadAllQuestions() async {
    try {
      print('📚 전체 질문 데이터 로드 중...');
      final rows = await _querySheet!.values.allRows();
      print('📚 총 ${rows.length}개 행 발견');

      _questionsCache.clear();
      // 각 행을 순회하며 유효한 데이터만 캐시에 저장
      for (int rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        final row = rows[rowIndex];
        // 피험자ID와 질문내용이 모두 있는 경우만 처리
        if (row.length >= 2 && row[0].isNotEmpty && row[1].isNotEmpty) {
          _questionsCache[row[0]] = row[1];
          print('📝 캐시 저장: ${row[0]} -> ${row[1]}');
        }
      }

      print('✅ 질문 캐시 완료! ${_questionsCache.length}개 질문 저장됨');
    } catch (e) {
      print('❌ 질문 로드 실패: $e');
      rethrow;
    }
  }

  /// 피험자 번호에 해당하는 4개 질문 반환
  ///
  /// [subjectNumber]: 1-64 범위의 피험자 번호
  /// 반환: 해당 피험자의 4개 질문 리스트 (1번부터 4번 순서)
  ///
  /// 캐시에서 질문을 조회하므로 매우 빠른 응답 속도 제공
  /// 캐시가 비어있을 경우 자동으로 초기화 수행
  static Future<List<String>> getQuestionsForSubject(int subjectNumber) async {
    print('🔍 getQuestionsForSubject 시작 - 피험자 번호: $subjectNumber');

    // 캐시 상태 확인 및 필요시 초기화
    if (_questionsCache.isEmpty) {
      print('📊 캐시가 비어있음, 시트 초기화 중...');
      await init();
    }

    final questions = <String>[];

    print('📋 캐시에서 질문 검색 중...');
    // 1번부터 4번까지 질문 순차적 조회
    for (int i = 1; i <= 4; i++) {
      final questionId = '$subjectNumber-$i';
      print('🔎 찾는 질문 ID: $questionId');

      final question = _questionsCache[questionId];
      if (question != null) {
        questions.add(question);
        print('✅ 캐시에서 발견: $questionId -> $question');
      } else {
        print('❌ 캐시에서 찾을 수 없음: $questionId');
      }
    }

    print('🎯 최종 질문 목록 (${questions.length}개):');
    for (int i = 0; i < questions.length; i++) {
      print('  ${i + 1}: ${questions[i]}');
    }

    return questions;
  }

  /// 피험자의 전체 실험 결과를 Google Sheets에 일괄 저장
  ///
  /// [subjectNumber]: 피험자 번호 (1-64)
  /// [results]: 4개 질문에 대한 실험 결과 리스트
  ///
  /// 각 결과를 output 시트에 순차적으로 추가하여 저장
  /// 시간 정보는 ISO 8601 형식으로 저장
  static Future<void> recordAllResults({
    required int subjectNumber,
    required List<QuestionResult> results,
  }) async {
    // output 시트가 초기화되지 않았다면 초기화 수행
    if (_outputSheet == null) await init();

    final rows = <List<String>>[];

    // 각 실험 결과를 Google Sheets 행 데이터로 변환
    for (final result in results) {
      final questionId = '$subjectNumber-${result.questionNumber}';
      rows.add([
        questionId, // 피험자 ID
        DateTime.now().toIso8601String(), // 타임스탬프
        questionId, // 질의 번호
        result.sendTime.toIso8601String(), // 발송 시간
        result.stopTime.toIso8601String(), // 중지 시간
        result.latencyMs.toString(), // 대기시간(밀리초)
      ]);
    }

    // 모든 결과를 순차적으로 시트에 추가
    for (final row in rows) {
      await _outputSheet!.values.appendRow(row);
    }
  }
}
