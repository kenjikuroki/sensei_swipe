import 'dart:io';

class AppConfig {
  final bool saleEnabled;
  final DateTime? saleEndDate;
  final String adBannerId;
  final String adInterstitialId;
  final String appTitle;
  final String nextAppText;
  final String nextAppUrl;
  final int regularPrice;
  final int salePrice;
  final bool nextAppEnabled;
  final String premiumProductId;
  final String platformAppId;
  final String appId;
  final String feedbackUrl;

  AppConfig({
    required this.saleEnabled,
    this.saleEndDate,
    required this.adBannerId,
    required this.adInterstitialId,
    required this.appTitle,
    required this.nextAppText,
    required this.nextAppUrl,
    required this.regularPrice,
    required this.salePrice,
    required this.nextAppEnabled,
    required this.premiumProductId,
    required this.platformAppId,
    required this.appId,
    this.feedbackUrl = '',
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    String normalizeConfigValue(dynamic value) {
      final normalized = value?.toString().trim() ?? '';
      final lower = normalized.toLowerCase();
      if (normalized.isEmpty || lower == 'nan' || lower == 'null') {
        return '';
      }
      return normalized;
    }

    DateTime? endDate;
    if (json['sale_end_date'] != null &&
        json['sale_end_date'].toString().isNotEmpty) {
      endDate = DateTime.tryParse(json['sale_end_date'].toString());
    }

    // Platform specific fields
    String banner = '';
    String inter = '';
    String nextUrl = '';
    String premiumId = '';
    String platformId = '';

    if (Platform.isIOS) {
      banner = normalizeConfigValue(json['ios_ad_banner']);
      inter = normalizeConfigValue(json['ios_ad_inter']);
      nextUrl = normalizeConfigValue(json['ios_next_app_url']);
      premiumId = normalizeConfigValue(json['ios_premium_id']);
      platformId = normalizeConfigValue(json['ios_id']);
    } else {
      banner = normalizeConfigValue(
        json['android_ad_banner'] ?? json['andoroid_ad_banner'],
      );
      inter = normalizeConfigValue(
        json['android_ad_inter'] ?? json['andoroid_ad_inter'],
      );
      nextUrl = normalizeConfigValue(
        json['android_next_app_url'] ?? json['andoroid_next_app_url'],
      );
      premiumId = normalizeConfigValue(
        json['android_premium_id'] ?? json['andoroid_premium_id'],
      );
      platformId = normalizeConfigValue(
        json['android_id'] ?? json['andoroid_id'],
      );
    }

    return AppConfig(
      saleEnabled:
          json['sale_enabled'] == true ||
          json['sale_enabled'] == 1 ||
          json['sale_enabled']?.toString() == '1',
      saleEndDate: endDate,
      adBannerId: banner,
      adInterstitialId: inter,
      appTitle: json['app_name']?.toString() ?? '',
      nextAppText: json['next_app_text']?.toString() ?? '',
      nextAppUrl: nextUrl,
      regularPrice:
          int.tryParse(json['regular_price']?.toString() ?? '') ?? 390,
      salePrice: int.tryParse(json['sale_price']?.toString() ?? '') ?? 190,
      nextAppEnabled:
          json['next_app_enabled'] == true ||
          json['next_app_enabled'] == 1 ||
          json['next_app_enabled']?.toString() == '1',
      premiumProductId: premiumId,
      platformAppId: platformId,
      appId: json['app_id']?.toString() ?? '',
      feedbackUrl: json['feedback_url']?.toString() ?? '',
    );
  }

  bool get isSaleActive {
    if (!saleEnabled) return false;
    if (saleEndDate == null) return true;
    return DateTime.now().isBefore(saleEndDate!);
  }
}

class Quiz {
  final String question;
  final bool isCorrect;
  final String explanation;
  final String? imagePath;
  final String category;

  Quiz({
    required this.question,
    required this.isCorrect,
    required this.explanation,
    this.imagePath,
    required this.category,
  });

  factory Quiz.fromJson(Map<String, dynamic> json) {
    dynamic img = json['image_path'];
    String? finalImg;
    if (img != null && img != 'null' && img != '') {
      finalImg = img.toString();
    }

    // Handle is_correct as "〇" / "×" or bool or int
    bool correctValue = false;
    dynamic rawCorrect = json['is_correct'] ?? json['isCorrect'];
    if (rawCorrect == '〇' || rawCorrect == '○') {
      correctValue = true;
    } else if (rawCorrect == '×' || rawCorrect == 'x' || rawCorrect == 'X') {
      correctValue = false;
    } else if (rawCorrect is bool) {
      correctValue = rawCorrect;
    } else if (rawCorrect is num) {
      correctValue = rawCorrect == 1;
    }

    return Quiz(
      question: (json['question'] as String? ?? '').replaceAll('\n', ''),
      isCorrect: correctValue,
      explanation: json['explanation'] as String? ?? '',
      imagePath: finalImg,
      category: json['category'] as String? ?? '',
    );
  }
}

class AppData {
  final AppConfig config;
  final Map<String, List<Quiz>> questions;
  final List<String> categoryOrder;

  AppData({
    required this.config,
    required this.questions,
    required this.categoryOrder,
  });

  factory AppData.fromJson(Map<String, dynamic> json) {
    final configMap = json['config'] as Map<String, dynamic>? ?? {};
    final questionsList = json['questions'] as List<dynamic>? ?? [];

    Map<String, List<Quiz>> groupedQuestions = {};
    List<String> categoryOrder = [];

    for (var qJson in questionsList) {
      final quiz = Quiz.fromJson(qJson as Map<String, dynamic>);
      String category = quiz.category.trim();
      if (category.isEmpty) category = 'その他';

      if (!groupedQuestions.containsKey(category)) {
        groupedQuestions[category] = [];
        categoryOrder.add(category);
      }
      groupedQuestions[category]!.add(quiz);
    }

    return AppData(
      config: AppConfig.fromJson(configMap),
      questions: groupedQuestions,
      categoryOrder: categoryOrder,
    );
  }
}
