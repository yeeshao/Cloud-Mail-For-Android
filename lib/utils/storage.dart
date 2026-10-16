import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // ===== 本地已读覆盖 =====
  // 某些服务端接口没有提供“标记已读”接口，或列表接口的已读状态同步滞后。
  // 用户打开邮件后在本机持久记录已读状态，避免返回列表/刷新后蓝点又出现。
  static const String _localReadEmailIdsKey = 'localReadEmailIds';

  static Set<int> getLocalReadEmailIds() {
    final raw = _prefs?.getString(_localReadEmailIdsKey);
    if (raw == null || raw.isEmpty) return <int>{};
    try {
      return (jsonDecode(raw) as List)
          .map((value) => int.tryParse(value.toString()))
          .whereType<int>()
          .toSet();
    } catch (_) {
      return <int>{};
    }
  }

  static bool isLocallyReadEmail(int emailId) =>
      getLocalReadEmailIds().contains(emailId);

  static void markEmailAsLocallyRead(int emailId) {
    if (emailId <= 0) return;
    final ids = getLocalReadEmailIds()..add(emailId);
    // 控制存储规模，保留最近标记的 5000 封邮件。
    final values = ids.toList();
    if (values.length > 5000) {
      values.removeRange(0, values.length - 5000);
    }
    _prefs?.setString(_localReadEmailIdsKey, jsonEncode(values));
  }

  // ===== 邮件列表缓存 =====
  // 按 "folder:accountId" 维度缓存首页邮件列表（JSON 字符串）
  // 设计：进入页面立刻用缓存渲染，后台再拉取最新数据替换

  static String? _cacheKey(String folder, int? accountId) =>
      'mailCache:$folder:${accountId ?? 'all'}';

  /// 读取某文件夹的缓存邮件列表，返回 null 表示无缓存
  static List<Map<String, dynamic>>? getMailCache(String folder, int? accountId) {
    final raw = _prefs?.getString(_cacheKey(folder, accountId)!);
    if (raw == null || raw.isEmpty) return null;
    try {
      final list = jsonDecode(raw) as List;
      // 用 Map<String, dynamic>.from 做一次安全转换，避免类型不匹配
      return list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// 写入缓存
  static void setMailCache(String folder, int? accountId, List<Map<String, dynamic>> emails) {
    _prefs?.setString(_cacheKey(folder, accountId)!, jsonEncode(emails));
  }

  /// 清空所有邮件缓存
  static void clearAllMailCache() {
    final keys = _prefs?.getKeys() ?? <String>{};
    for (final k in keys) {
      if (k.startsWith('mailCache:')) {
        _prefs?.remove(k);
      }
    }
  }

  static String? get token => _prefs?.getString('token');
  static set token(String? value) {
    if (value != null) {
      _prefs?.setString('token', value);
    } else {
      _prefs?.remove('token');
    }
  }

  static String? get email => _prefs?.getString('email');
  static set email(String? value) {
    if (value != null) {
      _prefs?.setString('email', value);
    } else {
      _prefs?.remove('email');
    }
  }

  static String? get baseUrl => _prefs?.getString('baseUrl');
  static set baseUrl(String? value) {
    if (value != null) {
      _prefs?.setString('baseUrl', value);
    } else {
      _prefs?.remove('baseUrl');
    }
  }

  static int? get currentAccountId => _prefs?.getInt('currentAccountId');
  static set currentAccountId(int? value) {
    if (value != null) {
      _prefs?.setInt('currentAccountId', value);
    } else {
      _prefs?.remove('currentAccountId');
    }
  }

  static String get themeMode => _prefs?.getString('themeMode') ?? 'system';
  static set themeMode(String value) {
    _prefs?.setString('themeMode', value);
  }

  /// UI 风格：'google' | 'apple'，默认 'google'
  static String get uiStyle => _prefs?.getString('uiStyle') ?? 'google';
  static set uiStyle(String value) {
    _prefs?.setString('uiStyle', value);
  }

  /// 记住登录状态
  static bool get rememberLogin => _prefs?.getBool('rememberLogin') ?? true;
  static set rememberLogin(bool value) {
    _prefs?.setBool('rememberLogin', value);
  }

  static bool get showSenderAvatar => _prefs?.getBool('showSenderAvatar') ?? true;
  static set showSenderAvatar(bool value) {
    _prefs?.setBool('showSenderAvatar', value);
  }

  static bool get autoLoadImages => _prefs?.getBool('autoLoadImages') ?? true;
  static set autoLoadImages(bool value) {
    _prefs?.setBool('autoLoadImages', value);
  }

  /// 邮件列表滑动操作（左滑删除/右滑星标），默认开启
  static bool get swipeActionsEnabled => _prefs?.getBool('swipeActionsEnabled') ?? true;
  static set swipeActionsEnabled(bool value) {
    _prefs?.setBool('swipeActionsEnabled', value);
  }

  static String? get openaiApiKey => _prefs?.getString('openaiApiKey');
  static set openaiApiKey(String? value) {
    if (value != null) {
      _prefs?.setString('openaiApiKey', value);
    } else {
      _prefs?.remove('openaiApiKey');
    }
  }

  static String? get openaiBaseUrl => _prefs?.getString('openaiBaseUrl');
  static set openaiBaseUrl(String? value) {
    if (value != null) {
      _prefs?.setString('openaiBaseUrl', value);
    } else {
      _prefs?.remove('openaiBaseUrl');
    }
  }

  static String? get openaiModel => _prefs?.getString('openaiModel');
  static set openaiModel(String? value) {
    if (value != null) {
      _prefs?.setString('openaiModel', value);
    } else {
      _prefs?.remove('openaiModel');
    }
  }

  static String? get lastCheckUpdateTime => _prefs?.getString('lastCheckUpdateTime');
  static set lastCheckUpdateTime(String? value) {
    if (value != null) {
      _prefs?.setString('lastCheckUpdateTime', value);
    } else {
      _prefs?.remove('lastCheckUpdateTime');
    }
  }

  // ===== 个性化配置 =====
  // 自定义主题色（ARGB 整数），null 表示用默认
  static int? get customPrimaryColor => _prefs?.getInt('customPrimaryColor');
  static set customPrimaryColor(int? value) {
    if (value != null) {
      _prefs?.setInt('customPrimaryColor', value);
    } else {
      _prefs?.remove('customPrimaryColor');
    }
  }

  // 自定义字体家族名，null 表示用默认
  static String? get customFontFamily => _prefs?.getString('customFontFamily');
  static set customFontFamily(String? value) {
    if (value != null) {
      _prefs?.setString('customFontFamily', value);
    } else {
      _prefs?.remove('customFontFamily');
    }
  }

  // 用户导入的自定义字体文件路径（持久化到文档目录），null 表示无
  static String? get customFontPath => _prefs?.getString('customFontPath');
  static set customFontPath(String? value) {
    if (value != null) {
      _prefs?.setString('customFontPath', value);
    } else {
      _prefs?.remove('customFontPath');
    }
  }

  // 自定义背景图本地路径，null 表示无
  static String? get customBackgroundImage => _prefs?.getString('customBackgroundImage');
  static set customBackgroundImage(String? value) {
    if (value != null) {
      _prefs?.setString('customBackgroundImage', value);
    } else {
      _prefs?.remove('customBackgroundImage');
    }
  }

  // ===== 更新镜像源 =====
  // 自定义/内置的下载镜像源列表（JSON 数组字符串）
  // 规则：'direct' 表示直连，其他为 URL 前缀（如 'https://ghproxy.com/'）
  static List<String> getUpdateMirrors() {
    final raw = _prefs?.getString('updateMirrors');
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  static void setUpdateMirrors(List<String> mirrors) {
    _prefs?.setString('updateMirrors', jsonEncode(mirrors));
  }

  // ===== WebDAV 配置（JSON 字符串）=====
  static String? get webdavConfig => _prefs?.getString('webdavConfig');
  static set webdavConfig(String? value) {
    if (value != null) {
      _prefs?.setString('webdavConfig', value);
    } else {
      _prefs?.remove('webdavConfig');
    }
  }

  // AI 对话历史（JSON 字符串）
  static String? get chatHistory => _prefs?.getString('chatHistory');
  static set chatHistory(String? value) {
    if (value != null) {
      _prefs?.setString('chatHistory', value);
    } else {
      _prefs?.remove('chatHistory');
    }
  }

  static void clear() {
    _prefs?.remove('token');
    _prefs?.remove('email');
    _prefs?.remove('currentAccountId');
    _prefs?.remove(_localReadEmailIdsKey);
  }
}

class ErrorMessages {
  static const List<String> connectionErrors = [
    '网断啦！检查一下你的 WiFi 是不是在摸鱼 🐟',
    '服务器失联了...它可能去度假了 🏖️',
    '网络离家出走了，请先把它找回来 🌐',
  ];

  static const List<String> timeoutErrors = [
    '服务器在发呆，等太久啦 ⏰',
    '请求超时！服务器可能在思考人生 🤔',
    '响应太慢了，比蜗牛还慢 🐌',
  ];

  static const List<String> authErrors = [
    '登录过期了，重新登一下吧~ 🔐',
    '认证失败！你的身份成谜 🕵️',
    '邮箱或密码不对哦，再想想？ 🤨',
  ];

  static const List<String> serverErrors = [
    '服务器炸了，请稍后再试 💥',
    '服务器内部出了点小状况 🤯',
    '后端小哥正在抢修中... 🛠️',
  ];

  static const List<String> unknownErrors = [
    '发生了一些奇怪的事情 🤪',
    '啊哦，出问题了，但我不知道为啥 😅',
    '未知错误，玄学范畴 🎲',
  ];

  static final _random = Random();

  static String _pickRandom(List<String> list) =>
      list[_random.nextInt(list.length)];

  static String getConnection() => _pickRandom(connectionErrors);

  static String getTimeout() => _pickRandom(timeoutErrors);

  static String getAuth() => _pickRandom(authErrors);

  static String getServer() => _pickRandom(serverErrors);

  static String getUnknown() => _pickRandom(unknownErrors);

  static String fromException(dynamic e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('connection') ||
        msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('connection refused') ||
        msg.contains('connection closed')) {
      return getConnection();
    }
    if (msg.contains('timeout') || msg.contains('timed out')) {
      return getTimeout();
    }
    if (msg.contains('401') ||
        msg.contains('unauthorized') ||
        msg.contains('forbidden') ||
        msg.contains('403')) {
      return getAuth();
    }
    if (msg.contains('500') || msg.contains('internal server')) {
      return getServer();
    }
    return '${getUnknown()}\n\n${e.toString()}';
  }
}
