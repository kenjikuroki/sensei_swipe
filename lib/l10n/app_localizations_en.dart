// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Cargo Manager';

  @override
  String get quizSubtitle => 'スキマ時間でサクサク合格！一問一答形式';

  @override
  String get modeShuffle => 'シャッフル';

  @override
  String get modeSequential => '順番通り';

  @override
  String get lockModeSequential => 'このモードはロックされています';

  @override
  String get premiumUpgrade => 'Premium Upgrade';

  @override
  String get featureSequentialTitle => 'Unlock Sequential Mode';

  @override
  String get featureSequentialDesc =>
      'You can solve all questions in order from the first one.';

  @override
  String get featureNoAdsTitle => 'Completely Hide Ads';

  @override
  String get featureNoAdsDesc => 'Hides all ads in the app.';

  @override
  String get purchase => 'Purchase';

  @override
  String get cancel => 'Cancel';

  @override
  String reviewWeakness(int count) {
    return '苦手を復習する ($count問)';
  }

  @override
  String get selectCategory => 'Select Category';

  @override
  String get noData => '問題データがまだありません';

  @override
  String get back => '元に戻す';

  @override
  String questionNumber(int index) {
    return '第$index問';
  }

  @override
  String questionsCount(int count) {
    return '$count問';
  }

  @override
  String get part1 => '一般知識';

  @override
  String get part2 => '安全・機材';

  @override
  String get part3 => '清掃方法';

  @override
  String get part4 => '建物管理';

  @override
  String get premiumCardTitle => 'プレミアムプランに\nアップグレード';

  @override
  String get premiumCardSubtitle => '広告を非表示にして集中！';

  @override
  String get restorePurchase => 'Restore Purchase';

  @override
  String get sisterAppPromoTitle => '別の資格にもチャレンジ！';

  @override
  String get sisterAppPromoSubtitle => '別の資格にもチャレンジ！\n詳細はこちらから';

  @override
  String get sisterAppDialogTitle => '別の資格にもチャレンジ！';

  @override
  String get sisterAppDialogBody => 'App Storeを開いて、\n姉妹アプリのページに移動します。';

  @override
  String get open => '開く';
}
