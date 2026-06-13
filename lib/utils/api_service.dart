import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/app_data.dart';
import 'prefs_helper.dart';
import '../config/gas_config.dart';

class ApiService {
  static String get _baseUrl => GasConfig.baseUrl;

  AppData? _parseUsableAppData(String jsonString, String appId) {
    try {
      final decoded = json.decode(jsonString) as Map<String, dynamic>;
      if (decoded.containsKey('error')) {
        debugPrint('ApiService: API returned error for $appId: ${decoded['error']}');
        return null;
      }

      final appData = AppData.fromJson(decoded);
      if (appData.config.appId.isNotEmpty && appData.config.appId != appId) {
        debugPrint(
          'ApiService: App id mismatch. expected=$appId actual=${appData.config.appId}',
        );
        return null;
      }
      if (appData.questions.isEmpty) {
        debugPrint('ApiService: Empty question set for $appId');
        return null;
      }
      return appData;
    } catch (e) {
      debugPrint('ApiService: Parse error - $e');
      return null;
    }
  }

  // キャッシュ優先で即座に返す（ネットワーク不使用）
  Future<AppData?> loadFromCacheOrFallback(String appId) async {
    final cachedJson = await PrefsHelper.getAppDataCache();
    if (cachedJson != null) {
      final data = _parseUsableAppData(cachedJson, appId);
      if (data != null) return data;
      debugPrint('ApiService: Cache invalid, falling back to asset');
    }

    if (kDebugMode) debugPrint('ApiService: Using bundled fallback for $appId');
    try {
      final assetString = await rootBundle.loadString('assets/fallback_data.json');
      return _parseUsableAppData(assetString, appId);
    } catch (e) {
      debugPrint('ApiService: Fallback asset error - $e');
    }

    return null;
  }

  // バックグラウンドでGASから取得しキャッシュを更新（次回起動に反映）
  void refreshInBackground(String appId) {
    _fetchAndCache(appId);
  }

  Future<void> _fetchAndCache(String appId) async {
    try {
      final url = Uri.parse('$_baseUrl?id=$appId');
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = _parseUsableAppData(response.body, appId);
        if (data != null) {
          await PrefsHelper.saveAppDataCache(response.body);
          debugPrint('ApiService: Background refresh successful');
        } else {
          debugPrint('ApiService: Background refresh returned invalid data, cache not updated');
        }
      }
    } catch (e) {
      debugPrint('ApiService: Background refresh failed - $e');
    }
  }
}
