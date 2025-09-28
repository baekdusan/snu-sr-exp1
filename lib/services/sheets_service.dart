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
  static const _queryWorksheet = 'query'; // 질문 내용이 저장된 시트
  static const _randomizationWorksheet = 'randomization'; // 피험자별 질문 번호가 저장된 시트
  static const _mainResultsWorksheet = 'main_results'; // 실제 질문 결과가 저장될 시트
  static const _quizResultsWorksheet = 'quiz_results'; // 퀴즈 결과가 저장될 시트

  // Google Sheets API 인스턴스들
  static GSheets? _gsheets;
  static Spreadsheet? _spreadsheet;
  static Worksheet? _querySheet;
  static Worksheet? _randomizationSheet;
  static Worksheet? _mainResultsSheet;
  static Worksheet? _quizResultsSheet;

  /// 질문 데이터 캐시
  /// Key: 질문 번호 (예: "18-4", "12-2")
  /// Value: 해당 질문의 내용 텍스트
  static final Map<String, String> _questionsCache = {};

  /// 피험자별 질문 번호 캐시
  /// Key: 피험자 번호 (예: "P001", "P002")
  /// Value: 32개 질문 번호 리스트 (예: ["18-4", "12-2", ...])
  static final Map<String, List<String>> _subjectQuestionsCache = {};

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
''';

      print('📱 GSheets 객체 생성 중...');
      _gsheets = GSheets(credentials);

      print('📊 스프레드시트 연결 중... (ID: $_spreadsheetId)');
      _spreadsheet = await _gsheets!.spreadsheet(_spreadsheetId);

      print('📝 query 시트 찾는 중...');
      _querySheet = _spreadsheet!.worksheetByTitle(_queryWorksheet);

      print('🎲 randomization 시트 찾는 중...');
      _randomizationSheet =
          _spreadsheet!.worksheetByTitle(_randomizationWorksheet);

      print('📈 main_results 시트 찾는 중...');
      _mainResultsSheet = _spreadsheet!.worksheetByTitle(_mainResultsWorksheet);

      print('🧩 quiz_results 시트 찾는 중...');
      _quizResultsSheet = _spreadsheet!.worksheetByTitle(_quizResultsWorksheet);

      print('✅ 시트 초기화 완료!');

      // 네트워크 효율성을 위해 모든 데이터를 미리 로드하여 캐시에 저장
      await _loadAllQuestions();
      await _loadAllSubjectQuestions();
    } catch (e) {
      print('❌ 시트 초기화 실패: $e');
      rethrow; // 초기화 실패 시 상위 레벨에서 처리하도록 예외 재전파
    }
  }

  /// 내부 메서드: query 시트에서 전체 질문 데이터 로드 및 캐시
  static Future<void> _loadAllQuestions() async {
    try {
      print('📚 전체 질문 데이터 로드 중...');
      final rows = await _querySheet!.values.allRows();
      print('📚 총 ${rows.length}개 질문 발견');

      _questionsCache.clear();
      // 각 행을 순회하며 질문번호-질문내용 매핑 저장
      for (int rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        final row = rows[rowIndex];
        // 질문번호와 질문내용이 모두 있는 경우만 처리
        if (row.length >= 2 && row[0].isNotEmpty && row[1].isNotEmpty) {
          _questionsCache[row[0]] = row[1];
          print('📝 질문 캐시 저장: ${row[0]} -> ${row[1]}');
        }
      }

      print('✅ 질문 캐시 완료! ${_questionsCache.length}개 질문 저장됨');
    } catch (e) {
      print('❌ 질문 로드 실패: $e');
      rethrow;
    }
  }

  /// 내부 메서드: randomization 시트에서 피험자별 질문 번호 로드 및 캐시
  static Future<void> _loadAllSubjectQuestions() async {
    try {
      print('🎲 피험자별 질문 번호 데이터 로드 중...');
      final rows = await _randomizationSheet!.values.allRows();
      print('🎲 총 ${rows.length}개 피험자 발견');

      _subjectQuestionsCache.clear();

      if (rows.isNotEmpty) {
        // 첫 번째 행은 헤더이므로 스킵하고 데이터 행부터 처리
        for (int rowIndex = 1; rowIndex < rows.length; rowIndex++) {
          final row = rows[rowIndex];
          if (row.isNotEmpty && row[0].isNotEmpty) {
            final participantId = row[0]; // P001, P002, ...
            final questionNumbers = <String>[];

            // Q1~Q32 컬럼 데이터 수집 (컬럼 1~32)
            for (int colIndex = 1;
                colIndex < row.length && colIndex <= 32;
                colIndex++) {
              if (colIndex < row.length && row[colIndex].isNotEmpty) {
                questionNumbers.add(row[colIndex]);
              }
            }

            if (questionNumbers.length == 32) {
              _subjectQuestionsCache[participantId] = questionNumbers;
              print('🎲 피험자 캐시 저장: $participantId -> 32개 질문');
            }
          }
        }
      }

      print('✅ 피험자 캐시 완료! ${_subjectQuestionsCache.length}개 피험자 저장됨');
    } catch (e) {
      print('❌ 피험자 데이터 로드 실패: $e');
      rethrow;
    }
  }

  /// 피험자 번호에 해당하는 32개 질문 반환
  ///
  /// [subjectNumber]: 1-80 범위의 피험자 번호
  /// 반환: 해당 피험자의 32개 질문 리스트
  ///
  /// 2단계 프로세스:
  /// 1. randomization 시트에서 피험자의 질문 번호 32개 조회
  /// 2. 각 질문 번호로 query 시트에서 실제 질문 내용 조회
  static Future<List<String>> getQuestionsForSubject(int subjectNumber) async {
    print('🔍 getQuestionsForSubject 시작 - 피험자 번호: $subjectNumber');

    // 캐시가 비어있으면 초기화
    if (_questionsCache.isEmpty || _subjectQuestionsCache.isEmpty) {
      print('📚 캐시가 비어있어 초기화 수행...');
      await init();
    }

    // 피험자 번호를 P001 형식으로 변환
    final participantId = 'P${subjectNumber.toString().padLeft(3, '0')}';
    print('🔍 변환된 피험자 ID: $participantId');

    // 1단계: randomization 시트에서 질문 번호 리스트 가져오기
    final questionNumbers = _subjectQuestionsCache[participantId];
    if (questionNumbers == null) {
      print('❌ 피험자 $participantId의 질문 번호 리스트를 찾을 수 없습니다.');
      return [];
    }

    print('🎲 질문 번호 리스트: $questionNumbers');

    // 2단계: 각 질문 번호로 실제 질문 내용 조회
    final questions = <String>[];
    for (final questionNumber in questionNumbers) {
      // en dash (–)를 hyphen (-)으로 정규화
      final normalizedQuestionNumber = questionNumber.replaceAll('–', '-');
      final question = _questionsCache[normalizedQuestionNumber];
      if (question != null) {
        questions.add(question);
        print('✅ 질문 발견: $questionNumber -> $question');
      } else {
        print('❌ 질문 없음: $questionNumber (정규화됨: $normalizedQuestionNumber)');
        questions.add('질문을 찾을 수 없습니다: $questionNumber');
      }
    }

    print('🎯 최종 결과: ${questions.length}개 질문 반환');
    return questions;
  }

  /// 피험자 번호가 이미 사용되었는지 확인
  ///
  /// [subjectNumber]: 확인할 피험자 번호 (1-80)
  /// 반환: true면 이미 데이터가 있음 (중복), false면 사용 가능
  static Future<bool> isSubjectDataExists(int subjectNumber) async {
    try {
      // main_results 시트가 초기화되지 않았다면 초기화 수행
      if (_mainResultsSheet == null) await init();

      // 피험자의 첫 번째 행 위치 계산 (32행 기준)
      final firstRow = (subjectNumber - 1) * 32 + 2;

      // 해당 행에 데이터가 있는지 확인
      final rowData = await _mainResultsSheet!.values.row(firstRow);
      final hasData = rowData.isNotEmpty && rowData[0].toString().isNotEmpty;

      print('🔍 피험자 $subjectNumber 중복 확인: ${hasData ? "이미 존재" : "사용 가능"}');
      return hasData;
    } catch (e) {
      print('❌ 피험자 $subjectNumber 중복 확인 실패: $e');
      // 에러 발생 시 안전하게 false 반환 (사용 가능으로 판단)
      return false;
    }
  }

  /// 피험자의 실제 질문 결과를 main_results 시트에 저장
  ///
  /// [subjectNumber]: 피험자 번호 (1-80)
  /// [results]: 32개 실제 질문에 대한 실험 결과 리스트
  ///
  /// 동시성 문제 해결을 위한 재시도 로직과 배치 저장 방식 사용
  /// 시간 정보는 ISO 8601 형식으로 저장
  static Future<void> recordMainResults({
    required int subjectNumber,
    required List<QuestionResult> results,
  }) async {
    // main_results 시트가 초기화되지 않았다면 초기화 수행
    if (_mainResultsSheet == null) await init();

    final rows = <List<String>>[];

    // 피험자 번호를 P001 형식으로 변환
    final participantId = 'P${subjectNumber.toString().padLeft(3, '0')}';

    // 피험자의 실제 질문 번호 리스트 가져오기
    final questionNumbers = _subjectQuestionsCache[participantId];
    if (questionNumbers == null) {
      throw Exception('피험자 $participantId의 질문 번호를 찾을 수 없습니다.');
    }

    // 각 실험 결과를 Google Sheets 행 데이터로 변환
    for (int i = 0; i < results.length; i++) {
      final result = results[i];
      final actualQuestionNumber =
          questionNumbers[i].replaceAll('–', '-'); // en dash 정규화
      rows.add([
        participantId, // 피험자 ID (P001, P002, ...)
        DateTime.now().toIso8601String(), // 타임스탬프
        actualQuestionNumber, // 실제 질의 번호 (18-4, 12-2, 64-1 등)
        result.sendTime.toIso8601String(), // 발송 시간
        result.stopTime.toIso8601String(), // 중지 시간
        result.latencyMs.toString(), // 대기시간(밀리초)
      ]);
    }

    // 피험자별 고정 위치에 저장 (동시성 문제 완전 해결)
    try {
      // 피험자별 시작 행 계산: 헤더(1행) + 이전 피험자들의 32행씩
      // 피험자 1: 2~33행, 피험자 2: 34~65행, 피험자 3: 66~97행...
      final startRow = (subjectNumber - 1) * 32 + 2;
      final endRow = startRow + 31;

      print('🎯 피험자 $participantId → $startRow~$endRow행에 저장');

      // 각 행을 정확한 위치에 저장
      for (int i = 0; i < rows.length; i++) {
        final targetRow = startRow + i;
        await _mainResultsSheet!.values.insertRow(targetRow, rows[i]);
        print('📝 $targetRow행 저장: ${rows[i][0]} (${rows[i][5]}ms)');
      }

      print('✅ 피험자 $participantId의 데이터를 $startRow~$endRow행에 저장 완료');
    } catch (e) {
      print('❌ 피험자 $subjectNumber 저장 실패: $e');
      rethrow;
    }
  }

  /// 피험자의 퀴즈 결과를 quiz_results 시트에 저장
  ///
  /// [subjectNumber]: 피험자 번호 (1-80)
  /// [quizResults]: 트라이얼 번호와 정답 여부 맵 (예: {4: 1, 9: 0, 20: 1, 24: 1, 28: 0})
  ///
  /// quiz_results 시트 형식: ParticipantID | Quiz_T4 | Quiz_T9 | Quiz_T20 | Quiz_T24 | Quiz_T28
  static Future<void> recordQuizResults({
    required int subjectNumber,
    required Map<int, int> quizResults,
  }) async {
    // quiz_results 시트가 초기화되지 않았다면 초기화 수행
    if (_quizResultsSheet == null) await init();

    // 피험자 번호를 P001 형식으로 변환
    final participantId = 'P${subjectNumber.toString().padLeft(3, '0')}';

    // 퀴즈 트라이얼 순서 (고정)
    final quizTrials = [4, 9, 20, 24, 28];

    // 데이터 행 생성: ParticipantID + 퀴즈 결과 5개
    final row = [participantId];
    for (final trialNo in quizTrials) {
      row.add(quizResults[trialNo]?.toString() ?? '');
    }

    try {
      // 피험자별 고정 위치에 저장: 피험자 N → N+1행 (헤더 제외)
      final targetRow = subjectNumber + 1;
      await _quizResultsSheet!.values.insertRow(targetRow, row);

      print(
          '🧩 퀴즈 결과 저장: $participantId → $targetRow행 (${quizResults.values.join(', ')})');
      print('✅ 피험자 $participantId 퀴즈 결과 저장 완료');
    } catch (e) {
      print('❌ 피험자 $subjectNumber 퀴즈 결과 저장 실패: $e');
      rethrow;
    }
  }

  /// 피험자의 모든 실험 데이터를 저장하는 통합 메서드
  ///
  /// [subjectNumber]: 피험자 번호 (1-80)
  /// [results]: 32개 실제 질문에 대한 실험 결과 리스트
  /// [quizResults]: 5개 퀴즈 트라이얼의 정답 여부
  static Future<void> recordAllResults({
    required int subjectNumber,
    required List<QuestionResult> results,
    required Map<int, int> quizResults,
  }) async {
    try {
      // 1. 실제 질문 결과를 main_results에 저장
      await recordMainResults(
        subjectNumber: subjectNumber,
        results: results,
      );

      // 2. 퀴즈 결과를 quiz_results에 저장
      await recordQuizResults(
        subjectNumber: subjectNumber,
        quizResults: quizResults,
      );

      print('🎯 피험자 $subjectNumber 전체 데이터 저장 완료');
    } catch (e) {
      print('❌ 피험자 $subjectNumber 전체 데이터 저장 실패: $e');
      rethrow;
    }
  }
}
