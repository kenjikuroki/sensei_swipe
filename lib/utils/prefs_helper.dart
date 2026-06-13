import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PrefsHelper {
  static const String _keyWeakQuestions = 'weak_questions';
  static const String _keyAdCounter = 'ad_counter';
  static const String _keyOfferShownV1 = 'special_offer_shown_v1';
  static const String _keyTutorialShown = 'tutorial_shown_v1';
  static const String _keyAppData = 'cached_app_data';

  static Future<void> saveAppDataCache(String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAppData, json);
  }

  static Future<String?> getAppDataCache() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAppData);
  }

  static Future<bool> shouldShowInterstitial() async {
    final prefs = await SharedPreferences.getInstance();
    int current = prefs.getInt(_keyAdCounter) ?? 0;
    current++;
    await prefs.setInt(_keyAdCounter, current);
    return (current % 2 == 0);
  }

  static Future<void> saveHighScore(String categoryKey, int score) async {
    final prefs = await SharedPreferences.getInstance();
    final currentHigh = prefs.getInt(categoryKey) ?? 0;
    if (score > currentHigh) {
      await prefs.setInt(categoryKey, score);
    }
  }

  static Future<int> getHighScore(String categoryKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(categoryKey) ?? 0;
  }

  static Future<void> addWeakQuestions(List<String> questions) async {
    if (questions.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final List<String> current = prefs.getStringList(_keyWeakQuestions) ?? [];

    bool changed = false;
    for (final q in questions) {
      if (!current.contains(q)) {
        current.add(q);
        changed = true;
      }
    }

    if (changed) {
      await prefs.setStringList(_keyWeakQuestions, current);
    }
  }

  static Future<void> removeWeakQuestions(List<String> questions) async {
    if (questions.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final List<String> current = prefs.getStringList(_keyWeakQuestions) ?? [];

    bool changed = false;
    for (final q in questions) {
      if (current.remove(q)) {
        changed = true;
      }
    }

    if (changed) {
      await prefs.setStringList(_keyWeakQuestions, current);
    }
  }

  static Future<List<String>> getWeakQuestions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyWeakQuestions) ?? [];
  }

  // --- Special Offer Persistence ---

  static Future<bool> isSpecialOfferShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOfferShownV1) ?? false;
  }

  static Future<void> markSpecialOfferShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOfferShownV1, true);
  }

  static Future<bool> isTutorialShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyTutorialShown) ?? false;
  }

  static Future<void> markTutorialShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTutorialShown, true);
  }

  static const String _keyQuizCompletionCount = 'quiz_completion_count';

  static Future<int> incrementQuizCompletionCount() async {
    final prefs = await SharedPreferences.getInstance();
    int current = prefs.getInt(_keyQuizCompletionCount) ?? 0;
    current++;
    await prefs.setInt(_keyQuizCompletionCount, current);
    return current;
  }

  static Future<int> getQuizCompletionCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyQuizCompletionCount) ?? 0;
  }

  static Future<bool> shouldShowReviewPrompt() async {
    final count = await getQuizCompletionCount();
    return count == 3;
  }

  // ---- Bookmarks ----
  static const String _bookmarkKey = 'bookmark_questions_unkou';

  static Future<void> addBookmarkedQuestions(List<String> questions) async {
    if (questions.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_bookmarkKey) ?? <String>[];
    bool changed = false;
    for (final q in questions) {
      if (!current.contains(q)) {
        current.add(q);
        changed = true;
      }
    }
    if (changed) await prefs.setStringList(_bookmarkKey, current);
  }

  static Future<void> removeBookmarkedQuestions(List<String> questions) async {
    if (questions.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_bookmarkKey) ?? <String>[];
    bool changed = false;
    for (final q in questions) {
      if (current.remove(q)) changed = true;
    }
    if (changed) await prefs.setStringList(_bookmarkKey, current);
  }

  static Future<List<String>> getBookmarkedQuestions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_bookmarkKey) ?? [];
  }

  // ---- Learning Stats ----
  static const String _keyTotalAnswered = 'total_answered_unkou';
  static const String _keyBestStreak = 'best_streak_unkou';
  static const String _keyDailyAnswered = 'daily_answered_unkou';
  static const String _keyDailyBestStreak = 'daily_best_streak_unkou';
  static const String _keyCatAnsweredPrefix = 'cat_answered_unkou_';
  static const String _keyCatCorrectPrefix = 'cat_correct_unkou_';

  static Future<void> addAnsweredCount(int count) async {
    if (count <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_keyTotalAnswered) ?? 0;
    await prefs.setInt(_keyTotalAnswered, current + count);
  }

  static Future<int> getAnsweredCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyTotalAnswered) ?? 0;
  }

  static Future<void> saveBestStreak(int streak) async {
    if (streak <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_keyBestStreak) ?? 0;
    if (streak > current) await prefs.setInt(_keyBestStreak, streak);
  }

  static Future<int> getBestStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyBestStreak) ?? 0;
  }

  static Future<void> addCategoryAnsweredCount(
    String categoryKey,
    int count,
  ) async {
    if (count <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_keyCatAnsweredPrefix$categoryKey';
    final current = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, current + count);
  }

  static Future<void> addCategoryCorrectCount(
    String categoryKey,
    int count,
  ) async {
    if (count <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final key = '$_keyCatCorrectPrefix$categoryKey';
    final current = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, current + count);
  }

  static Future<int> getCategoryAnsweredCount(String categoryKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_keyCatAnsweredPrefix$categoryKey') ?? 0;
  }

  static Future<int> getCategoryCorrectCount(String categoryKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_keyCatCorrectPrefix$categoryKey') ?? 0;
  }

  static String _todayKey() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  static Future<Map<String, int>> _getDailyMap(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      return decoded.map(
        (k, v) => MapEntry(k, v is int ? v : int.tryParse('$v') ?? 0),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveDailyMap(String key, Map<String, int> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(data));
  }

  static Future<void> addDailyAnsweredCount(int count) async {
    if (count <= 0) return;
    final current = await _getDailyMap(_keyDailyAnswered);
    final today = _todayKey();
    current[today] = (current[today] ?? 0) + count;
    await _saveDailyMap(_keyDailyAnswered, current);
  }

  static Future<Map<String, int>> getDailyAnsweredHistory() async {
    return _getDailyMap(_keyDailyAnswered);
  }

  static Future<void> saveDailyBestStreak(int streak) async {
    if (streak <= 0) return;
    final current = await _getDailyMap(_keyDailyBestStreak);
    final today = _todayKey();
    final existing = current[today] ?? 0;
    if (streak > existing) {
      current[today] = streak;
      await _saveDailyMap(_keyDailyBestStreak, current);
    }
  }

  static Future<Map<String, int>> getDailyBestStreakHistory() async {
    return _getDailyMap(_keyDailyBestStreak);
  }

  static Future<int> getConsecutiveDaysStreak() async {
    final history = await getDailyAnsweredHistory();
    final now = DateTime.now();
    final todayKey = _todayKey();
    // If studied today, start from today; otherwise from yesterday (streak still alive until midnight)
    final startOffset = (history[todayKey] ?? 0) > 0 ? 0 : 1;
    int streak = 0;
    for (int i = startOffset; i < 365; i++) {
      final date = now.subtract(Duration(days: i));
      final m = date.month.toString().padLeft(2, '0');
      final d = date.day.toString().padLeft(2, '0');
      final key = '${date.year}-$m-$d';
      if ((history[key] ?? 0) > 0) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  static Future<bool> hasStudiedToday() async {
    final history = await getDailyAnsweredHistory();
    return (history[_todayKey()] ?? 0) > 0;
  }

  // ---- Settings ----
  static const String _keyDailyGoal = 'daily_goal';
  static const String _keyNotifEnabled = 'notif_enabled';
  static const String _keyNotifHour = 'notif_hour';
  static const String _keyShowAnswerExplanation = 'show_answer_explanation';
  static const String _keyExplanationModeNoticeShown =
      'explanation_mode_notice_shown_v2';

  static Future<int> getDailyGoal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyDailyGoal) ?? 30;
  }

  static Future<void> setDailyGoal(int goal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDailyGoal, goal);
  }

  static Future<bool> getNotifEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyNotifEnabled) ?? true;
  }

  static Future<void> setNotifEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotifEnabled, enabled);
  }

  static Future<int> getNotifHour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyNotifHour) ?? 20;
  }

  static Future<void> setNotifHour(int hour) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyNotifHour, hour);
  }

  static Future<bool> getShowAnswerExplanation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyShowAnswerExplanation) ?? true;
  }

  static Future<void> setShowAnswerExplanation(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowAnswerExplanation, enabled);
  }

  static Future<bool> isExplanationModeNoticeShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyExplanationModeNoticeShown) ?? false;
  }

  static Future<void> markExplanationModeNoticeShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyExplanationModeNoticeShown, true);
  }

  // ---- Exam Date ----
  static const String _keyExamDate = 'exam_date';
  static const String _keyExamOnboardingDone = 'exam_onboarding_done';

  static Future<void> setExamDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyExamDate, date.toIso8601String());
  }

  static Future<DateTime?> getExamDate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyExamDate);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  static Future<void> clearExamDate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyExamDate);
  }

  static Future<bool> isExamOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyExamOnboardingDone) ?? false;
  }

  static Future<void> markExamOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyExamOnboardingDone, true);
  }
}
