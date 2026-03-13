import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';

import 'package:appinio_swiper/appinio_swiper.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'widgets/ad_banner.dart';
import 'utils/ad_manager.dart';
import 'utils/purchase_manager.dart';
import 'widgets/premium_unlock_card.dart';
import 'widgets/special_offer_dialog.dart';
import 'widgets/premium_upgrade_dialog.dart';
import 'widgets/mode_toggle.dart';
import 'widgets/category_review_modal.dart';
import 'utils/prefs_helper.dart';
import 'package:url_launcher/url_launcher.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Lock orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Initialize Purchase Manager
  await PurchaseManager.instance.initialize();
  
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
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E293B),
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

class _HomePageState extends State<HomePage> {
  int _weaknessCount = 0;
  bool _isLoading = true;
  QuizMode _currentMode = QuizMode.shuffle;

  @override
  void initState() {
    super.initState();
    _initializeApp();
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
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _loadUserData() async {
    final weakList = await PrefsHelper.getWeakQuestions();
    if (mounted) {
      setState(() {
        _weaknessCount = weakList.length;
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
    List<Quiz> quizzes;
    String highScoreKey;
    switch(partKey) {
      case 'part1': quizzes = QuizData.part1; highScoreKey = 'highscore_part1'; break;
      case 'part2': quizzes = QuizData.part2; highScoreKey = 'highscore_part2'; break;
      case 'part3': quizzes = QuizData.part3; highScoreKey = 'highscore_part3'; break;
      case 'part4': quizzes = QuizData.part4; highScoreKey = 'highscore_part4'; break;

      default: quizzes = []; highScoreKey = '';
    }
    
    if (quizzes.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('問題データがまだありません')),
       );
       return;
    }
    _startQuiz(
      context, 
      quizzes, 
      highScoreKey, 
      isRandom10: _currentMode == QuizMode.shuffle
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("潜水士試験対策"),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  const Text(
                    "スキマ時間でサクサク合格！一問一答",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Mode Toggle
                  ValueListenableBuilder<bool>(
                    valueListenable: PurchaseManager.instance.isPremium,
                    builder: (context, isPremium, child) {
                      return ModeToggle(
                        currentMode: _currentMode,
                        isPremium: isPremium,
                        onModeChanged: (mode) {
                          setState(() {
                            _currentMode = mode;
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 24),

                  // Part 1: 潜水業務
                  _MenuButton(
                    title: "潜水業務",
                    icon: Icons.waves,
                    iconColor: Colors.blueAccent,
                    onTap: () => _startQuizByCategory(context, 'part1'),
                  ),
                  const SizedBox(height: 12),

                  // Part 2: 送気、潜降及び浮上
                  _MenuButton(
                    title: "送気、潜降及び浮上",
                    icon: Icons.arrow_downward,
                    iconColor: Colors.orange,
                    onTap: () => _startQuizByCategory(context, 'part2'),
                  ),
                  const SizedBox(height: 12),

                  // Part 3: 高気圧障害
                  _MenuButton(
                    title: "高気圧障害",
                    icon: Icons.medical_services,
                    iconColor: Colors.redAccent,
                    onTap: () => _startQuizByCategory(context, 'part3'),
                  ),
                  const SizedBox(height: 12),

                  // Part 4: 関係法令
                  _MenuButton(
                    title: "関係法令",
                    icon: Icons.gavel,
                    iconColor: Colors.green,
                    onTap: () => _startQuizByCategory(context, 'part4'),
                  ),
                  const SizedBox(height: 40),

                  // Weakness Review
                  ElevatedButton.icon(
                    onPressed: _weaknessCount > 0 ? () => _startWeaknessReview(context) : null,
                    icon: const Icon(Icons.refresh),
                    label: Text("苦手を復習する ($_weaknessCount問)"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 4,
                      shadowColor: Colors.redAccent.withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Sister App Promotion
                  ValueListenableBuilder<bool>(
                    valueListenable: PurchaseManager.instance.isPremium,
                    builder: (context, isPremium, child) {
                      if (isPremium) return const SizedBox.shrink();
                      return const Column(
                        children: [
                          _SisterAppPromotion(),
                          SizedBox(height: 40),
                        ],
                      );
                    },
                  ),

                  const PremiumUnlockCard(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
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
  final int totalQuestions;

  const QuizPage({
    super.key,
    required this.quizzes,
    this.categoryKey,
    this.isWeaknessReview = false,
    required this.totalQuestions,
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
  Color _backgroundColor = const Color(0xFFF1F5F9);

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
          _backgroundColor = Colors.green.withValues(alpha: 0.2);
          HapticFeedback.lightImpact();
          
          if (widget.isWeaknessReview) {
            _correctQuizzesInReview.add(quiz);
          }
        } else {
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
    if (widget.categoryKey != null) {
      await PrefsHelper.saveHighScore(widget.categoryKey!, _score);
    }

    if (_incorrectQuizzes.isNotEmpty) {
      final incorrectTexts = _incorrectQuizzes.map((q) => q.question).toList();
      await PrefsHelper.addWeakQuestions(incorrectTexts);
    }

    if (widget.isWeaknessReview && _correctQuizzesInReview.isNotEmpty) {
      final correctTexts = _correctQuizzesInReview.map((q) => q.question).toList();
      await PrefsHelper.removeWeakQuestions(correctTexts);
    }
    
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
  }

  Widget _buildCard(Quiz quiz) {
    bool hasImage = quiz.imagePath != null;

    return Container(
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
                      fontSize: 40,
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
                        fontSize: hasImage ? 24 : 32,
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
          
           const Padding(
            padding: EdgeInsets.only(left: 40.0, right: 40.0, bottom: 40.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  children: [
                    Icon(Icons.close, color: Colors.redAccent, size: 48),
                    Text("誤り", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
                Column(
                  children: [
                    Icon(Icons.circle_outlined, color: Colors.green, size: 48),
                    Text("正しい", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
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

  Future<void> _launchURL(BuildContext context) async {
    final Uri url = Uri.parse('https://apps.apple.com/app/id6758617558');
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                 Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    image: const DecorationImage(
                      image: AssetImage('assets/sister_app_icon.jpg'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "選択問題版のアプリが登場！",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "App Storeを開いて、\n姉妹アプリのページに移動します。",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text("キャンセル", style: TextStyle(color: Colors.grey)),
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
                                const SnackBar(content: Text('URLを開けませんでした')),
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
                        child: const Text("開く", style: TextStyle(fontWeight: FontWeight.bold)),
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
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _launchURL(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
               ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/sister_app_icon.jpg',
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 60,
                      height: 60,
                      color: Colors.grey[200],
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "選択問題版のアプリが登場！",
                          style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "5択問題で実力試し！\n姉妹アプリはこちら",
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, height: 1.4),
                        ),
                      ],
                    ),
                  ),
              const Icon(Icons.launch, color: Colors.grey),
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

class ResultPage extends StatelessWidget {
  final int score;
  final int total;
  final List<Map<String, dynamic>> history;
  final List<Quiz> incorrectQuizzes;
  final List<Quiz> originalQuizzes;
  final String? categoryKey;
  final bool isWeaknessReview;

  const ResultPage({
    super.key,
    required this.score,
    required this.total,
    required this.history,
    required this.incorrectQuizzes,
    required this.originalQuizzes,
    this.categoryKey,
    required this.isWeaknessReview,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea( // 1. SafeArea内
        child: Column(
          children: [
            // -----------------------------------------------------------------
            // 1. 上部エリア
            // -----------------------------------------------------------------
            const AdBanner(adKey: 'result'), // 一番上に広告バナー

            Container(
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
                      Text(
                        "$score/$total", // 9/10のようなスコア
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w900, // 太字
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  
                  if (score == total)
                    const Text(
                      "PERFECT! 🎉",
                      style: TextStyle(fontSize: 20, color: Colors.green, fontWeight: FontWeight.bold),
                    )
                  else
                    Text(
                      score >= 8 ? "合格圏内！素晴らしい！" : "あと少し！復習しよう",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: score >= 8 ? Colors.green : Colors.red,
                      ),
                    ),
                ],
              ),
            ),

            // -----------------------------------------------------------------
            // 2. 中央エリア（スクロール可能なリスト）
            // -----------------------------------------------------------------
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: history.length,
                itemBuilder: (context, index) {
                  final item = history[index];
                  final Quiz quiz = item['quiz'];
                  final bool isCorrect = item['result'];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16), // 角丸16px
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
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.withValues(alpha: 0.05), // 薄い青灰色
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
                      if (incorrectQuizzes.isNotEmpty) ...[
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (context) => QuizPage(
                                      quizzes: incorrectQuizzes,
                                      isWeaknessReview: true,
                                      totalQuestions: incorrectQuizzes.length,
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
                              if (this.isWeaknessReview) {
                                Navigator.of(context).popUntil((route) => route.isFirst);
                                return;
                              }

                              final shuffledAgain = List<Quiz>.from(this.originalQuizzes)..shuffle();
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (context) => QuizPage(
                                    quizzes: shuffledAgain,
                                    categoryKey: this.categoryKey,
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
                            child: Text(isWeaknessReview ? "ホームに戻る" : "リトライ"),
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
