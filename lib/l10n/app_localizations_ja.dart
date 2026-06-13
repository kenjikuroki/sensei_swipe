// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => '潜水士試験対策';

  @override
  String get quizSubtitle => 'スキマ時間でサクサク合格！一問一答形式';

  @override
  String get modeShuffle => 'シャッフル';

  @override
  String get modeSequential => '順番通り';

  @override
  String get lockModeSequential => 'このモードはロックされています';

  @override
  String get premiumUpgrade => 'プレミアムアップグレード';

  @override
  String get featureSequentialTitle => '「連続」モードの解放';

  @override
  String get featureSequentialDesc => '1問目から順番にすべての問題を解くことができます。';

  @override
  String get featureNoAdsTitle => '広告を完全に非表示';

  @override
  String get featureNoAdsDesc => 'アプリ内のあらゆる広告を非表示にします。';

  @override
  String get purchase => '購入する';

  @override
  String get cancel => 'キャンセル';

  @override
  String reviewWeakness(int count) {
    return '苦手を復習する ($count問)';
  }

  @override
  String get selectCategory => 'カテゴリーを選択';

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
  String get restorePurchase => '購入を復元する';

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
