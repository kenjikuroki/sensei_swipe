import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class MigrationHelper {
  static const String _migratedKey = 'migration_v1_completed';

  static Future<void> performMigration() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if migration has already been run
    if (prefs.getBool(_migratedKey) ?? false) {
      return;
    }
    
    debugPrint("MigrationHelper: Starting data migration...");

    // 1. Weak Questions (weak_questions remains the same, no action needed)
    
    // 2. Premium Status
    // Old key: 'is_premium_user'
    // New key: 'is_premium'
    final oldPremium = prefs.getBool('is_premium_user');
    if (oldPremium != null && oldPremium) {
      debugPrint("MigrationHelper: Migrated premium status.");
      await prefs.setBool('is_premium', true);
    }
    
    // 3. Quiz Completion Count
    // Old key: 'complete_quiz_count'
    // New key: 'quiz_completion_count'
    final oldQuizCount = prefs.getInt('complete_quiz_count');
    if (oldQuizCount != null) {
      debugPrint("MigrationHelper: Migrated quiz completion count.");
      await prefs.setInt('quiz_completion_count', oldQuizCount);
    }

    // 4. High Scores
    // Old: highscore_part1, highscore_part2...
    // New: highscore_貨物自動車運送事業法, highscore_道路運送車両法...
    final Map<String, String> categoryMap = {
      'part1': '貨物自動車運送事業法',
      'part2': '道路運送車両法',
      'part3': '道路交通法',
      'part4': '労働基準法',
      'part5': '実務上の知識及び能力',
    };

    for (final entry in categoryMap.entries) {
      final oldKey = 'highscore_${entry.key}'; // Old code had 'categoryKey' passed directly to prefs, wait!
      // Let's recheck the old code. 
      // Main.dart:
      // case 'part1': quizzes = QuizData.part1; highScoreKey = 'highscore_part1'; break;
      // then `PrefsHelper.saveHighScore(categoryKey, score)` uses precisely 'highscore_part1'.
      
      final oldScore = prefs.getInt(oldKey);
      if (oldScore != null && oldScore > 0) {
        final newKey = 'highscore_${entry.value}';
        debugPrint("MigrationHelper: Migrated highscore for ${entry.value} ($oldScore)");
        await prefs.setInt(newKey, oldScore);
      }
    }

    // Mark as migrated
    await prefs.setBool(_migratedKey, true);
    debugPrint("MigrationHelper: Data migration to V2 completed.");
  }
}
