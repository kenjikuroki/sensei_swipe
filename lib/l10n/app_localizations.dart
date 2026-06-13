import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In ja, this message translates to:
  /// **'運行管理者 貨物'**
  String get appTitle;

  /// No description provided for @quizSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'スキマ時間でサクサク合格！一問一答形式'**
  String get quizSubtitle;

  /// No description provided for @modeShuffle.
  ///
  /// In ja, this message translates to:
  /// **'シャッフル'**
  String get modeShuffle;

  /// No description provided for @modeSequential.
  ///
  /// In ja, this message translates to:
  /// **'順番通り'**
  String get modeSequential;

  /// No description provided for @lockModeSequential.
  ///
  /// In ja, this message translates to:
  /// **'このモードはロックされています'**
  String get lockModeSequential;

  /// No description provided for @premiumUpgrade.
  ///
  /// In ja, this message translates to:
  /// **'プレミアムアップグレード'**
  String get premiumUpgrade;

  /// No description provided for @featureSequentialTitle.
  ///
  /// In ja, this message translates to:
  /// **'「連続」モードの解放'**
  String get featureSequentialTitle;

  /// No description provided for @featureSequentialDesc.
  ///
  /// In ja, this message translates to:
  /// **'1問目から順番にすべての問題を解くことができます。'**
  String get featureSequentialDesc;

  /// No description provided for @featureNoAdsTitle.
  ///
  /// In ja, this message translates to:
  /// **'広告を完全に非表示'**
  String get featureNoAdsTitle;

  /// No description provided for @featureNoAdsDesc.
  ///
  /// In ja, this message translates to:
  /// **'アプリ内のあらゆる広告を非表示にします。'**
  String get featureNoAdsDesc;

  /// No description provided for @purchase.
  ///
  /// In ja, this message translates to:
  /// **'購入する'**
  String get purchase;

  /// No description provided for @cancel.
  ///
  /// In ja, this message translates to:
  /// **'キャンセル'**
  String get cancel;

  /// No description provided for @reviewWeakness.
  ///
  /// In ja, this message translates to:
  /// **'苦手を復習する ({count}問)'**
  String reviewWeakness(int count);

  /// No description provided for @selectCategory.
  ///
  /// In ja, this message translates to:
  /// **'カテゴリーを選択'**
  String get selectCategory;

  /// No description provided for @noData.
  ///
  /// In ja, this message translates to:
  /// **'問題データがまだありません'**
  String get noData;

  /// No description provided for @back.
  ///
  /// In ja, this message translates to:
  /// **'元に戻す'**
  String get back;

  /// No description provided for @questionNumber.
  ///
  /// In ja, this message translates to:
  /// **'第{index}問'**
  String questionNumber(int index);

  /// No description provided for @questionsCount.
  ///
  /// In ja, this message translates to:
  /// **'{count}問'**
  String questionsCount(int count);

  /// No description provided for @part1.
  ///
  /// In ja, this message translates to:
  /// **'一般知識'**
  String get part1;

  /// No description provided for @part2.
  ///
  /// In ja, this message translates to:
  /// **'安全・機材'**
  String get part2;

  /// No description provided for @part3.
  ///
  /// In ja, this message translates to:
  /// **'清掃方法'**
  String get part3;

  /// No description provided for @part4.
  ///
  /// In ja, this message translates to:
  /// **'建物管理'**
  String get part4;

  /// No description provided for @premiumCardTitle.
  ///
  /// In ja, this message translates to:
  /// **'プレミアムプランに\nアップグレード'**
  String get premiumCardTitle;

  /// No description provided for @premiumCardSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'広告を非表示にして集中！'**
  String get premiumCardSubtitle;

  /// No description provided for @restorePurchase.
  ///
  /// In ja, this message translates to:
  /// **'購入を復元する'**
  String get restorePurchase;

  /// No description provided for @sisterAppPromoTitle.
  ///
  /// In ja, this message translates to:
  /// **'別の資格にもチャレンジ！'**
  String get sisterAppPromoTitle;

  /// No description provided for @sisterAppPromoSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'別の資格にもチャレンジ！\n詳細はこちらから'**
  String get sisterAppPromoSubtitle;

  /// No description provided for @sisterAppDialogTitle.
  ///
  /// In ja, this message translates to:
  /// **'別の資格にもチャレンジ！'**
  String get sisterAppDialogTitle;

  /// No description provided for @sisterAppDialogBody.
  ///
  /// In ja, this message translates to:
  /// **'App Storeを開いて、\n姉妹アプリのページに移動します。'**
  String get sisterAppDialogBody;

  /// No description provided for @open.
  ///
  /// In ja, this message translates to:
  /// **'開く'**
  String get open;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
