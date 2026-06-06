import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';

import 'package:appinio_swiper/appinio_swiper.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'widgets/ad_banner.dart';
import 'utils/ad_manager.dart';
import 'utils/purchase_manager.dart';
import 'utils/prefs_helper.dart';
import 'utils/responsive_helper.dart';
import 'utils/notification_service.dart';
import 'widgets/special_offer_dialog.dart';
import 'widgets/premium_upgrade_dialog.dart';
import 'widgets/tutorial_overlay.dart';
import 'widgets/category_review_modal.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'theme/app_chrome.dart';

final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Lock orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Initialize Purchase Manager
  await PurchaseManager.instance.initialize();
  await NotificationService.initialize();

  runApp(const MyApp());
}

// -----------------------------------------------------------------------------
// 1. Data Models & Helpers
// -----------------------------------------------------------------------------

class Quiz {
  final String question;
  final bool isCorrect;
  final String explanation;
  final String? imagePath;

  Quiz({
    required this.question,
    required this.isCorrect,
    required this.explanation,
    this.imagePath,
  });

  factory Quiz.fromJson(Map<String, dynamic> json) {
    dynamic imagePathVal = json['imagePath'];
    String? finalImagePath;
    if (imagePathVal is List) {
      if (imagePathVal.isNotEmpty) {
        finalImagePath = imagePathVal.first as String?;
      }
    } else if (imagePathVal is String) {
      finalImagePath = imagePathVal;
    }

    return Quiz(
      question: (json['question'] as String).replaceAll('\n', ''),
      isCorrect: json['isCorrect'] as bool,
      explanation: json['explanation'] as String,
      imagePath: finalImagePath,
    );
  }
}

// PrefsHelper moved to lib/utils/prefs_helper.dart

class QuizData {
  static Map<String, List<Quiz>> _data = {};

  static Future<void> load() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/quiz_data.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      _data = {};
      jsonData.forEach((key, value) {
        if (value is List) {
          _data[key] = value.map((q) => Quiz.fromJson(q)).toList();
        }
      });
    } catch (e) {
      debugPrint("Error loading quiz data: $e");
      _data = {};
    }
  }

  static List<Quiz> get part1 => _data['part1'] ?? [];
  static List<Quiz> get part2 => _data['part2'] ?? [];
  static List<Quiz> get part3 => _data['part3'] ?? [];
  static List<Quiz> get part4 => _data['part4'] ?? [];


  static List<Quiz> getQuizzesFromTexts(List<String> texts) {
    final allQuizzes = [
      ...part1,
      ...part2,
      ...part3,
      ...part4,

    ];
    return allQuizzes.where((q) => texts.contains(q.question)).toList();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '潜水士 過去問',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F172A),
          primary: const Color(0xFF1E293B),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.backgroundTop,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
      home: const HomePage(),
      navigatorObservers: [routeObserver],
    );
  }
}

// -----------------------------------------------------------------------------
// 2. Home Page
// -----------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with RouteAware {
  int _weaknessCount = 0;
  int _bookmarkCount = 0;
  int _totalAnsweredCount = 0;
  int _consecutiveDaysStreak = 0;
  bool _notifEnabled = true;
  int _notifHour = 20;
  bool _isLoading = true;
  Map<String, int> _categoryWeaknessCounts = {};
  Map<String, int> _categoryBookmarkCounts = {};
  Map<String, int> _categoryHighScores = {};
  Map<String, int> _categoryAccuracyRates = {};
  Map<String, int> _categoryAnsweredCounts = {};
  final List<String> _categoryKeys = const ['part1', 'part2', 'part3', 'part4'];
  bool _isSequentialMode = false;
  DateTime? _examDate;
  int _dailyGoalTarget = 30;
  int _todayAnsweredCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadUserData();
  }
  
  Future<void> _initializeApp() async {
    // 1. Wait for 1 second
    await Future.delayed(const Duration(seconds: 1));

    // 2. Request ATT
    final status = await AppTrackingTransparency.requestTrackingAuthorization();
    debugPrint("ATT Status: $status");

    // 3. Initialize Ads
    await MobileAds.instance.initialize();
    
    // 4. Preload Ads
    AdManager.instance.preloadAd('home');

    await QuizData.load();
    await _loadUserData();
    if (mounted) {
      setState(() { _isLoading = false; });
      final onboardingDone = await PrefsHelper.isExamOnboardingDone();
      if (!onboardingDone && mounted) _showExamDateOnboarding();
    }
  }

  void _showExamDateOnboarding() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: false,
      builder: (_) => _ExamDateOnboardingSheet(
        onDone: (date) async {
          await PrefsHelper.markExamOnboardingDone();
          if (date != null) await PrefsHelper.setExamDate(date);
          if (mounted) _loadUserData();
        },
      ),
    );
  }
  
  Future<void> _loadUserData() async {
    final weakList = await PrefsHelper.getWeakQuestions();
    final bookmarkList = await PrefsHelper.getBookmarkedQuestions();
    final totalAnswered = await PrefsHelper.getAnsweredCount();
    final consecutiveDays = await PrefsHelper.getConsecutiveDaysStreak();
    final notifEnabled = await PrefsHelper.getNotifEnabled();
    final notifHour = await PrefsHelper.getNotifHour();
    final examDate = await PrefsHelper.getExamDate();
    final dailyGoal = await PrefsHelper.getDailyGoal();
    final dailyHistory = await PrefsHelper.getDailyAnsweredHistory();
    final todayKey = DateTime.now().toIso8601String().substring(0, 10);
    final todayCount = dailyHistory[todayKey] ?? 0;

    final weakCounts = <String, int>{};
    final bookmarkCounts = <String, int>{};
    final highScores = <String, int>{};
    final accuracyRates = <String, int>{};
    final answeredCounts = <String, int>{};

    for (final key in _categoryKeys) {
      final quizzes = _getQuizzesByKey(key);
      final qTexts = quizzes.map((q) => q.question).toSet();
      weakCounts[key] = weakList.where((t) => qTexts.contains(t)).length;
      bookmarkCounts[key] = bookmarkList.where((t) => qTexts.contains(t)).length;
      highScores[key] = await PrefsHelper.getHighScore('highscore_$key');
      final answered = await PrefsHelper.getCategoryAnsweredCount(key);
      final correct = await PrefsHelper.getCategoryCorrectCount(key);
      answeredCounts[key] = answered;
      accuracyRates[key] = answered > 0 ? ((correct / answered) * 100).round() : 0;
    }

    if (mounted) {
      setState(() {
        _weaknessCount = weakList.length;
        _bookmarkCount = bookmarkList.length;
        _totalAnsweredCount = totalAnswered;
        _consecutiveDaysStreak = consecutiveDays;
        _notifEnabled = notifEnabled;
        _notifHour = notifHour;
        _examDate = examDate;
        _dailyGoalTarget = dailyGoal;
        _todayAnsweredCount = todayCount;
        _categoryWeaknessCounts = weakCounts;
        _categoryBookmarkCounts = bookmarkCounts;
        _categoryHighScores = highScores;
        _categoryAccuracyRates = accuracyRates;
        _categoryAnsweredCounts = answeredCounts;
      });
    }
  }

  void _startQuiz(BuildContext context, List<Quiz> quizList, String categoryKey, {bool isRandom10 = true}) async {
    List<Quiz> questionsToUse = List<Quiz>.from(quizList);
    
    if (isRandom10) {
      questionsToUse.shuffle();
      if (questionsToUse.length > 10) {
        questionsToUse = questionsToUse.take(10).toList();
      }
    } else {
      // Sequential mode: keep order and use all
    }
    
    AdManager.instance.preloadAd('result');
    AdManager.instance.preloadAd('quiz');
    AdManager.instance.preloadInterstitial();
    
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QuizPage(
          quizzes: questionsToUse,
          categoryKey: categoryKey,
          totalQuestions: isRandom10 ? 10 : questionsToUse.length,
        ),
      ),
    );
    if (!mounted) return;
    _loadUserData();
  }

  void _startWeaknessReview(BuildContext context) async {
    final counts = await _getWeaknessCountsByCategory();
    
    if (!mounted) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => CategoryReviewModal(
        weaknessCounts: counts,
        onCategoryTap: (partKey) => _startWeaknessReviewByCategory(context, partKey),
      ),
    );
  }

  Future<Map<String, int>> _getWeaknessCountsByCategory() async {
    final weakTexts = await PrefsHelper.getWeakQuestions();
    Map<String, int> counts = {
      'part1': 0, 'part2': 0, 'part3': 0, 'part4': 0,
    };
    
    for (var text in weakTexts) {
      if (QuizData.part1.any((q) => q.question == text)) counts['part1'] = (counts['part1'] ?? 0) + 1;
      else if (QuizData.part2.any((q) => q.question == text)) counts['part2'] = (counts['part2'] ?? 0) + 1;
      else if (QuizData.part3.any((q) => q.question == text)) counts['part3'] = (counts['part3'] ?? 0) + 1;
      else if (QuizData.part4.any((q) => q.question == text)) counts['part4'] = (counts['part4'] ?? 0) + 1;
    }
    return counts;
  }

  void _startWeaknessReviewByCategory(BuildContext context, String partKey) async {
    final weakTexts = await PrefsHelper.getWeakQuestions();
    List<Quiz> allInCategory;
    switch(partKey) {
      case 'part1': allInCategory = QuizData.part1; break;
      case 'part2': allInCategory = QuizData.part2; break;
      case 'part3': allInCategory = QuizData.part3; break;
      case 'part4': allInCategory = QuizData.part4; break;
      default: allInCategory = [];
    }
    
    final weakQuizzes = allInCategory.where((q) => weakTexts.contains(q.question)).toList();
    if (weakQuizzes.isEmpty) return;

    AdManager.instance.preloadAd('result');
    AdManager.instance.preloadAd('quiz');
    AdManager.instance.preloadInterstitial();

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QuizPage(
          quizzes: weakQuizzes,
          isWeaknessReview: true,
          totalQuestions: weakQuizzes.length,
        ),
      ),
    );
    if (!mounted) return;
    _loadUserData();
  }

  void _startQuizByCategory(BuildContext context, String partKey) {
    final quizzes = _getQuizzesByKey(partKey);
    if (quizzes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('問題データがまだありません')),
      );
      return;
    }
    _startQuiz(context, quizzes, partKey, isRandom10: !_isSequentialMode);
  }

  void _startBookmarkReview(BuildContext context) async {
    final navigator = Navigator.of(context);
    final bookmarkTexts = await PrefsHelper.getBookmarkedQuestions();
    if (!mounted) return;
    if (bookmarkTexts.isEmpty) return;

    final bookmarkQuizzes = QuizData.getQuizzesFromTexts(bookmarkTexts);

    AdManager.instance.preloadAd('result');
    AdManager.instance.preloadAd('quiz');
    AdManager.instance.preloadInterstitial();

    await navigator.push(
      MaterialPageRoute(
        builder: (context) => QuizPage(
          quizzes: bookmarkQuizzes,
          isWeaknessReview: false,
          isBookmarkReview: true,
          totalQuestions: bookmarkQuizzes.length,
        ),
      ),
    );
    if (!mounted) return;
    _loadUserData();
  }

  void _startBookmarkReviewByCategory(BuildContext context, String categoryKey) async {
    final navigator = Navigator.of(context);
    final allBookmarks = await PrefsHelper.getBookmarkedQuestions();
    if (!mounted) return;
    final quizzes = _getQuizzesByKey(categoryKey);
    final qTexts = quizzes.map((q) => q.question).toSet();
    final filtered = allBookmarks.where((t) => qTexts.contains(t)).toList();
    if (filtered.isEmpty) return;

    final bookmarkQuizzes = QuizData.getQuizzesFromTexts(filtered);
    AdManager.instance.preloadAd('result');
    AdManager.instance.preloadAd('quiz');
    AdManager.instance.preloadInterstitial();

    await navigator.push(
      MaterialPageRoute(
        builder: (context) => QuizPage(
          quizzes: bookmarkQuizzes,
          isWeaknessReview: false,
          isBookmarkReview: true,
          totalQuestions: bookmarkQuizzes.length,
        ),
      ),
    );
    if (!mounted) return;
    _loadUserData();
  }

  List<Quiz> _getQuizzesByKey(String key) {
    switch (key) {
      case 'part1': return QuizData.part1;
      case 'part2': return QuizData.part2;
      case 'part3': return QuizData.part3;
      case 'part4': return QuizData.part4;
      default: return [];
    }
  }

  String _getCategoryName(String key) {
    switch (key) {
      case 'part1': return '潜水業務';
      case 'part2': return '送気、潜降及び浮上';
      case 'part3': return '高気圧障害';
      case 'part4': return '関係法令';
      default: return key;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isCompact = !ResponsiveHelper.isTablet(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        centerTitle: false,
        title: const Text("潜水士試験対策"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: '設定',
            color: Colors.white.withValues(alpha: 0.8),
            onPressed: _showSettingsSheet,
          ),
        ],
      ),
      body: AppBackground(
        child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, isCompact ? 16 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _buildExamDateBanner()),
                        const SizedBox(width: 8),
                        Expanded(child: _buildDailyGoal()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildTopSelectors(),
                  const SizedBox(height: 12),

                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: _categoryKeys.length,
                    itemBuilder: (ctx, idx) {
                      final key = _categoryKeys[idx];
                      final quizzes = _getQuizzesByKey(key);
                      return _CategoryListItem(
                        index: idx,
                        title: _getCategoryName(key),
                        questionCount: quizzes.length,
                        onTap: () => _startQuizByCategory(context, key),
                        onInfo: () => _showCategoryInfoSheet(context, key),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildBottomHomeActions(context, compact: isCompact),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<bool>(
                    valueListenable: PurchaseManager.instance.isPremium,
                    builder: (context, isPremium, _) {
                      if (isPremium) return const SizedBox.shrink();
                      return const Column(children: [_SisterAppPromotion(), SizedBox(height: 8)]);
                    },
                  ),
                  _buildPremiumBanner(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildBottomHomeActions(BuildContext context, {bool compact = true}) {
    final weaknessStyle = ElevatedButton.styleFrom(
      backgroundColor: Colors.white.withValues(alpha: 0.92),
      foregroundColor: AppColors.ink,
      elevation: 2,
      shadowColor: const Color(0xFF21314D).withValues(alpha: 0.05),
      side: BorderSide(color: AppColors.line.withValues(alpha: 0.9)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 14),
    );
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: double.infinity,
          maxWidth: ResponsiveHelper.respCardWidth(context) ?? double.infinity,
        ),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: compact ? 44 : 48,
                child: ElevatedButton.icon(
                  onPressed: _weaknessCount > 0 ? () => _startWeaknessReview(context) : null,
                  icon: const Icon(Icons.history_edu_rounded, color: Color(0xFFCC6A43)),
                  label: Text('要復習 $_weaknessCount', style: const TextStyle(fontWeight: FontWeight.w800)),
                  style: weaknessStyle,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: PurchaseManager.instance.isPremium,
                builder: (context, isPremium, child) {
                  return SizedBox(
                    height: compact ? 44 : 48,
                    child: ElevatedButton.icon(
                      onPressed: _bookmarkCount > 0
                          ? () {
                              if (!isPremium) { _showPremiumDialog(); return; }
                              _startBookmarkReview(context);
                            }
                          : null,
                      icon: Icon(
                        isPremium ? Icons.bookmark_rounded : Icons.lock_rounded,
                        color: const Color(0xFF5D729D),
                      ),
                      label: Text('ブックマーク $_bookmarkCount', style: const TextStyle(fontWeight: FontWeight.w800)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF3F6FB),
                        foregroundColor: AppColors.accent,
                        elevation: 2,
                        shadowColor: const Color(0xFF21314D).withValues(alpha: 0.05),
                        side: BorderSide(color: AppColors.line.withValues(alpha: 0.9)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumBanner() {
    return ValueListenableBuilder<bool>(
      valueListenable: PurchaseManager.instance.isPremium,
      builder: (context, isPremium, _) {
        if (isPremium) return const SizedBox.shrink();
        return GestureDetector(
          onTap: _showPremiumDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2C4A7C), Color(0xFF4F6FA9)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2C4A7C).withValues(alpha: 0.22),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFFFFD700),
                  size: 26,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'プレミアムにアップグレード',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '広告なし・連続モード・ブックマーク機能解放',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white60,
                  size: 22,
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  void _showPremiumDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const PremiumUpgradeDialog(),
    );
  }

  Future<void> _showSettingsSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SettingsSheet(
        dailyGoal: _dailyGoalTarget,
        notifEnabled: _notifEnabled,
        notifHour: _notifHour,
        examDate: _examDate,
        streak: _consecutiveDaysStreak,
        onChanged: ({int? goal, bool? notifEnabled, int? notifHour}) async {
          if (goal != null) await PrefsHelper.setDailyGoal(goal);
          if (notifEnabled != null) await PrefsHelper.setNotifEnabled(notifEnabled);
          if (notifHour != null) await PrefsHelper.setNotifHour(notifHour);
          final enabled = notifEnabled ?? _notifEnabled;
          final hour = notifHour ?? _notifHour;
          await NotificationService.scheduleDailyReminder(
            examDate: _examDate,
            streak: _consecutiveDaysStreak,
            enabled: enabled,
            hour: hour,
          );
          if (mounted) _loadUserData();
        },
        onExamDateChanged: (date) async {
          if (date != null) {
            await PrefsHelper.setExamDate(date);
          } else {
            await PrefsHelper.clearExamDate();
          }
          await NotificationService.scheduleDailyReminder(
            examDate: date,
            streak: _consecutiveDaysStreak,
            enabled: _notifEnabled,
            hour: _notifHour,
          );
          if (mounted) _loadUserData();
        },
      ),
    );
  }

  void _showCategoryInfoSheet(BuildContext context, String categoryKey) {
    final quizzes = _getQuizzesByKey(categoryKey);
    final questionCount = quizzes.length;
    final accuracyRate = _categoryAccuracyRates[categoryKey] ?? 0;
    final answeredCount = _categoryAnsweredCounts[categoryKey] ?? 0;
    final highScore = _categoryHighScores[categoryKey] ?? 0;
    final weaknessCount = _categoryWeaknessCounts[categoryKey] ?? 0;
    final bookmarkCount = _categoryBookmarkCounts[categoryKey] ?? 0;
    final completionRate = questionCount == 0
        ? 0.0
        : (math.min(answeredCount, questionCount) / questionCount).clamp(0.0, 1.0);
    final completionPercent = (completionRate * 100).round();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            gradient: LinearGradient(
              colors: [AppColors.backgroundTop, AppColors.backgroundBottom],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.line,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _getCategoryName(categoryKey),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 16),
                SoftSurface(
                  borderRadius: BorderRadius.circular(22),
                  borderColor: AppColors.line.withValues(alpha: 0.84),
                  fillColor: Colors.white.withValues(alpha: 0.95),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Column(
                      children: [
                        _InfoSheetRow(
                          label: '問題数',
                          value: '$questionCount問',
                          icon: Icons.quiz_rounded,
                          color: AppColors.accent,
                        ),
                        const SizedBox(height: 12),
                        _InfoSheetRow(
                          label: '正答率',
                          value: answeredCount > 0 ? '$accuracyRate%' : '未回答',
                          icon: Icons.percent_rounded,
                          color: accuracyRate >= 70
                              ? const Color(0xFF4CAF50)
                              : accuracyRate > 0
                                  ? const Color(0xFFFF9D0A)
                                  : AppColors.inkMuted,
                        ),
                        const SizedBox(height: 12),
                        _InfoSheetRow(
                          label: '回答数',
                          value: '$answeredCount問',
                          icon: Icons.bar_chart_rounded,
                          color: AppColors.accent,
                        ),
                        const SizedBox(height: 12),
                        _InfoSheetRow(
                          label: '最高スコア',
                          value: highScore > 0 ? '$highScore点' : '--',
                          icon: Icons.emoji_events_rounded,
                          color: const Color(0xFFE08800),
                        ),
                        const SizedBox(height: 12),
                        _InfoSheetRow(
                          label: '要復習',
                          value: weaknessCount > 0 ? '$weaknessCount問' : 'なし',
                          icon: Icons.history_edu_rounded,
                          color: weaknessCount > 0
                              ? const Color(0xFFCC6A43)
                              : const Color(0xFF4CAF50),
                        ),
                        const SizedBox(height: 12),
                        _InfoSheetRow(
                          label: 'ブックマーク',
                          value: bookmarkCount > 0 ? '$bookmarkCount問' : 'なし',
                          icon: Icons.bookmark_outline_rounded,
                          color: bookmarkCount > 0
                              ? Colors.blueAccent
                              : AppColors.inkMuted,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Text(
                              '進捗',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.inkMuted,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              answeredCount == 0
                                  ? '未着手'
                                  : completionRate >= 1.0
                                      ? '完了'
                                      : '$completionPercent%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: completionRate >= 1.0
                                    ? const Color(0xFF4CAF50)
                                    : AppColors.accent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: completionRate,
                            minHeight: 8,
                            backgroundColor: AppColors.line.withValues(alpha: 0.4),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              completionRate >= 1.0
                                  ? const Color(0xFF4CAF50)
                                  : AppColors.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: weaknessCount > 0
                            ? () {
                                Navigator.of(context).pop();
                                _startWeaknessReviewByCategory(context, categoryKey);
                              }
                            : null,
                        icon: const Icon(Icons.history_edu_rounded, size: 16),
                        label: Text('要復習 ($weaknessCount問)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFCC6A43),
                          side: const BorderSide(color: Color(0xFFCC6A43)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: bookmarkCount > 0
                            ? () {
                                Navigator.of(context).pop();
                                _startBookmarkReviewByCategory(context, categoryKey);
                              }
                            : null,
                        icon: const Icon(Icons.bookmark_outline, size: 16),
                        label: Text('ブックマーク ($bookmarkCount問)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blueAccent,
                          side: const BorderSide(color: Colors.blueAccent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildExamDateBanner() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final examDay = _examDate == null ? null : DateTime(_examDate!.year, _examDate!.month, _examDate!.day);
    final daysLeft = examDay == null ? null : examDay.difference(today).inDays;

    Color bannerColor;
    String label;
    if (daysLeft == null) {
      bannerColor = AppColors.accentSoft;
      label = '試験日未設定';
    } else if (daysLeft < 0) {
      bannerColor = AppColors.surfaceMuted;
      label = '試験日が過ぎました';
    } else if (daysLeft == 0) {
      bannerColor = AppColors.error.withValues(alpha: 0.12);
      label = '今日が試験日！';
    } else if (daysLeft <= 7) {
      bannerColor = AppColors.warning.withValues(alpha: 0.13);
      label = 'あと $daysLeft 日';
    } else if (daysLeft <= 30) {
      bannerColor = const Color(0xFFFFF8E1);
      label = 'あと $daysLeft 日';
    } else {
      bannerColor = AppColors.accentSoft;
      label = 'あと $daysLeft 日';
    }

    return GestureDetector(
      onTap: _showSettingsSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bannerColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line.withValues(alpha: 0.7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '試験日',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkMuted),
            ),
            const SizedBox(height: 2),
            Text(
              daysLeft == null
                  ? '--'
                  : _examDate!.month == now.month
                      ? '${_examDate!.month}/${_examDate!.day}'
                      : '${_examDate!.year}/${_examDate!.month}/${_examDate!.day}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.ink),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyGoal() {
    final progress = (_dailyGoalTarget > 0 ? (_todayAnsweredCount / _dailyGoalTarget).clamp(0.0, 1.0) : 0.0);
    final achieved = _todayAnsweredCount >= _dailyGoalTarget;

    return GestureDetector(
      onTap: _showSettingsSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: achieved ? AppColors.success.withValues(alpha: 0.10) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line.withValues(alpha: 0.7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '今日の目標',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkMuted),
            ),
            const SizedBox(height: 2),
            Text(
              '$_todayAnsweredCount / $_dailyGoalTarget問',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: achieved ? AppColors.success : AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: AppColors.line.withValues(alpha: 0.4),
                valueColor: AlwaysStoppedAnimation<Color>(
                  achieved ? AppColors.success : AppColors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSelectors() {
    return Align(
      alignment: Alignment.centerLeft,
      child: ValueListenableBuilder<bool>(
        valueListenable: PurchaseManager.instance.isPremium,
        builder: (context, isPremium, _) {
          return Container(
            width: 90,
            height: 34,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: AppColors.line.withValues(alpha: 0.7)),
              boxShadow: AppChrome.softShadow,
            ),
            child: Row(
              children: [
                _buildModeTab(
                  icon: Icons.shuffle_rounded,
                  isSelected: !_isSequentialMode,
                  isLocked: false,
                  isFirst: true,
                  onTap: () => setState(() => _isSequentialMode = false),
                ),
                _buildModeTab(
                  icon: Icons.format_list_numbered_rounded,
                  isSelected: _isSequentialMode,
                  isLocked: !isPremium,
                  isFirst: false,
                  onTap: () {
                    if (!isPremium) { _showPremiumDialog(); return; }
                    setState(() => _isSequentialMode = true);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildModeTab({
    required IconData icon,
    required bool isSelected,
    required bool isLocked,
    required bool isFirst,
    required VoidCallback onTap,
  }) {
    final outerRadius = const Radius.circular(17);
    const innerRadius = Radius.zero;
    final borderRadius = isFirst
        ? BorderRadius.only(topLeft: outerRadius, bottomLeft: outerRadius, topRight: innerRadius, bottomRight: innerRadius)
        : BorderRadius.only(topRight: outerRadius, bottomRight: outerRadius, topLeft: innerRadius, bottomLeft: innerRadius);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: double.infinity,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accent : Colors.transparent,
            borderRadius: borderRadius,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 18, color: isSelected ? Colors.white : AppColors.inkMuted),
              if (isLocked)
                Positioned(
                  right: 6,
                  bottom: 5,
                  child: Icon(Icons.lock_rounded, size: 9, color: isSelected ? Colors.white54 : AppColors.inkMuted),
                ),
            ],
          ),
        ),     ),
    );
  }

}

// ---------------------------------------------------------------------------
// Category list item (縦並びリスト用)
// ---------------------------------------------------------------------------

class _CategoryListItem extends StatelessWidget {
  static const _colors = [
    Color(0xFF4F6FA9),
    Color(0xFF4CAF50),
    Color(0xFFFF9D0A),
    Color(0xFFCC6A43),
    Color(0xFF9C27B0),
    Color(0xFF00BCD4),
    Color(0xFFE91E63),
    Color(0xFF607D8B),
  ];

  final int index;
  final String title;
  final int questionCount;
  final VoidCallback onTap;
  final VoidCallback onInfo;

  const _CategoryListItem({
    required this.index,
    required this.title,
    required this.questionCount,
    required this.onTap,
    required this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colors[index % _colors.length];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line.withValues(alpha: 0.75)),
          boxShadow: AppChrome.softShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.menu_book_rounded, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$questionCount問',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onInfo,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: AppColors.inkMuted.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoSheetRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _InfoSheetRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.inkSoft,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _MenuButton({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: iconColor, size: 26),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.blueGrey[300], size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}




// -----------------------------------------------------------------------------
// 3. Quiz Page
// -----------------------------------------------------------------------------

class QuizPage extends StatefulWidget {
  final List<Quiz> quizzes;
  final String? categoryKey;
  final bool isWeaknessReview;
  final bool isBookmarkReview;
  final int totalQuestions;

  const QuizPage({
    super.key,
    required this.quizzes,
    this.categoryKey,
    this.isWeaknessReview = false,
    this.isBookmarkReview = false,
    required this.totalQuestions,
  });

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  final AppinioSwiperController controller = AppinioSwiperController();

  int _score = 0;
  int _currentIndex = 1;
  int _currentCorrectStreak = 0;
  int _bestCorrectStreak = 0;
  bool _showTutorial = false;
  final List<Quiz> _incorrectQuizzes = [];
  final List<Quiz> _correctQuizzesInReview = [];
  final List<Map<String, dynamic>> _answerHistory = [];
  Color _backgroundColor = const Color(0xFFF1F5F9);

  @override
  void initState() {
    super.initState();
    _checkTutorial();
  }

  Future<void> _checkTutorial() async {
    final shown = await PrefsHelper.isTutorialShown();
    if (!shown && mounted) {
      setState(() => _showTutorial = true);
    }
  }

  Future<void> _dismissTutorial() async {
    await PrefsHelper.markTutorialShown();
    if (mounted) setState(() => _showTutorial = false);
  }

  void _handleSwipeEnd(int previousIndex, int targetIndex, SwiperActivity activity) {
    if (activity is Swipe) {
      final quiz = widget.quizzes[previousIndex];
      bool userVal = (activity.direction == AxisDirection.right);
      bool isCorrect = (userVal == quiz.isCorrect);

      _answerHistory.add({
        'quiz': quiz,
        'result': isCorrect,
      });

      setState(() {
        if (isCorrect) {
          _score++;
          _currentCorrectStreak++;
          if (_currentCorrectStreak > _bestCorrectStreak) {
            _bestCorrectStreak = _currentCorrectStreak;
          }
          _backgroundColor = Colors.green.withValues(alpha: 0.2);
          HapticFeedback.lightImpact();

          if (widget.isWeaknessReview) {
            _correctQuizzesInReview.add(quiz);
          }
        } else {
          _currentCorrectStreak = 0;
          _backgroundColor = Colors.red.withValues(alpha: 0.2);
          _incorrectQuizzes.add(quiz);
          HapticFeedback.heavyImpact();
        }
      });

      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          setState(() {
            _backgroundColor = const Color(0xFFF1F5F9);
          });
        }
      });

      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 600),
          content: Text(
            isCorrect ? "正解！ ⭕" : "不正解... ❌",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          backgroundColor: isCorrect ? Colors.green : Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height * 0.5,
            left: 50,
            right: 50,
          ),
        ),
      );

      setState(() {
        if (_currentIndex < widget.totalQuestions) {
          _currentIndex++;
        }
      });

      if (previousIndex == widget.quizzes.length - 1) {
        _finishQuiz();
      }
    }
  }

  Future<void> _finishQuiz() async {
    final total = widget.quizzes.length;

    if (widget.categoryKey != null) {
      await PrefsHelper.saveHighScore('highscore_${widget.categoryKey!}', _score);
      await PrefsHelper.addCategoryAnsweredCount(widget.categoryKey!, total);
      await PrefsHelper.addCategoryCorrectCount(widget.categoryKey!, _score);
    }
    await PrefsHelper.addAnsweredCount(total);
    await PrefsHelper.addDailyAnsweredCount(total);
    await PrefsHelper.saveBestStreak(_bestCorrectStreak);
    await PrefsHelper.saveDailyBestStreak(_bestCorrectStreak);

    if (_incorrectQuizzes.isNotEmpty) {
      final incorrectTexts = _incorrectQuizzes.map((q) => q.question).toList();
      await PrefsHelper.addWeakQuestions(incorrectTexts);
    }

    if (widget.isWeaknessReview && _correctQuizzesInReview.isNotEmpty) {
      final correctTexts = _correctQuizzesInReview.map((q) => q.question).toList();
      await PrefsHelper.removeWeakQuestions(correctTexts);
    }

    await PrefsHelper.incrementQuizCompletionCount();

    if (mounted) {
      final shouldShow = await PrefsHelper.shouldShowInterstitial();
      
      if (shouldShow) {
        AdManager.instance.showInterstitial(
          onComplete: () async {
            if (mounted) {
              // After interstitial, check for special offer
              final showOffer = await PurchaseManager.instance.shouldShowSpecialOffer();
              if (showOffer && mounted) {
                await PurchaseManager.instance.markSpecialOfferAsShown();
                if (!mounted) return;
                await showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const SpecialOfferDialog(),
                );
              }
              if (mounted) {
                _navigateToResult();
              }
            }
          },
        );
      } else {
        _navigateToResult();
      }
    }
  }

  void _navigateToResult() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => ResultPage(
          score: _score,
          total: widget.quizzes.length,
          history: _answerHistory,
          incorrectQuizzes: _incorrectQuizzes,
          originalQuizzes: widget.quizzes,
          categoryKey: widget.categoryKey,
          isWeaknessReview: widget.isWeaknessReview,
          isBookmarkReview: widget.isBookmarkReview,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quizBody = Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black54),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        color: _backgroundColor,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "第$_currentIndex問",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          "$_currentIndex / ${widget.totalQuestions}",
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _currentIndex / widget.totalQuestions,
                        minHeight: 8,
                        backgroundColor: Colors.grey[300],
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AppinioSwiper(
                  controller: controller,
                  cardCount: widget.quizzes.length,
                  loop: false,
                  backgroundCardCount: 2,
                  swipeOptions: const SwipeOptions.symmetric(horizontal: true, vertical: false),
                  onSwipeEnd: _handleSwipeEnd,
                  cardBuilder: (context, index) {
                    return _buildCard(widget.quizzes[index]);
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.only(bottom: 40, top: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        controller.unswipe();
                        setState(() {
                          if (_currentIndex > 1) {
                            _currentIndex--;
                          }
                          if (_answerHistory.isNotEmpty) {
                            final last = _answerHistory.removeLast();
                            final bool wasCorrect = last['result'];
                            final Quiz quiz = last['quiz'];
                            
                            if (wasCorrect) {
                              _score--;
                              if (widget.isWeaknessReview) {
                                _correctQuizzesInReview.remove(quiz);
                              }
                            } else {
                              _incorrectQuizzes.remove(quiz);
                            }
                          }
                        });
                      },
                      icon: const Icon(Icons.undo),
                      label: const Text("元に戻す"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        elevation: 2,
                      ),
                    ),
                  ],
                ),
              ),
              // Ad Banner for Quiz
              SafeArea(
                top: false,
                child: ValueListenableBuilder<bool>(
                  valueListenable: PurchaseManager.instance.isPremium,
                  builder: (context, isPremium, child) {
                    if (isPremium) return const SizedBox.shrink();
                    return const SizedBox(
                      height: 60,
                      child: AdBanner(adKey: 'quiz', keepAlive: true),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (_showTutorial) {
      return Stack(
        children: [
          quizBody,
          TutorialOverlay(onDismiss: _dismissTutorial),
        ],
      );
    }
    return quizBody;
  }

  Widget _buildCard(Quiz quiz) {
    bool hasImage = quiz.imagePath != null;

    return SizedBox.expand(
      child: Container(
      margin: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Column(
        children: [
          if (hasImage) 
            Expanded(
              flex: 4,
              child: Container(
                width: double.infinity,
                color: Colors.grey[200],
                child: Image.asset(
                  quiz.imagePath!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.image_not_supported, size: 50, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text("Image not found", style: TextStyle(color: Colors.grey[600])),
                      ],
                    );
                  },
                ),
              ),
            ),

          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Q.",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: AutoSizeText(
                      quiz.question,
                      style: TextStyle(
                        fontSize: hasImage ? 18 : 22,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.left,
                      minFontSize: 12,
                      stepGranularity: 1,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.only(left: 40.0, right: 40.0, bottom: 40.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => controller.swipeLeft(),
                  child: const Column(
                    children: [
                      Icon(Icons.close, color: Colors.redAccent, size: 48),
                      Text("誤り", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => controller.swipeRight(),
                  child: const Column(
                    children: [
                      Icon(Icons.circle_outlined, color: Colors.green, size: 48),
                      Text("正しい", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (hasImage) const SizedBox(height: 10),
        ],
      ),
    );
  }

}

class _SisterAppPromotion extends StatelessWidget {
  const _SisterAppPromotion();

  static const _url = 'https://apps.apple.com/jp/app/id6768983288';

  Future<void> _launchURL(BuildContext context) async {
    final Uri url = Uri.parse(_url);
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset('assets/sakusaku_icon.png', width: 80, height: 80, fit: BoxFit.cover),
                ),
                const SizedBox(height: 16),
                const Text(
                  'サクサク過去問',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                const Text(
                  '公式例題ベースのスワイプ問題集アプリです。\nApp Storeで詳細を確認できます。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          if (!await launchUrl(url)) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('URLを開けませんでした')),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: const Text('開く', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: () => _launchURL(context),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset('assets/sakusaku_icon.png', width: 32, height: 32, fit: BoxFit.cover),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'サクサク過去問',
                      style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '公式例題ベースの問題集が新登場',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, height: 1.2),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.launch, color: Colors.grey, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 4. Result Page
// -----------------------------------------------------------------------------

class ResultPage extends StatefulWidget {
  final int score;
  final int total;
  final List<Map<String, dynamic>> history;
  final List<Quiz> incorrectQuizzes;
  final List<Quiz> originalQuizzes;
  final String? categoryKey;
  final bool isWeaknessReview;
  final bool isBookmarkReview;

  const ResultPage({
    super.key,
    required this.score,
    required this.total,
    required this.history,
    required this.incorrectQuizzes,
    required this.originalQuizzes,
    this.categoryKey,
    required this.isWeaknessReview,
    this.isBookmarkReview = false,
  });

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  Set<String> _bookmarkedQuestions = {};

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    final list = await PrefsHelper.getBookmarkedQuestions();
    if (mounted) setState(() => _bookmarkedQuestions = Set.from(list));
  }

  Future<void> _toggleBookmark(Quiz quiz) async {
    final q = quiz.question;
    if (_bookmarkedQuestions.contains(q)) {
      await PrefsHelper.removeBookmarkedQuestions([q]);
      if (mounted) setState(() => _bookmarkedQuestions.remove(q));
    } else {
      await PrefsHelper.addBookmarkedQuestions([q]);
      if (mounted) setState(() => _bookmarkedQuestions.add(q));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Column(
          children: [
            // -----------------------------------------------------------------
            // 1. 上部エリア
            // -----------------------------------------------------------------
            const AdBanner(adKey: 'result'), // 一番上に広告バナー

            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 24 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(32), // 角丸32px
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 5))
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "正解数",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      const SizedBox(width: 8),
                      TweenAnimationBuilder<int>(
                        tween: IntTween(begin: 0, end: widget.score),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeOut,
                        builder: (context, value, _) => Text(
                          "$value/${widget.total}",
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (widget.score == widget.total)
                    const Text(
                      "PERFECT! 🎉",
                      style: TextStyle(fontSize: 20, color: Colors.green, fontWeight: FontWeight.bold),
                    )
                  else
                    Text(
                      widget.score / widget.total >= 0.8 ? "合格圏内！素晴らしい！" : widget.score / widget.total >= 0.5 ? "もう少し！頑張ろう！" : "まだまだ復習が必要！",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: widget.score / widget.total >= 0.8 ? Colors.green : Colors.red,
                      ),
                    ),
                ],
              ),
            ),
            ),

            // -----------------------------------------------------------------
            // 2. 中央エリア（スクロール可能なリスト）
            // -----------------------------------------------------------------
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.history.length,
                itemBuilder: (context, index) {
                  final item = widget.history[index];
                  final Quiz quiz = item['quiz'];
                  final bool isCorrect = item['result'];
                  final isBookmarked = _bookmarkedQuestions.contains(quiz.question);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                isCorrect ? Icons.check_circle : Icons.cancel,
                                color: isCorrect ? Colors.green : Colors.red,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      quiz.question,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    if (quiz.imagePath != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4.0),
                                        child: Row(
                                          children: [
                                            Icon(Icons.image, size: 16, color: Colors.grey[500]),
                                            const SizedBox(width: 4),
                                            Text("画像問題", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  isBookmarked ? Icons.bookmark : Icons.bookmark_outline,
                                  color: isBookmarked ? Colors.blueAccent : Colors.grey,
                                  size: 22,
                                ),
                                onPressed: () => _toggleBookmark(quiz),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "💡 ${quiz.explanation}",
                              style: TextStyle(color: Colors.blueGrey[700], fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // -----------------------------------------------------------------
            // 3. 下部エリア（固定フッター）
            // -----------------------------------------------------------------
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFFF9F9F9),
              child: Column(
                children: [
                  Row(
                    children: [
                      // 左ボタン: 「ミスを確認」 (全問正解時は非表示)
                      if (widget.incorrectQuizzes.isNotEmpty) ...[
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (context) => QuizPage(
                                      quizzes: widget.incorrectQuizzes,
                                      isWeaknessReview: true,
                                      totalQuestions: widget.incorrectQuizzes.length,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text("ミスを確認"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],

                      // 右ボタン: 「リトライ」 or 「ホームに戻る」
                      Expanded(
                        child: SizedBox(
                          height: 56,
                          child: ElevatedButton(
                            onPressed: () {
                              if (widget.isWeaknessReview || widget.isBookmarkReview) {
                                Navigator.of(context).popUntil((route) => route.isFirst);
                                return;
                              }

                              final shuffledAgain = List<Quiz>.from(widget.originalQuizzes)..shuffle();
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (context) => QuizPage(
                                    quizzes: shuffledAgain,
                                    categoryKey: widget.categoryKey,
                                    totalQuestions: shuffledAgain.length,
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.blueAccent,
                              elevation: 0,
                              side: const BorderSide(color: Colors.blueAccent, width: 2),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            child: Text((widget.isWeaknessReview || widget.isBookmarkReview) ? "ホームに戻る" : "リトライ"),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ホームに戻るリンク
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    child: const Text("ホームに戻る", style: TextStyle(color: Colors.grey)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Settings Sheet ──────────────────────────────────────────────────────────

class _SettingsSheet extends StatefulWidget {
  final int dailyGoal;
  final bool notifEnabled;
  final int notifHour;
  final DateTime? examDate;
  final int streak;
  final void Function({int? goal, bool? notifEnabled, int? notifHour}) onChanged;
  final void Function(DateTime?) onExamDateChanged;

  const _SettingsSheet({
    required this.dailyGoal,
    required this.notifEnabled,
    required this.notifHour,
    required this.examDate,
    required this.streak,
    required this.onChanged,
    required this.onExamDateChanged,
  });

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late bool _notifEnabled;
  late int _notifHour;
  late int _dailyGoal;
  DateTime? _examDate;

  static const _goalOptions = [10, 20, 30, 50, 70, 100];

  @override
  void initState() {
    super.initState();
    _notifEnabled = widget.notifEnabled;
    _notifHour = widget.notifHour;
    _dailyGoal = widget.dailyGoal;
    _examDate = widget.examDate;
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _notifHour, minute: 0),
      helpText: '通知時間を選択',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _notifHour = picked.hour);
    widget.onChanged(notifHour: picked.hour);
  }

  Future<void> _pickExamDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _examDate ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
      helpText: '試験日を選択',
    );
    if (picked == null) return;
    setState(() => _examDate = picked);
    widget.onExamDateChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        gradient: LinearGradient(
          colors: [AppColors.backgroundTop, AppColors.backgroundBottom],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 32),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44, height: 5,
                  decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(999)),
                ),
              ),
              const SizedBox(height: 20),
              const Text('設定', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.ink)),
              const SizedBox(height: 24),

              // ── 試験日 ──
              const Text('試験日', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.inkMuted)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickExamDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded, color: AppColors.inkMuted, size: 20),
                            const SizedBox(width: 12),
                            Text(
                              _examDate == null
                                  ? '未設定'
                                  : '${_examDate!.year}/${_examDate!.month.toString().padLeft(2,'0')}/${_examDate!.day.toString().padLeft(2,'0')}',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
                            ),
                            const Spacer(),
                            const Icon(Icons.chevron_right, color: AppColors.inkMuted),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_examDate != null) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        setState(() => _examDate = null);
                        widget.onExamDateChanged(null);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: const Icon(Icons.close_rounded, color: AppColors.inkMuted, size: 20),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),

              // ── 1日の目標 ──
              const Text('1日の目標', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.inkMuted)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _goalOptions.map((g) {
                  final selected = g == _dailyGoal;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _dailyGoal = g);
                      widget.onChanged(goal: g);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.accent : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: selected ? AppColors.accent : AppColors.line),
                      ),
                      child: Text(
                        '$g問',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : AppColors.ink,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // ── 通知 ──
              const Text('リマインド通知', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.inkMuted)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_outlined, color: AppColors.inkMuted),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('毎日の学習リマインド',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
                    ),
                    Switch.adaptive(
                      value: _notifEnabled,
                      activeColor: AppColors.accent,
                      onChanged: (v) {
                        setState(() => _notifEnabled = v);
                        widget.onChanged(notifEnabled: v);
                      },
                    ),
                  ],
                ),
              ),
              if (_notifEnabled) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _pickTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time_rounded, color: AppColors.inkMuted),
                        const SizedBox(width: 12),
                        Text(
                          '${_notifHour.toString().padLeft(2, '0')}:00',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
                        ),
                        const Spacer(),
                        const Icon(Icons.chevron_right, color: AppColors.inkMuted),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Exam Date Onboarding Sheet ───────────────────────────────────────────────

class _ExamDateOnboardingSheet extends StatefulWidget {
  final void Function(DateTime?) onDone;
  const _ExamDateOnboardingSheet({required this.onDone});

  @override
  State<_ExamDateOnboardingSheet> createState() => _ExamDateOnboardingSheetState();
}

class _ExamDateOnboardingSheetState extends State<_ExamDateOnboardingSheet> {
  DateTime? _examDate;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
      helpText: '試験日を選択',
    );
    if (picked != null) setState(() => _examDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        gradient: LinearGradient(
          colors: [AppColors.backgroundTop, AppColors.backgroundBottom],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 32),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44, height: 5,
                decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(999)),
              ),
            ),
            const SizedBox(height: 24),
            const Text('試験日を登録しよう', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.ink)),
            const SizedBox(height: 8),
            const Text(
              '試験日を設定すると、残り日数を毎日確認できます。',
              style: TextStyle(fontSize: 14, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, color: AppColors.inkMuted),
                    const SizedBox(width: 12),
                    Text(
                      _examDate == null
                          ? '試験日を選択する'
                          : '${_examDate!.year}/${_examDate!.month.toString().padLeft(2,'0')}/${_examDate!.day.toString().padLeft(2,'0')}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _examDate == null ? AppColors.inkMuted : AppColors.ink,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right, color: AppColors.inkMuted),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onDone(_examDate);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('はじめる', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onDone(null);
              },
              child: const Text('あとで設定する', style: TextStyle(color: AppColors.inkMuted)),
            ),
          ],
        ),
      ),
    );
  }
}
