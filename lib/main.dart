import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';

import 'package:appinio_swiper/appinio_swiper.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'widgets/ad_banner.dart';
import 'utils/ad_manager.dart';
import 'utils/purchase_manager.dart';
import 'widgets/special_offer_dialog.dart';
import 'utils/prefs_helper.dart';
import 'utils/migration_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';

import 'theme/app_chrome.dart';
import 'utils/notification_service.dart';
import 'widgets/premium_upgrade_dialog.dart';
import 'widgets/category_review_modal.dart';
import 'widgets/tutorial_overlay.dart';
import 'models/app_data.dart';
import 'utils/api_service.dart';
import 'utils/responsive_helper.dart';
import 'package:in_app_review/in_app_review.dart';

final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();
const bool kAlwaysShowExplanationModeNoticeForTesting = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await PurchaseManager.instance.initialize();
  await NotificationService.initialize();

  runApp(const MyApp());
}

// -----------------------------------------------------------------------------
// 1. Data Models & Helpers
// -----------------------------------------------------------------------------

// Data Models & Helpers are now in lib/models/app_data.dart
// QuizData is replaced by ApiService and dynamic AppData in _MyHomePageState

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '潜水士試験対策',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ja', '')],
      locale: const Locale('ja', ''),
      theme: AppChrome.theme(context),
      navigatorObservers: [routeObserver],
      home: const HomePage(),
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
  bool _isLoading = true;
  bool _isSequentialMode = false;
  Map<String, int> _categoryWeaknessCounts = {};
  Map<String, int> _categoryHighScores = {};
  AppData? _appData;
  late final PageController _categoryPageController;
  int _currentCategoryPage = 0;
  int _bookmarkCount = 0;
  int _totalAnsweredCount = 0;
  int _bestStreak = 0;
  int _consecutiveDaysStreak = 0;
  bool _hasStudiedToday = false;
  DateTime? _examDate;
  int _dailyGoalTarget = 30;
  int _todayAnsweredCount = 0;
  bool _notifEnabled = true;
  int _notifHour = 20;
  bool _showAnswerExplanation = true;
  bool _isExplanationNoticeShowing = false;
  Map<String, int> _categoryBookmarkCounts = {};
  Map<String, int> _categoryAccuracyRates = {};
  Map<String, int> _categoryAnsweredCounts = {};
  Map<String, int> _dailyAnsweredHistory = {};
  Map<String, int> _dailyBestStreakHistory = {};

  @override
  void initState() {
    super.initState();
    _categoryPageController = PageController(viewportFraction: 0.82);
    _initializeApp();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    _loadUserData();
  }

  @override
  void reassemble() {
    super.reassemble();
    if (!kAlwaysShowExplanationModeNoticeForTesting) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _maybeShowExplanationModeNotice();
      }
    });
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _categoryPageController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    // データ移行（ローカルのみ、高速）
    await MigrationHelper.performMigration();

    // キャッシュまたはバンドルassetから即座に読み込む（ネットワーク不使用）
    final apiService = ApiService();
    _appData = await apiService.loadFromCacheOrFallback('sensui');

    if (_appData != null) {
      AdManager.instance.setAdUnitIds(
        bannerId: _appData!.config.adBannerId,
        interstitialId: _appData!.config.adInterstitialId,
      );
      PurchaseManager.instance.setProductId(_appData!.config.premiumProductId);
    }

    await _loadUserData();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }

    // UI表示後に権限・広告・バックグラウンド更新を実行
    _initPostDisplay(apiService);
  }

  Future<void> _initPostDisplay(ApiService apiService) async {
    // ATT権限リクエスト
    final status = await AppTrackingTransparency.requestTrackingAuthorization();
    debugPrint("ATT Status: $status");

    // 通知権限リクエスト（ATTの後に出して重ならないように）
    await NotificationService.requestPermission();

    // 広告初期化・プリロード
    await MobileAds.instance.initialize();
    AdManager.instance.preloadAd('home');

    // バックグラウンドでGASから最新データを取得しキャッシュを更新（次回起動に反映）
    apiService.refreshInBackground('sensui');

    // 通知スケジュール更新
    final examDateForNotif = await PrefsHelper.getExamDate();
    final streakForNotif = await PrefsHelper.getConsecutiveDaysStreak();
    final notifEnabledForSchedule = await PrefsHelper.getNotifEnabled();
    final notifHourForSchedule = await PrefsHelper.getNotifHour();
    await NotificationService.scheduleDailyReminder(
      examDate: examDateForNotif,
      streak: streakForNotif,
      enabled: notifEnabledForSchedule,
      hour: notifHourForSchedule,
    );

    // 初回のみ試験日オンボーディングを表示
    final onboardingDone = await PrefsHelper.isExamOnboardingDone();
    if (!onboardingDone && mounted) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) _showExamDateOnboarding();
    }

    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 250));
      if (mounted) {
        _maybeShowExplanationModeNotice();
      }
    }
  }

  Future<void> _maybeShowExplanationModeNotice() async {
    if (_isExplanationNoticeShowing || !mounted) return;

    final hasExistingUsage =
        await PrefsHelper.isTutorialShown() ||
        (await PrefsHelper.getAnsweredCount()) > 0 ||
        (await PrefsHelper.getBookmarkedQuestions()).isNotEmpty ||
        (await PrefsHelper.getWeakQuestions()).isNotEmpty;
    final shouldShow =
        (kAlwaysShowExplanationModeNoticeForTesting || hasExistingUsage) &&
        !await PrefsHelper.isExplanationModeNoticeShown();
    if (!shouldShow || !mounted) return;

    _isExplanationNoticeShowing = true;
    await PrefsHelper.markExplanationModeNoticeShown();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'アップデート',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '解説の表示タイミングを選べるようになりました',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '設定から、1問ごとに確認するか、最後にまとめて確認するかを切り替えできます。',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkSoft,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'あとで',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _showSettingsSheet();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          child: const Text('設定を見る'),
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

    _isExplanationNoticeShowing = false;
  }

  Future<void> _loadUserData() async {
    final weakList = await PrefsHelper.getWeakQuestions();
    final bookmarkList = await PrefsHelper.getBookmarkedQuestions();
    final totalAnswered = await PrefsHelper.getAnsweredCount();
    final bestStreak = await PrefsHelper.getBestStreak();
    final dailyAnswered = await PrefsHelper.getDailyAnsweredHistory();
    final dailyBestStreak = await PrefsHelper.getDailyBestStreakHistory();
    final consecutiveDays = await PrefsHelper.getConsecutiveDaysStreak();
    final studiedToday = await PrefsHelper.hasStudiedToday();
    final examDate = await PrefsHelper.getExamDate();
    final dailyGoal = await PrefsHelper.getDailyGoal();
    final notifEnabled = await PrefsHelper.getNotifEnabled();
    final notifHour = await PrefsHelper.getNotifHour();
    final showAnswerExplanation = await PrefsHelper.getShowAnswerExplanation();
    if (_appData == null) return;

    final counts = <String, int>{};
    final highScores = <String, int>{};
    final bookmarkCounts = <String, int>{};
    final accuracyRates = <String, int>{};
    final answeredCounts = <String, int>{};

    for (var entry in _appData!.questions.entries) {
      final categoryKey = entry.key;
      final questions = entry.value;
      final categoryQuestionTexts = questions.map((q) => q.question).toSet();

      int weakCount = 0;
      for (var t in weakList) {
        if (categoryQuestionTexts.contains(t)) weakCount++;
      }
      counts[categoryKey] = weakCount;

      int bookmarkCount = 0;
      for (var t in bookmarkList) {
        if (categoryQuestionTexts.contains(t)) bookmarkCount++;
      }
      bookmarkCounts[categoryKey] = bookmarkCount;

      highScores[categoryKey] = await PrefsHelper.getHighScore(
        'highscore_$categoryKey',
      );

      final answeredCount = await PrefsHelper.getCategoryAnsweredCount(
        categoryKey,
      );
      final correctCount = await PrefsHelper.getCategoryCorrectCount(
        categoryKey,
      );
      accuracyRates[categoryKey] = answeredCount > 0
          ? ((correctCount / answeredCount) * 100).round()
          : 0;
      answeredCounts[categoryKey] = answeredCount;
    }

    if (mounted) {
      setState(() {
        _weaknessCount = weakList.length;
        _bookmarkCount = bookmarkCounts.values.fold(0, (sum, c) => sum + c);
        _totalAnsweredCount = totalAnswered;
        _bestStreak = bestStreak;
        _consecutiveDaysStreak = consecutiveDays;
        _hasStudiedToday = studiedToday;
        _examDate = examDate;
        _todayAnsweredCount = dailyAnswered[_dateKey(DateTime.now())] ?? 0;
        _dailyGoalTarget = dailyGoal;
        _notifEnabled = notifEnabled;
        _notifHour = notifHour;
        _showAnswerExplanation = showAnswerExplanation;
        _dailyAnsweredHistory = dailyAnswered;
        _dailyBestStreakHistory = dailyBestStreak;
        _categoryWeaknessCounts = counts;
        _categoryHighScores = highScores;
        _categoryBookmarkCounts = bookmarkCounts;
        _categoryAccuracyRates = accuracyRates;
        _categoryAnsweredCounts = answeredCounts;
      });
    }
  }

  void _startQuiz(
    BuildContext context,
    List<Quiz> quizList,
    String categoryKey,
  ) async {
    List<Quiz> questionsToUse = List<Quiz>.from(quizList);

    if (!_isSequentialMode) {
      // Shuffle Mode (10 questions)
      questionsToUse.shuffle();
      if (questionsToUse.length > 10) {
        questionsToUse = questionsToUse.take(10).toList();
      }
    } else {
      // Sequential Mode (All questions, no shuffle)
      // They are already in order from the API data
    }

    AdManager.instance.preloadAd('result');
    AdManager.instance.preloadAd('quiz');
    AdManager.instance.preloadInterstitial();

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QuizPage(
          quizzes: questionsToUse,
          categoryKey: categoryKey,
          totalQuestions: questionsToUse.length,
          showAnswerExplanation: _showAnswerExplanation,
        ),
      ),
    );
    if (!mounted) return;
    _loadUserData();
  }

  void _showPremiumDialog() {
    showDialog(
      context: context,
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
        showAnswerExplanation: _showAnswerExplanation,
        examDate: _examDate,
        streak: _consecutiveDaysStreak,
        feedbackUrl: _appData?.config.feedbackUrl ?? '',
        appTitle: _appData?.config.appTitle ?? '',
        onChanged:
            ({
              int? goal,
              bool? notifEnabled,
              int? notifHour,
              bool? showAnswerExplanation,
            }) async {
              if (goal != null) {
                await PrefsHelper.setDailyGoal(goal);
              }
              if (notifEnabled != null) {
                await PrefsHelper.setNotifEnabled(notifEnabled);
              }
              if (notifHour != null) {
                await PrefsHelper.setNotifHour(notifHour);
              }
              if (showAnswerExplanation != null) {
                await PrefsHelper.setShowAnswerExplanation(
                  showAnswerExplanation,
                );
              }
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
          if (mounted) setState(() => _examDate = date);
        },
      ),
    );
  }

  Future<void> _showExamDateOnboarding() async {
    await PrefsHelper.markExamOnboardingDone();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      builder: (ctx) => _ExamDateOnboardingSheet(
        initialDate: _examDate,
        onDateSelected: (date) async {
          await PrefsHelper.setExamDate(date);
          await NotificationService.scheduleDailyReminder(
            examDate: date,
            streak: _consecutiveDaysStreak,
          );
          if (mounted) setState(() => _examDate = date);
        },
      ),
    );
  }

  Future<void> _showExamDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _examDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      helpText: '試験日を選択',
      confirmText: '設定',
      cancelText: 'キャンセル',
    );
    if (picked == null) return;
    await PrefsHelper.setExamDate(picked);
    await NotificationService.scheduleDailyReminder(
      examDate: picked,
      streak: _consecutiveDaysStreak,
    );
    if (mounted) setState(() => _examDate = picked);
  }

  Widget _buildDailyGoal() {
    final achieved = _todayAnsweredCount >= _dailyGoalTarget;
    final progress = (_todayAnsweredCount / _dailyGoalTarget).clamp(0.0, 1.0);
    final progressColor = achieved ? const Color(0xFF4CAF50) : AppColors.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: achieved
            ? const Color(0xFF4CAF50).withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: achieved
              ? const Color(0xFF4CAF50).withValues(alpha: 0.35)
              : AppColors.line.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(
                achieved ? Icons.check_circle_rounded : Icons.today_rounded,
                size: 14,
                color: progressColor,
              ),
              const SizedBox(width: 6),
              Text(
                '今日の目標',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: progressColor.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            achieved
                ? '$_dailyGoalTarget問 達成！'
                : '$_todayAnsweredCount / $_dailyGoalTarget問',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: progressColor,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: AppColors.line.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExamDateBanner() {
    if (_examDate == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line.withValues(alpha: 0.7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.calendar_month_rounded,
                  size: 14,
                  color: AppColors.inkMuted,
                ),
                const SizedBox(width: 6),
                const Text(
                  '試験日',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '設定から登録',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.inkSoft,
              ),
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exam = DateTime(_examDate!.year, _examDate!.month, _examDate!.day);
    final daysLeft = exam.difference(today).inDays;

    final Color bannerColor;
    final Color textColor;
    final String countdownText;

    if (daysLeft < 0) {
      bannerColor = AppColors.line.withValues(alpha: 0.4);
      textColor = AppColors.inkMuted;
      countdownText = '試験日が過ぎました';
    } else if (daysLeft == 0) {
      bannerColor = const Color(0xFFCC6A43).withValues(alpha: 0.12);
      textColor = const Color(0xFFCC6A43);
      countdownText = '今日が試験日！';
    } else if (daysLeft <= 7) {
      bannerColor = const Color(0xFFCC6A43).withValues(alpha: 0.10);
      textColor = const Color(0xFFCC6A43);
      countdownText = 'あと $daysLeft 日';
    } else if (daysLeft <= 30) {
      bannerColor = const Color(0xFFFF9D0A).withValues(alpha: 0.10);
      textColor = const Color(0xFFE08800);
      countdownText = 'あと $daysLeft 日';
    } else {
      bannerColor = AppColors.accent.withValues(alpha: 0.08);
      textColor = AppColors.accent;
      countdownText = 'あと $daysLeft 日';
    }

    final examLabel =
        '${_examDate!.year}/${_examDate!.month.toString().padLeft(2, '0')}/${_examDate!.day.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bannerColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: textColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_rounded, size: 14, color: textColor),
              const SizedBox(width: 6),
              Text(
                '試験まで',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: textColor.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            countdownText,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: textColor,
            ),
          ),
          Text(
            examLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: textColor.withValues(alpha: 0.6),
            ),
          ),
        ],
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
                    if (!isPremium) {
                      _showPremiumDialog();
                      return;
                    }
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
    final innerRadius = Radius.zero;
    final outerRadius = const Radius.circular(17);
    final borderRadius = isFirst
        ? BorderRadius.only(
            topLeft: outerRadius,
            bottomLeft: outerRadius,
            topRight: innerRadius,
            bottomRight: innerRadius,
          )
        : BorderRadius.only(
            topRight: outerRadius,
            bottomRight: outerRadius,
            topLeft: innerRadius,
            bottomLeft: innerRadius,
          );

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
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : AppColors.inkMuted,
              ),
              if (isLocked)
                Positioned(
                  right: 8,
                  bottom: 6,
                  child: Icon(
                    Icons.lock_rounded,
                    size: 11,
                    color: AppColors.inkMuted.withValues(alpha: 0.9),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeStatsRow(BuildContext context, {bool compact = false}) {
    final streakActive = _consecutiveDaysStreak > 0;
    final streakAtRisk = streakActive && !_hasStudiedToday;
    final streakBg = streakAtRisk
        ? const Color(0xFFCC6A43).withValues(alpha: 0.10)
        : streakActive
        ? const Color(0xFFFF9D0A).withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.9);
    final streakBorder = streakAtRisk
        ? const Color(0xFFCC6A43).withValues(alpha: 0.35)
        : streakActive
        ? const Color(0xFFFF9D0A).withValues(alpha: 0.35)
        : AppColors.line.withValues(alpha: 0.88);
    final streakValueColor = streakAtRisk
        ? const Color(0xFFCC6A43)
        : streakActive
        ? const Color(0xFFE08800)
        : AppColors.ink;

    return Row(
      children: [
        Expanded(
          child: _HomeStatCard(
            icon: Icons.bar_chart_rounded,
            label: '総回答数',
            value: '$_totalAnsweredCount',
            backgroundColor: AppColors.accent.withValues(alpha: 0.08),
            borderColor: AppColors.accent.withValues(alpha: 0.18),
            labelColor: AppColors.accent.withValues(alpha: 0.75),
            valueColor: AppColors.accent,
            iconColor: AppColors.accent.withValues(alpha: 0.7),
            onTap: () => _showStatsHistorySheet(
              title: '総回答数',
              subtitle: '日ごとの回答数',
              history: _dailyAnsweredHistory,
              color: const Color(0xFF4F6FA9),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _HomeStatCard(
            icon: Icons.local_fire_department_rounded,
            label: streakAtRisk ? '連続学習 ⚠️' : '連続学習',
            value: '${_consecutiveDaysStreak}日',
            backgroundColor: streakBg,
            borderColor: streakBorder,
            labelColor: streakAtRisk
                ? const Color(0xFFCC6A43).withValues(alpha: 0.8)
                : AppColors.inkMuted,
            valueColor: streakValueColor,
            iconColor: const Color(0xFFFF9D0A).withValues(alpha: 0.9),
            onTap: () => _showStatsHistorySheet(
              title: '連続学習',
              subtitle: '日ごとの学習記録',
              history: _dailyAnsweredHistory,
              color: const Color(0xFFFF9D0A),
            ),
          ),
        ),
      ],
    );
  }

  void _showStatsHistorySheet({
    required String title,
    required String subtitle,
    required Map<String, int> history,
    required Color color,
  }) {
    final points = _buildRecentDailyStats(history);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
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
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 16),
                SoftSurface(
                  borderRadius: BorderRadius.circular(26),
                  borderColor: AppColors.line.withValues(alpha: 0.84),
                  fillColor: Colors.white.withValues(alpha: 0.9),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    child: points.every((p) => p.value == 0)
                        ? const SizedBox(
                            height: 180,
                            child: Center(
                              child: Text(
                                'まだ記録がありません',
                                style: TextStyle(
                                  color: AppColors.inkSoft,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                        : _StatsBarChart(points: points, color: color),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<_DailyStatPoint> _buildRecentDailyStats(Map<String, int> history) {
    final now = DateTime.now();
    return List.generate(7, (index) {
      final date = now.subtract(Duration(days: 6 - index));
      final key = _dateKey(date);
      return _DailyStatPoint(
        label: '${date.month}/${date.day}',
        value: history[key] ?? 0,
      );
    });
  }

  String _dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Widget _buildBottomHomeActions(BuildContext context, {bool compact = false}) {
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
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: compact ? 44 : 48,
                    child: ElevatedButton.icon(
                      onPressed: _weaknessCount > 0
                          ? () => _startWeaknessReview(context)
                          : null,
                      icon: const Icon(
                        Icons.history_edu_rounded,
                        color: Color(0xFFCC6A43),
                      ),
                      label: Text(
                        '要復習 $_weaknessCount',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
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
                                  if (!isPremium) {
                                    _showPremiumDialog();
                                    return;
                                  }
                                  _startBookmarkReview(context);
                                }
                              : null,
                          icon: Icon(
                            isPremium
                                ? Icons.bookmark_rounded
                                : Icons.lock_rounded,
                            color: const Color(0xFF5D729D),
                          ),
                          label: Text(
                            'ブックマーク $_bookmarkCount',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF3F6FB),
                            foregroundColor: AppColors.accent,
                            elevation: 2,
                            shadowColor: const Color(
                              0xFF21314D,
                            ).withValues(alpha: 0.05),
                            side: BorderSide(
                              color: AppColors.line.withValues(alpha: 0.9),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
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

  void _startBookmarkReview(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => CategoryReviewModal(
        counts: _categoryBookmarkCounts,
        categoryOrder: _appData!.categoryOrder,
        onCategorySelected: (categoryKey) =>
            _startBookmarkReviewByCategory(context, categoryKey),
      ),
    );
  }

  void _startBookmarkReviewByCategory(
    BuildContext context,
    String categoryKey,
  ) async {
    final bookmarkedTexts = await PrefsHelper.getBookmarkedQuestions();
    if (!mounted || _appData == null) return;
    if (bookmarkedTexts.isEmpty) return;

    final categoryQuizzes = _appData!.questions[categoryKey] ?? [];
    if (categoryQuizzes.isEmpty) return;

    final categoryQuestionsSet = categoryQuizzes.map((q) => q.question).toSet();
    final bookmarkedQuizzes = _getQuizzesFromTexts(
      bookmarkedTexts,
    ).where((q) => categoryQuestionsSet.contains(q.question)).toList();
    if (bookmarkedQuizzes.isEmpty) return;

    AdManager.instance.preloadAd('result');
    AdManager.instance.preloadAd('quiz');
    AdManager.instance.preloadInterstitial();

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QuizPage(
          quizzes: bookmarkedQuizzes,
          totalQuestions: bookmarkedQuizzes.length,
          showAnswerExplanation: _showAnswerExplanation,
        ),
      ),
    );
    if (!mounted) return;
    _loadUserData();
  }

  void _startWeaknessReview(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => CategoryReviewModal(
        counts: _categoryWeaknessCounts,
        categoryOrder: _appData!.categoryOrder,
        onCategorySelected: (categoryKey) =>
            _startWeaknessReviewByCategory(context, categoryKey),
      ),
    );
  }

  void _startWeaknessReviewByCategory(
    BuildContext context,
    String categoryKey,
  ) async {
    final weakTexts = await PrefsHelper.getWeakQuestions();
    if (!mounted || _appData == null) return;
    if (weakTexts.isEmpty) return;

    final categoryQuizzes = _appData!.questions[categoryKey] ?? [];
    if (categoryQuizzes.isEmpty) return;

    final categoryQuestionsSet = categoryQuizzes.map((q) => q.question).toSet();
    final weakQuizzes = _getQuizzesFromTexts(
      weakTexts,
    ).where((q) => categoryQuestionsSet.contains(q.question)).toList();

    if (weakQuizzes.isEmpty) return;

    AdManager.instance.preloadAd('result');
    AdManager.instance.preloadAd('quiz');
    AdManager.instance.preloadInterstitial();

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QuizPage(
          quizzes: weakQuizzes,
          isWeaknessReview: true,
          totalQuestions: weakQuizzes.length,
          showAnswerExplanation: _showAnswerExplanation,
        ),
      ),
    );
    if (!mounted) return;
    _loadUserData();
  }

  List<Quiz> _getQuizzesFromTexts(List<String> texts) {
    if (_appData == null) return [];

    final allQuizzes = _appData!.questions.values
        .expand((element) => element)
        .toList();
    return allQuizzes.where((q) => texts.contains(q.question)).toList();
  }

  void _startQuizByCategory(BuildContext context, String categoryKey) {
    if (_appData == null) return;

    final quizzes = _appData!.questions[categoryKey] ?? [];

    if (quizzes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('問題データがまだありません')));
      return;
    }
    _startQuiz(context, quizzes, categoryKey);
  }

  void _showCategoryInfoSheet(BuildContext context, String categoryKey) {
    final quizzes = _appData?.questions[categoryKey] ?? [];
    final questionCount = quizzes.length;
    final accuracyRate = _categoryAccuracyRates[categoryKey] ?? 0;
    final answeredCount = _categoryAnsweredCounts[categoryKey] ?? 0;
    final highScore = _categoryHighScores[categoryKey] ?? 0;
    final weaknessCount = _categoryWeaknessCounts[categoryKey] ?? 0;
    final completionRate = questionCount == 0
        ? 0.0
        : (math.min(answeredCount, questionCount) / questionCount).clamp(
            0.0,
            1.0,
          );
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
                  categoryKey,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
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
                            backgroundColor: AppColors.line.withValues(
                              alpha: 0.4,
                            ),
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
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final l10n = AppLocalizations.of(context)!;
    final seen = <String>{};
    final categories = (_appData?.categoryOrder ?? [])
        .where((c) => seen.add(c))
        .toList();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        centerTitle: false,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF4A90E2),
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: const Text(
                '問',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _appData?.config.appTitle ?? l10n.appTitle,
                style: TextStyle(
                  fontSize: ResponsiveHelper.respFontSize(context, 16),
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _showSettingsSheet,
            icon: const Icon(Icons.settings_rounded),
            color: Colors.white.withValues(alpha: 0.8),
            iconSize: 22,
          ),
          const SizedBox(width: 2),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxHeight < 610;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  14,
                  isCompact ? 10 : 16,
                  14,
                  isCompact ? 14 : 22,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                    const SizedBox(height: 6),
                    if (categories.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            '問題データがありません',
                            style: TextStyle(
                              color: AppColors.inkSoft,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    else ...[
                      ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: categories.length,
                        itemBuilder: (ctx, idx) {
                          final catKey = categories[idx];
                          final quizzes = _appData!.questions[catKey] ?? [];
                          return _CategoryListItem(
                            index: idx,
                            title: catKey,
                            questionCount: quizzes.length,
                            onTap: () => _startQuizByCategory(context, catKey),
                            onInfo: () =>
                                _showCategoryInfoSheet(context, catKey),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildBottomHomeActions(context, compact: isCompact),
                      const SizedBox(height: 8),
                      if (false) // 姉妹アプリ一時非表示
                        ValueListenableBuilder<bool>(
                          valueListenable: PurchaseManager.instance.isPremium,
                          builder: (context, isPremium, _) {
                            if (isPremium) return const SizedBox.shrink();
                            return Column(
                              children: [
                                _SisterAppPromotion(config: _appData?.config),
                                const SizedBox(height: 8),
                              ],
                            );
                          },
                        ),
                      _buildPremiumBanner(),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
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

// ---------------------------------------------------------------------------
// Category carousel card (旧デザイン — 非表示中)
// ---------------------------------------------------------------------------

class _CategoryCarouselCard extends StatelessWidget {
  final String title;
  final int questionCount;
  final int highScore;
  final int weaknessCount;
  final int accuracyRate;
  final int answeredCount;
  final bool isActive;
  final bool isSmallScreen;
  final VoidCallback onStart;

  const _CategoryCarouselCard({
    required this.title,
    required this.questionCount,
    required this.highScore,
    required this.weaknessCount,
    required this.accuracyRate,
    required this.answeredCount,
    required this.isActive,
    this.isSmallScreen = false,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final cardFill = isActive
        ? Colors.white.withValues(alpha: 0.98)
        : const Color(0xFFF3F5F8);
    final borderColor = AppColors.line.withValues(alpha: 0.84);
    const startButtonColor = AppColors.accent;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 360;
        final padding = EdgeInsets.fromLTRB(
          compact ? 16 : 22,
          compact ? 14 : 18,
          compact ? 16 : 22,
          compact ? 12 : 16,
        );

        return SoftSurface(
          borderRadius: BorderRadius.circular(32),
          borderColor: borderColor,
          boxShadow: AppChrome.liftShadow,
          fillColor: cardFill,
          child: Padding(
            padding: padding,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ResponsiveHelper.respFontSize(
                      context,
                      isSmallScreen ? 17 : 21,
                    ),
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    height: 1.08,
                  ),
                ),
                SizedBox(height: compact ? 10 : 18),
                Expanded(
                  child: _CategoryStatusPanel(
                    questionCount: questionCount,
                    highScore: highScore,
                    weaknessCount: weaknessCount,
                    accuracyRate: accuracyRate,
                    answeredCount: answeredCount,
                    compact: compact,
                  ),
                ),
                SizedBox(height: compact ? 6 : 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 220,
                      maxWidth: 320,
                    ),
                    child: SizedBox(
                      height: compact ? 40 : 44,
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onStart,
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text(
                          '学習を開始',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: AppChrome.primaryButtonStyle(
                          backgroundColor: startButtonColor,
                          foregroundColor: Colors.white,
                          radius: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CategoryStatusPanel extends StatelessWidget {
  final int questionCount;
  final int highScore;
  final int weaknessCount;
  final int accuracyRate;
  final int answeredCount;
  final bool compact;

  const _CategoryStatusPanel({
    required this.questionCount,
    required this.highScore,
    required this.weaknessCount,
    required this.accuracyRate,
    required this.answeredCount,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final panelBorder = AppColors.line.withValues(alpha: 0.82);
    const labelColor = AppColors.inkMuted;
    const metricColor = AppColors.inkSoft;
    final dividerColor = AppColors.line.withValues(alpha: 0.68);
    final trackColor = Colors.white.withValues(alpha: 0.95);
    final hasAnswered = answeredCount > 0;
    final headlineLabel = weaknessCount > 0 ? '要復習' : '問題数';
    final headlineValue = weaknessCount > 0
        ? '$weaknessCount問'
        : '$questionCount問';
    final headlineColor = weaknessCount > 0
        ? const Color(0xFFCC6A43)
        : AppColors.accent;
    final completionRate = questionCount == 0
        ? 0.0
        : (math.min(answeredCount, questionCount) / questionCount).clamp(
            0.0,
            1.0,
          );
    final completionPercent = (completionRate * 100).round();
    final barColor = weaknessCount > 0
        ? const Color(0xFFCC6A43)
        : AppColors.accent;
    final barWidth = completionRate;

    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 14,
        compact ? 10 : 12,
        compact ? 12 : 14,
        compact ? 9 : 11,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFAFBFD), Color(0xFFF2F6FA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                headlineLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: labelColor,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                headlineValue,
                style: TextStyle(
                  fontSize: ResponsiveHelper.respFontSize(context, 25),
                  fontWeight: FontWeight.w900,
                  color: headlineColor,
                  height: 1,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 5 : 8),
          Row(
            children: [
              const Text(
                '進捗',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: labelColor,
                ),
              ),
              const Spacer(),
              Text(
                !hasAnswered
                    ? '未着手'
                    : (completionRate >= 1.0 ? '完了' : '$completionPercent%'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: completionRate >= 1.0
                      ? const Color(0xFF4CAF50)
                      : weaknessCount > 0
                      ? headlineColor
                      : AppColors.accent,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 4 : 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 8,
              color: trackColor,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: barWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: barColor.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 5 : 8),
          Container(height: 1, color: dividerColor),
          SizedBox(height: compact ? 5 : 7),
          Row(
            children: [
              Expanded(
                child: _CategoryStatusMetric(
                  label: '正答率',
                  value: accuracyRate > 0 ? '$accuracyRate%' : '--',
                  labelColor: labelColor,
                  valueColor: metricColor,
                ),
              ),
              _CategoryStatusDivider(color: dividerColor),
              Expanded(
                child: _CategoryStatusMetric(
                  label: '最高',
                  value: highScore > 0 ? '$highScore点' : '--',
                  labelColor: labelColor,
                  valueColor: metricColor,
                ),
              ),
              _CategoryStatusDivider(color: dividerColor),
              Expanded(
                child: _CategoryStatusMetric(
                  label: '全問題',
                  value: '$questionCount問',
                  labelColor: labelColor,
                  valueColor: metricColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryStatusMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;

  const _CategoryStatusMetric({
    required this.label,
    required this.value,
    required this.labelColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: valueColor,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _CategoryStatusDivider extends StatelessWidget {
  final Color color;
  const _CategoryStatusDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: color,
    );
  }
}

class _HomeStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color backgroundColor;
  final Color borderColor;
  final Color labelColor;
  final Color valueColor;
  final Color iconColor;
  final VoidCallback? onTap;

  const _HomeStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.backgroundColor,
    required this.borderColor,
    required this.labelColor,
    required this.valueColor,
    required this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      borderColor: borderColor,
      fillColor: backgroundColor,
      boxShadow: AppChrome.softShadow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: iconColor),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: labelColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: valueColor,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyStatPoint {
  final String label;
  final int value;
  const _DailyStatPoint({required this.label, required this.value});
}

class _StatsBarChart extends StatelessWidget {
  final List<_DailyStatPoint> points;
  final Color color;

  const _StatsBarChart({required this.points, required this.color});

  @override
  Widget build(BuildContext context) {
    final maxValue = points.fold<int>(
      0,
      (max, p) => p.value > max ? p.value : max,
    );
    final safeMax = maxValue == 0 ? 1 : maxValue;

    return SizedBox(
      height: 180,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: points.map((point) {
          final ratio = point.value / safeMax;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${point.value}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 112,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        height: math.max(6, 112 * ratio),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.18),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    point.label,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
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
  final int totalQuestions;
  final bool showAnswerExplanation;

  const QuizPage({
    super.key,
    required this.quizzes,
    this.categoryKey,
    this.isWeaknessReview = false,
    required this.totalQuestions,
    required this.showAnswerExplanation,
  });

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  final AppinioSwiperController controller = AppinioSwiperController();

  int _score = 0;
  int _currentIndex = 1;
  final List<Quiz> _incorrectQuizzes = [];
  final List<Quiz> _correctQuizzesInReview = [];
  final List<Map<String, dynamic>> _answerHistory = [];
  int _currentCorrectStreak = 0;
  int _bestCorrectStreak = 0;
  Color _backgroundColor = Colors.transparent;
  bool _showTutorial = false;
  _AnswerFeedbackData? _answerFeedback;
  bool _shouldFinishAfterFeedback = false;
  double _feedbackExitDirection = 0;
  bool _isFeedbackExiting = false;

  @override
  void initState() {
    super.initState();
    _checkTutorial();
  }

  Future<void> _checkTutorial() async {
    final shown = await PrefsHelper.isTutorialShown();
    if (!shown && mounted) {
      setState(() {
        _showTutorial = true;
      });
    }
  }

  void _dismissTutorial() {
    setState(() {
      _showTutorial = false;
    });
    PrefsHelper.markTutorialShown();
  }

  void _handleSwipeEnd(
    int previousIndex,
    int targetIndex,
    SwiperActivity activity,
  ) {
    if (activity is Swipe) {
      final quiz = widget.quizzes[previousIndex];
      bool userVal = (activity.direction == AxisDirection.right);
      bool isCorrect = (userVal == quiz.isCorrect);

      _answerHistory.add({'quiz': quiz, 'result': isCorrect});

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
            _recordWeakness(quiz.question, true);
          }
        } else {
          _currentCorrectStreak = 0;
          _backgroundColor = Colors.red.withValues(alpha: 0.2);
          _incorrectQuizzes.add(quiz);
          HapticFeedback.heavyImpact();
          _recordWeakness(quiz.question, false);
        }
      });

      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          setState(() {
            _backgroundColor = Colors.transparent;
          });
        }
      });

      final isLastQuestion = previousIndex == widget.quizzes.length - 1;

      if (widget.showAnswerExplanation) {
        setState(() {
          _answerFeedback = _AnswerFeedbackData(
            quiz: quiz,
            isCorrect: isCorrect,
          );
          _shouldFinishAfterFeedback = isLastQuestion;
          _feedbackExitDirection = 0;
          _isFeedbackExiting = false;
        });
      } else {
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 600),
            content: Text(
              isCorrect ? "正解！ ⭕" : "不正解... ❌",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ResponsiveHelper.respFontSize(context, 18),
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: isCorrect ? Colors.green : Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height * 0.5,
              left: ResponsiveHelper.respPadding(context, 50),
              right: ResponsiveHelper.respPadding(context, 50),
            ),
          ),
        );
      }

      setState(() {
        if (_currentIndex < widget.totalQuestions) {
          _currentIndex++;
        }
      });

      if (isLastQuestion && !widget.showAnswerExplanation) {
        _finishQuiz();
      }
    }
  }

  Future<void> _finishQuiz() async {
    if (!widget.showAnswerExplanation) {
      await Future.delayed(const Duration(milliseconds: 700));
    }

    if (widget.categoryKey != null) {
      await PrefsHelper.saveHighScore(
        'highscore_${widget.categoryKey!}',
        _score,
      );
      await PrefsHelper.addCategoryAnsweredCount(
        widget.categoryKey!,
        widget.quizzes.length,
      );
      await PrefsHelper.addCategoryCorrectCount(widget.categoryKey!, _score);
    }
    await PrefsHelper.addAnsweredCount(widget.quizzes.length);
    await PrefsHelper.addDailyAnsweredCount(widget.quizzes.length);
    await PrefsHelper.saveBestStreak(_bestCorrectStreak);
    await PrefsHelper.saveDailyBestStreak(_bestCorrectStreak);

    // Increment quiz completion count and check for review prompt
    final completionCount = await PrefsHelper.incrementQuizCompletionCount();
    if (completionCount == 3) {
      final InAppReview inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        inAppReview.requestReview();
      }
    }

    if (_incorrectQuizzes.isNotEmpty) {
      final incorrectTexts = _incorrectQuizzes.map((q) => q.question).toList();
      await PrefsHelper.addWeakQuestions(incorrectTexts);
    }

    if (widget.isWeaknessReview && _correctQuizzesInReview.isNotEmpty) {
      final correctTexts = _correctQuizzesInReview
          .map((q) => q.question)
          .toList();
      await PrefsHelper.removeWeakQuestions(correctTexts);
    }

    if (mounted) {
      final shouldShow = await PrefsHelper.shouldShowInterstitial();

      if (shouldShow) {
        AdManager.instance.showInterstitial(
          onComplete: () async {
            if (mounted) {
              // After interstitial, check for special offer
              final showOffer = await PurchaseManager.instance
                  .shouldShowSpecialOffer();
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

  Future<void> _recordWeakness(String question, bool isCorrect) async {
    if (isCorrect) {
      await PrefsHelper.removeWeakQuestions([question]);
    } else {
      await PrefsHelper.addWeakQuestions([question]);
    }
  }

  void _navigateToResult() {
    ScaffoldMessenger.of(context).clearSnackBars();
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
          showAnswerExplanation: widget.showAnswerExplanation,
        ),
      ),
    );
  }

  Future<void> _continueAfterAnswerFeedback([double? exitDirection]) async {
    final shouldFinish = _shouldFinishAfterFeedback;
    final resolvedDirection =
        exitDirection ?? ((_answerFeedback?.isCorrect ?? true) ? 1 : -1);
    setState(() {
      _feedbackExitDirection = resolvedDirection;
      _isFeedbackExiting = true;
    });
    await Future.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    setState(() {
      _answerFeedback = null;
      _shouldFinishAfterFeedback = false;
      _feedbackExitDirection = 0;
      _isFeedbackExiting = false;
    });
    if (shouldFinish) {
      _finishQuiz();
    }
  }

  void _undoLastAnswer() {
    controller.unswipe();
    setState(() {
      _answerFeedback = null;
      _shouldFinishAfterFeedback = false;
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
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.backgroundTop, AppColors.backgroundBottom],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              color: _backgroundColor,
              child: SafeArea(
                child: Column(
                  children: [
                    // Custom Header Row
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        4,
                        ResponsiveHelper.isTablet(context) ? 24 : 8,
                        24,
                        8,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.chevron_left_rounded,
                              color: Colors.black54,
                              size: 40,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            iconSize: 40,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _currentIndex / widget.totalQuestions,
                                minHeight: 8,
                                backgroundColor: Colors.grey[300],
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF2F5D8C),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            "$_currentIndex / ${widget.totalQuestions}",
                            style: TextStyle(
                              fontSize: ResponsiveHelper.respFontSize(
                                context,
                                14,
                              ),
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 6,
                            ),
                            child: IgnorePointer(
                              ignoring: _answerFeedback != null,
                              child: AppinioSwiper(
                                controller: controller,
                                cardCount: widget.quizzes.length,
                                loop: false,
                                backgroundCardCount: 2,
                                swipeOptions: const SwipeOptions.symmetric(
                                  horizontal: true,
                                  vertical: false,
                                ),
                                onSwipeEnd: _handleSwipeEnd,
                                cardBuilder: (context, index) {
                                  return _buildCard(widget.quizzes[index]);
                                },
                              ),
                            ),
                          ),
                          if (_answerFeedback != null)
                            Positioned.fill(
                              child: IgnorePointer(
                                ignoring: false,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      40,
                                      0,
                                      40,
                                      72,
                                    ),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth:
                                            (ResponsiveHelper.respCardWidth(
                                                  context,
                                                ) ??
                                                double.infinity) -
                                            48,
                                      ),
                                      child: _AnswerFeedbackSheet(
                                        feedback: _answerFeedback!,
                                        isLastQuestion:
                                            _shouldFinishAfterFeedback,
                                        exitDirection: _feedbackExitDirection,
                                        isExiting: _isFeedbackExiting,
                                        onContinue:
                                            _continueAfterAnswerFeedback,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.only(top: 18, bottom: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 52,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _undoLastAnswer,
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.zero,
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black87,
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(26),
                                ),
                              ),
                              child: const Icon(Icons.undo_rounded, size: 24),
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
            if (_showTutorial)
              Positioned.fill(
                child: TutorialOverlay(onDismiss: _dismissTutorial),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(Quiz quiz) {
    bool hasImage = quiz.imagePath != null;

    return SizedBox.expand(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                ResponsiveHelper.respCardWidth(context) ?? double.infinity,
          ),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                              const Icon(
                                Icons.image_not_supported,
                                size: 50,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Image not found",
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),

                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(26, 24, 26, 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          "Q.",
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: AutoSizeText(
                            quiz.question,
                            style: TextStyle(
                              fontSize: hasImage ? 20 : 26,
                              fontWeight: FontWeight.bold,
                              height: 1.42,
                              color: Colors.black87,
                            ),
                            textAlign: TextAlign.left,
                            minFontSize: 14,
                            stepGranularity: 1,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.only(
                    left: 44,
                    right: 44,
                    bottom: 28,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => controller.swipeLeft(),
                        child: const Column(
                          children: [
                            Icon(
                              Icons.close,
                              color: Colors.redAccent,
                              size: 56,
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => controller.swipeRight(),
                        child: const Column(
                          children: [
                            Icon(
                              Icons.circle_outlined,
                              color: Colors.green,
                              size: 56,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasImage) const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnswerFeedbackData {
  final Quiz quiz;
  final bool isCorrect;

  const _AnswerFeedbackData({required this.quiz, required this.isCorrect});
}

class _AnswerFeedbackSheet extends StatelessWidget {
  final _AnswerFeedbackData feedback;
  final bool isLastQuestion;
  final ValueChanged<double> onContinue;
  final double exitDirection;
  final bool isExiting;

  const _AnswerFeedbackSheet({
    required this.feedback,
    required this.isLastQuestion,
    required this.onContinue,
    required this.exitDirection,
    required this.isExiting,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = feedback.isCorrect
        ? AppColors.success
        : AppColors.error;
    final fillColor = feedback.isCorrect
        ? const Color(0xFFF2FBF5)
        : const Color(0xFFFFF4F4);
    final label = feedback.isCorrect ? '正解' : '不正解';
    final buttonLabel = isLastQuestion ? '結果を見る' : '次へ';

    return TweenAnimationBuilder<Offset>(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: const Offset(0, 0.18), end: Offset.zero),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          if (isExiting) return;
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() > 120) {
            onContinue(velocity < 0 ? -1 : 1);
          }
        },
        child: Material(
          color: Colors.transparent,
          child: SoftSurface(
            borderRadius: BorderRadius.circular(22),
            borderColor: accentColor.withValues(alpha: 0.26),
            fillColor: fillColor,
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.10),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: const Color(0xFF21314D).withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 228, maxHeight: 270),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                feedback.isCorrect
                                    ? Icons.check_circle_rounded
                                    : Icons.cancel_rounded,
                                size: 16,
                                color: accentColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: accentColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Text(
                        feedback.quiz.explanation,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          height: 1.55,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: Row(
                        children: [
                          const Spacer(),
                          SizedBox(
                            height: 42,
                            child: ElevatedButton(
                              onPressed: () =>
                                  onContinue(feedback.isCorrect ? 1 : -1),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accentColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              child: Text(buttonLabel),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      builder: (context, offset, child) {
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          opacity: isExiting ? 0 : (1 - offset.dy * 1.6).clamp(0.0, 1.0),
          child: AnimatedRotation(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            turns: isExiting ? 0.024 * exitDirection : 0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              offset: isExiting
                  ? Offset(1.08 * exitDirection, -0.02)
                  : Offset(0, offset.dy),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _CollapsingResultSummary extends StatelessWidget {
  final int score;
  final int total;
  final String message;
  final double collapseProgress;

  const _CollapsingResultSummary({
    required this.score,
    required this.total,
    required this.message,
    required this.collapseProgress,
  });

  @override
  Widget build(BuildContext context) {
    final scoreFont = lerpDouble(48, 28, collapseProgress)!;
    final labelFont = lerpDouble(17, 14, collapseProgress)!;
    final horizontalPadding = lerpDouble(28, 20, collapseProgress)!;
    final verticalPadding = lerpDouble(20, 14, collapseProgress)!;
    final summaryHeight = lerpDouble(164, 80, collapseProgress)!;
    final borderRadius = lerpDouble(32, 20, collapseProgress)!;
    final messageOpacity = (1 - collapseProgress * 2.2).clamp(0.0, 1.0);

    return Container(
      height: summaryHeight,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: double.infinity,
            maxWidth:
                ResponsiveHelper.respCardWidth(context) ?? double.infinity,
          ),
          child: SoftSurface(
            borderRadius: BorderRadius.circular(borderRadius),
            borderColor: AppColors.line.withValues(alpha: 0.78),
            fillColor: Colors.white.withValues(alpha: 0.98),
            child: ClipRect(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '正解数',
                          style: TextStyle(
                            fontSize: labelFont,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkMuted,
                          ),
                        ),
                        SizedBox(width: lerpDouble(10, 8, collapseProgress)!),
                        Text(
                          '$score/$total',
                          style: TextStyle(
                            fontSize: ResponsiveHelper.respFontSize(
                              context,
                              scoreFont,
                            ),
                            fontWeight: FontWeight.w900,
                            color: AppColors.warning,
                            letterSpacing: -1,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                    if (collapseProgress < 0.5) ...[
                      SizedBox(height: lerpDouble(10, 4, collapseProgress)!),
                      Opacity(
                        opacity: messageOpacity,
                        child: Text(
                          message,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: score == total
                                ? AppColors.success
                                : score >= 8
                                ? AppColors.success
                                : AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSheet extends StatefulWidget {
  final int dailyGoal;
  final bool notifEnabled;
  final int notifHour;
  final bool showAnswerExplanation;
  final DateTime? examDate;
  final int streak;
  final String feedbackUrl;
  final String appTitle;
  final void Function({
    int? goal,
    bool? notifEnabled,
    int? notifHour,
    bool? showAnswerExplanation,
  })
  onChanged;
  final void Function(DateTime?) onExamDateChanged;

  const _SettingsSheet({
    required this.dailyGoal,
    required this.notifEnabled,
    required this.notifHour,
    required this.showAnswerExplanation,
    required this.examDate,
    required this.streak,
    this.feedbackUrl = '',
    this.appTitle = '',
    required this.onChanged,
    required this.onExamDateChanged,
  });

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late int _goal;
  late bool _notifEnabled;
  late int _notifHour;
  late bool _showAnswerExplanation;
  late DateTime? _examDate;

  static const _goalOptions = [10, 20, 30, 50, 70, 100];

  @override
  void initState() {
    super.initState();
    _goal = widget.dailyGoal;
    _notifEnabled = widget.notifEnabled;
    _notifHour = widget.notifHour;
    _showAnswerExplanation = widget.showAnswerExplanation;
    _examDate = widget.examDate;
  }

  Future<void> _pickExamDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _examDate ?? now.add(const Duration(days: 30)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 730)),
      helpText: '試験日を選択',
    );
    if (picked == null) return;
    setState(() => _examDate = picked);
    widget.onExamDateChanged(picked);
  }

  Future<void> _clearExamDate() async {
    setState(() => _examDate = null);
    widget.onExamDateChanged(null);
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
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '設定',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 20),

            // Exam Date
            const Text(
              '試験日',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickExamDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.line.withValues(alpha: 0.7),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_rounded,
                      size: 18,
                      color: AppColors.inkMuted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _examDate != null
                            ? '${_examDate!.year}/${_examDate!.month.toString().padLeft(2, '0')}/${_examDate!.day.toString().padLeft(2, '0')}'
                            : '未設定',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _examDate != null
                              ? AppColors.ink
                              : AppColors.inkMuted,
                        ),
                      ),
                    ),
                    if (_examDate != null)
                      GestureDetector(
                        onTap: _clearExamDate,
                        child: const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.inkMuted,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            Container(height: 1, color: AppColors.line.withValues(alpha: 0.5)),
            const SizedBox(height: 20),

            // Daily Goal
            const Text(
              '今日の目標',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: _goalOptions.map((g) {
                final selected = _goal == g;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _goal = g);
                      widget.onChanged(goal: g);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.accent : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? AppColors.accent
                              : AppColors.line.withValues(alpha: 0.8),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '$g',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: selected ? Colors.white : AppColors.ink,
                            ),
                          ),
                          Text(
                            '問',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : AppColors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),
            Container(height: 1, color: AppColors.line.withValues(alpha: 0.5)),
            const SizedBox(height: 20),

            const Text(
              '学習スタイル',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.line.withValues(alpha: 0.7),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '解説の表示タイミング',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F6FB),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.line.withValues(alpha: 0.7),
                            ),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildReviewModeOption(
                                  label: '1問ごと確認',
                                  selected: _showAnswerExplanation,
                                  onTap: () {
                                    setState(
                                      () => _showAnswerExplanation = true,
                                    );
                                    widget.onChanged(
                                      showAnswerExplanation: true,
                                    );
                                  },
                                ),
                              ),
                              Expanded(
                                child: _buildReviewModeOption(
                                  label: '最後にまとめて',
                                  selected: !_showAnswerExplanation,
                                  onTap: () {
                                    setState(
                                      () => _showAnswerExplanation = false,
                                    );
                                    widget.onChanged(
                                      showAnswerExplanation: false,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            Container(height: 1, color: AppColors.line.withValues(alpha: 0.5)),
            const SizedBox(height: 20),

            // Notification
            const Text(
              '学習リマインダー',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.line.withValues(alpha: 0.7),
                ),
              ),
              child: Column(
                children: [
                  // ON/OFF
                  Row(
                    children: [
                      const Icon(
                        Icons.notifications_rounded,
                        size: 18,
                        color: AppColors.inkMuted,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '通知',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      Switch.adaptive(
                        value: _notifEnabled,
                        activeTrackColor: AppColors.accent,
                        activeThumbColor: Colors.white,
                        onChanged: (v) {
                          setState(() => _notifEnabled = v);
                          widget.onChanged(notifEnabled: v);
                        },
                      ),
                    ],
                  ),
                  if (_notifEnabled) ...[
                    Divider(
                      height: 1,
                      color: AppColors.line.withValues(alpha: 0.5),
                    ),
                    // Time
                    GestureDetector(
                      onTap: _pickTime,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              size: 18,
                              color: AppColors.inkMuted,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                '通知時間',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                            Text(
                              '${_notifHour.toString().padLeft(2, '0')}:00',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.accent,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: AppColors.inkMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            if (widget.feedbackUrl.isNotEmpty) ...[
              const SizedBox(height: 24),
              Container(
                height: 1,
                color: AppColors.line.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 20),
              const Text(
                'サポート',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  final prefill = Uri.encodeComponent('【${widget.appTitle}】');
                  final uri = Uri.parse(
                    '${widget.feedbackUrl}?usp=pp_url&entry.1780917331=$prefill',
                  );
                  if (!await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  )) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('フォームを開けませんでした')),
                      );
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.line.withValues(alpha: 0.7),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.flag_rounded,
                        size: 18,
                        color: AppColors.inkMuted,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '問題の誤り・ご要望',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: AppColors.inkMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReviewModeOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.accent
                : AppColors.line.withValues(alpha: 0.65),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.20),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _ExamDateOnboardingSheet extends StatefulWidget {
  final DateTime? initialDate;
  final ValueChanged<DateTime> onDateSelected;

  const _ExamDateOnboardingSheet({
    required this.initialDate,
    required this.onDateSelected,
  });

  @override
  State<_ExamDateOnboardingSheet> createState() =>
      _ExamDateOnboardingSheetState();
}

class _ExamDateOnboardingSheetState extends State<_ExamDateOnboardingSheet> {
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      helpText: '試験日を選択',
      confirmText: '設定',
      cancelText: 'キャンセル',
    );
    if (picked != null) setState(() => _selected = picked);
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _selected == null
        ? '日付を選択'
        : '${_selected!.year}年${_selected!.month}月${_selected!.day}日';

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
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '試験日を設定',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '試験日までの日数が表示されます。',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _selected != null
                        ? AppColors.accent.withValues(alpha: 0.5)
                        : AppColors.line,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      color: _selected != null
                          ? AppColors.accent
                          : AppColors.inkMuted,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _selected != null
                            ? AppColors.ink
                            : AppColors.inkMuted,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.inkMuted,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _selected == null
                    ? null
                    : () {
                        widget.onDateSelected(_selected!);
                        Navigator.of(context).pop();
                      },
                style: AppChrome.primaryButtonStyle(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  radius: 20,
                ),
                child: const Text(
                  '設定する',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.inkSoft,
                  side: BorderSide(
                    color: AppColors.line.withValues(alpha: 0.9),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'あとで設定する',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SisterAppPromotion extends StatelessWidget {
  final AppConfig? config;
  const _SisterAppPromotion({this.config});

  Future<void> _launchURL(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    String urlString = config?.nextAppUrl ?? '6758681333';

    // If urlString is purely numeric, treat it as an Apple App ID
    if (RegExp(r'^\d+$').hasMatch(urlString)) {
      urlString = 'https://apps.apple.com/app/id$urlString';
    }

    final Uri url = Uri.parse(urlString);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/sougou_icon.png',
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'サクサク過去問',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.sisterAppDialogBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          l10n.cancel,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          if (!await launchUrl(url)) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.noData),
                                ), // Reuse or add more specific
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: Text(
                          l10n.open,
                          style: const TextStyle(fontWeight: FontWeight.bold),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      elevation: 4,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: () => _launchURL(context),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.respPadding(context, 16.0),
            vertical: 12,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/sougou_icon.png',
                  width: ResponsiveHelper.respSize(context, 32),
                  height: ResponsiveHelper.respSize(context, 32),
                  fit: BoxFit.cover,
                ),
              ),
              SizedBox(width: ResponsiveHelper.respPadding(context, 10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'サクサク過去問',
                      style: TextStyle(
                        fontSize: ResponsiveHelper.respFontSize(context, 10),
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '過去問・例題ベースの問題集が新登場',
                      style: TextStyle(
                        fontSize: ResponsiveHelper.respFontSize(context, 12),
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.launch,
                color: Colors.grey,
                size: ResponsiveHelper.respIconSize(context, 16),
              ),
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
  final bool showAnswerExplanation;

  const ResultPage({
    super.key,
    required this.score,
    required this.total,
    required this.history,
    required this.incorrectQuizzes,
    required this.originalQuizzes,
    this.categoryKey,
    required this.isWeaknessReview,
    required this.showAnswerExplanation,
  });

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  Set<String> _bookmarkedQuestions = {};
  late final ScrollController _scrollController;
  double _collapseProgress = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleScroll);
    _loadBookmarks();
  }

  void _handleScroll() {
    final next = (_scrollController.offset / 120).clamp(0.0, 1.0);
    if ((next - _collapseProgress).abs() < 0.01) return;
    setState(() => _collapseProgress = next);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadBookmarks() async {
    final bookmarked = await PrefsHelper.getBookmarkedQuestions();
    if (!mounted) return;
    setState(() {
      _bookmarkedQuestions = bookmarked.toSet();
    });
  }

  Future<void> _toggleBookmark(Quiz quiz) async {
    final isBookmarked = _bookmarkedQuestions.contains(quiz.question);
    if (isBookmarked) {
      await PrefsHelper.removeBookmarkedQuestions([quiz.question]);
    } else {
      await PrefsHelper.addBookmarkedQuestions([quiz.question]);
    }
    if (!mounted) return;
    setState(() {
      if (isBookmarked)
        _bookmarkedQuestions.remove(quiz.question);
      else
        _bookmarkedQuestions.add(quiz.question);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.backgroundTop, AppColors.backgroundBottom],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            // 1. SafeArea内
            child: Column(
              children: [
                // -----------------------------------------------------------------
                // 1. 上部エリア
                // -----------------------------------------------------------------
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SizedBox(height: 60, child: AdBanner(adKey: 'result')),
                ),

                _CollapsingResultSummary(
                  score: widget.score,
                  total: widget.total,
                  message: widget.score == widget.total
                      ? 'PERFECT! 🎉'
                      : widget.score >= 8
                      ? '合格圏内！素晴らしい！'
                      : widget.score / widget.total >= 0.5
                      ? 'もう少し！頑張ろう！'
                      : 'まだまだ復習が必要！',
                  collapseProgress: _collapseProgress,
                ),

                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: widget.history.length,
                    itemBuilder: (context, index) {
                      final item = widget.history[index];
                      final Quiz quiz = item['quiz'];
                      final bool isCorrect = item['result'];
                      final bool isBookmarked = _bookmarkedQuestions.contains(
                        quiz.question,
                      );

                      return Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: double.infinity,
                            maxWidth:
                                ResponsiveHelper.respCardWidth(context) ??
                                double.infinity,
                          ),
                          child: SoftSurface(
                            margin: const EdgeInsets.only(bottom: 12),
                            borderRadius: BorderRadius.circular(22),
                            borderColor: AppColors.line.withValues(alpha: 0.78),
                            fillColor: Colors.white.withValues(alpha: 0.98),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        isCorrect
                                            ? Icons.check_circle_rounded
                                            : Icons.cancel_rounded,
                                        color: isCorrect
                                            ? AppColors.success
                                            : AppColors.error,
                                        size: 28,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              quiz.question,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16,
                                                color: AppColors.ink,
                                                height: 1.42,
                                              ),
                                            ),
                                            if (quiz.imagePath != null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 4,
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.image_outlined,
                                                      size: 16,
                                                      color: Colors.grey[500],
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      "画像問題",
                                                      style: TextStyle(
                                                        color: Colors.grey[500],
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        onPressed: () => _toggleBookmark(quiz),
                                        icon: Icon(
                                          isBookmarked
                                              ? Icons.bookmark_rounded
                                              : Icons.bookmark_border_rounded,
                                          color: isBookmarked
                                              ? AppColors.warning
                                              : AppColors.inkMuted,
                                        ),
                                        tooltip: isBookmarked
                                            ? 'ブックマーク解除'
                                            : 'ブックマーク',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceMuted,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text(
                                      "💡 ${quiz.explanation}",
                                      style: TextStyle(
                                        color: AppColors.ink,
                                        fontSize: ResponsiveHelper.respFontSize(
                                          context,
                                          13,
                                        ),
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                  color: AppColors.backgroundBottom.withValues(alpha: 0.6),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: double.infinity,
                        maxWidth:
                            ResponsiveHelper.respCardWidth(context) ??
                            double.infinity,
                      ),
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
                                              totalQuestions: widget
                                                  .incorrectQuizzes
                                                  .length,
                                              showAnswerExplanation:
                                                  widget.showAnswerExplanation,
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.menu_book_rounded),
                                      label: const Text("ミスを確認"),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
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
                                      if (widget.isWeaknessReview) {
                                        Navigator.of(
                                          context,
                                        ).popUntil((route) => route.isFirst);
                                        return;
                                      }

                                      final shuffledAgain = List<Quiz>.from(
                                        widget.originalQuizzes,
                                      )..shuffle();
                                      Navigator.of(context).pushReplacement(
                                        MaterialPageRoute(
                                          builder: (context) => QuizPage(
                                            quizzes: shuffledAgain,
                                            categoryKey: widget.categoryKey,
                                            totalQuestions:
                                                shuffledAgain.length,
                                            showAnswerExplanation:
                                                widget.showAnswerExplanation,
                                          ),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.blueAccent,
                                      elevation: 0,
                                      side: const BorderSide(
                                        color: Colors.blueAccent,
                                        width: 2,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    child: Text(
                                      widget.isWeaknessReview
                                          ? "ホームに戻る"
                                          : "リトライ",
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // ホームに戻るリンク
                          TextButton(
                            onPressed: () {
                              Navigator.of(
                                context,
                              ).popUntil((route) => route.isFirst);
                            },
                            child: const Text(
                              "ホームに戻る",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ), // Container (gradient)
      ),
    );
  }
}
