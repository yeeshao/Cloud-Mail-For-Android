import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/email.dart';

class CloudMailApi {
  String baseUrl;
  String? token;

  CloudMailApi(this.baseUrl, {this.token});

  String _url(String path) {
    String url = baseUrl;
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!path.startsWith('/')) {
      path = '/$path';
    }
    // 所有 API 都在 /api 下
    if (!path.startsWith('/api')) {
      path = '/api$path';
    }
    return '$url$path';
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': token!,
      };

  /// 健壮的响应解析：处理非 JSON 响应、格式不匹配等情况
  ApiResponse<T> _parseResponse<T>(http.Response response, T Function(dynamic)? dataParser) {
    final bodyStr = utf8.decode(response.bodyBytes);
    try {
      final json = jsonDecode(bodyStr);
      if (json is! Map<String, dynamic>) {
        // 响应不是对象（可能是数组或原始值）
        return ApiResponse<T>(
          code: response.statusCode == 200 ? 200 : 0,
          message: '响应格式异常',
          data: null,
        );
      }
      return ApiResponse<T>.fromJson(json, dataParser);
    } catch (e) {
      // 响应不是 JSON（可能是 HTML 错误页）
      return ApiResponse<T>(
        code: response.statusCode,
        message: 'HTTP ${response.statusCode}: ${bodyStr.length > 200 ? bodyStr.substring(0, 200) : bodyStr}',
        data: null,
      );
    }
  }

  /// 登录 — POST /api/login，返回 JWT token
  /// 注意: 这是普通用户登录接口，不是 /api/public/genToken（那个是管理员生成 publicToken 用的）
  Future<ApiResponse<String>> login(String email, String password) async {
    final response = await http.post(
      Uri.parse(_url('/api/login')),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    return _parseResponse<String>(response, (data) => data['token'] as String);
  }

  /// 查询邮件列表 — GET /api/email/list（内部路由，需 JWT）
  /// 参数: emailId(游标), type, accountId, size, timeSort, allReceive
  /// 返回: {list: [...], total, latestEmail}
  Future<ApiResponse<EmailListResult>> getEmailList({
    int? accountId,
    int type = 0,
    int size = 20,
    int? emailId,
    int timeSort = 0,
    int? allReceive,
    String? toEmail,
    String? sendName,
    String? sendEmail,
    String? subject,
    String? content,
    int? isDel,
    int page = 1,
  }) async {
    final params = <String, String>{};
    if (accountId != null) params['accountId'] = accountId.toString();
    params['type'] = type.toString();
    params['size'] = size.toString();
    if (emailId != null) params['emailId'] = emailId.toString();
    params['timeSort'] = timeSort.toString();
    if (allReceive != null) params['allReceive'] = allReceive.toString();

    final uri = Uri.parse(_url('/email/list')).replace(queryParameters: params);
    final response = await http.get(uri, headers: _headers);

    return _parseResponse<EmailListResult>(response, (data) {
      // 内部 API 返回 {list: [...], total, latestEmail}
      if (data is Map<String, dynamic>) {
        final rawList = data['list'] as List? ?? [];
        final list = rawList
            .map((e) => Email.fromJson(e as Map<String, dynamic>))
            .toList();
        return EmailListResult(
          list: list,
          total: data['total'] ?? list.length,
          latestEmail: data['latestEmail'] != null
              ? Email.fromJson(data['latestEmail'] as Map<String, dynamic>)
              : (list.isNotEmpty ? list.first : null),
        );
      }
      // 兼容直接返回数组的情况
      if (data is List) {
        final list = data
            .map((e) => Email.fromJson(e as Map<String, dynamic>))
            .toList();
        return EmailListResult(
          list: list,
          total: list.length,
          latestEmail: list.isNotEmpty ? list.first : null,
        );
      }
      return EmailListResult(list: [], total: 0, latestEmail: null);
    });
  }

  /// 查询所有邮箱聚合邮件。与单账户列表使用相同的响应结构。
  /// 后端 allEmail/list 支持 type、游标和分页参数。
  Future<ApiResponse<EmailListResult>> getAllEmailList({
    int type = 0,
    int size = 20,
    int? emailId,
    int timeSort = 0,
    int? isDel,
  }) async {
    final params = <String, String>{
      'type': type.toString(),
      'size': size.toString(),
      'timeSort': timeSort.toString(),
      if (emailId != null) 'emailId': emailId.toString(),
      if (isDel != null) 'isDel': isDel.toString(),
    };
    final uri = Uri.parse(_url('/allEmail/list')).replace(queryParameters: params);
    final response = await http.get(uri, headers: _headers);
    return _parseResponse<EmailListResult>(response, (data) {
      final raw = data is Map<String, dynamic> ? (data['list'] as List? ?? []) : (data is List ? data : <dynamic>[]);
      final list = raw.whereType<Map>().map((e) => Email.fromJson(Map<String, dynamic>.from(e))).toList();
      return EmailListResult(
        list: list,
        total: data is Map<String, dynamic> ? (data['total'] as int? ?? list.length) : list.length,
        latestEmail: data is Map<String, dynamic> && data['latestEmail'] is Map
            ? Email.fromJson(Map<String, dynamic>.from(data['latestEmail'] as Map))
            : (list.isNotEmpty ? list.first : null),
      );
    });
  }

  Future<ApiResponse<List<Email>>> getLatestEmail({
    int? accountId,
    int type = 0,
    int? allReceive,
  }) async {
    final params = <String, String>{};
    if (accountId != null) params['accountId'] = accountId.toString();
    params['type'] = type.toString();
    if (allReceive != null) params['allReceive'] = allReceive.toString();

    final uri = Uri.parse(_url('/email/latest')).replace(queryParameters: params);
    final response = await http.get(uri, headers: _headers);

    return _parseResponse<List<Email>>(response, (data) {
      if (data is List) {
        return data.map((e) => Email.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    });
  }

  Future<ApiResponse> deleteEmails(String emailIds) async {
    final uri = Uri.parse(_url('/email/delete'))
        .replace(queryParameters: {'emailIds': emailIds});
    final response = await http.delete(uri, headers: _headers);
    return _parseResponse(response, null);
  }

  Future<ApiResponse<List<Email>>> sendEmail({
    required int accountId,
    required List<String> receiveEmail,
    required String subject,
    required String content,
    String? text,
    String? name,
    String sendType = 'new',
    int? emailId,
    List<Map<String, dynamic>>? attachments,
  }) async {
    final body = {
      'accountId': accountId,
      'receiveEmail': receiveEmail,
      'subject': subject,
      'content': content,
      if (text != null) 'text': text,
      if (name != null) 'name': name,
      'sendType': sendType,
      if (emailId != null) 'emailId': emailId,
      if (attachments != null) 'attachments': attachments,
    };

    final response = await http.post(
      Uri.parse(_url('/email/send')),
      headers: _headers,
      body: jsonEncode(body),
    );

    // 发送邮件的响应 data 格式不确定，只关心是否成功
    return _parseResponse<List<Email>>(response, (data) {
      if (data is List) {
        return data.map((e) => Email.fromJson(e as Map<String, dynamic>)).toList();
      }
      return []; // 成功但 data 不是列表，返回空列表
    });
  }

  Future<ApiResponse<List<Attachment>>> getAttachmentList(int emailId) async {
    final uri = Uri.parse(_url('/email/attList'))
        .replace(queryParameters: {'emailId': emailId.toString()});
    final response = await http.get(uri, headers: _headers);

    return _parseResponse<List<Attachment>>(response, (data) {
      if (data is List) {
        return data.map((e) => Attachment.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    });
  }

  Future<ApiResponse> addStar(int emailId) async {
    final response = await http.post(
      Uri.parse(_url('/star/add')),
      headers: _headers,
      body: jsonEncode({'emailId': emailId}),
    );
    return _parseResponse(response, null);
  }

  Future<ApiResponse> cancelStar(int emailId) async {
    final uri = Uri.parse(_url('/star/cancel'))
        .replace(queryParameters: {'emailId': emailId.toString()});
    final response = await http.delete(uri, headers: _headers);
    return _parseResponse(response, null);
  }

  Future<ApiResponse<List<Email>>> getStarList({
    int size = 20,
    int? emailId,
  }) async {
    final params = <String, String>{
      'size': size.toString(),
      if (emailId != null) 'emailId': emailId.toString(),
    };
    final uri = Uri.parse(_url('/star/list')).replace(queryParameters: params);
    final response = await http.get(uri, headers: _headers);

    return _parseResponse<List<Email>>(response, (data) {
      // star/list 返回 {list: [...]}
      if (data is Map<String, dynamic>) {
        final rawList = data['list'] as List? ?? [];
        return rawList
            .map((e) => Email.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      if (data is List) {
        return data.map((e) => Email.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    });
  }

  Future<ApiResponse<List<Account>>> getAccountList() async {
    final response = await http.get(
      Uri.parse(_url('/account/list')),
      headers: _headers,
    );

    return _parseResponse<List<Account>>(response, (data) {
      if (data is List) {
        return data.map((e) => Account.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    });
  }

  Future<ApiResponse<Account>> addAccount(String email, {String? password}) async {
    final response = await http.post(
      Uri.parse(_url('/account/add')),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        if (password != null) 'password': password,
      }),
    );

    return _parseResponse<Account>(response, (data) => Account.fromJson(data));
  }

  Future<ApiResponse> deleteAccount(int accountId) async {
    final uri = Uri.parse(_url('/account/delete'))
        .replace(queryParameters: {'accountId': accountId.toString()});
    final response = await http.delete(uri, headers: _headers);
    return _parseResponse(response, null);
  }

  Future<ApiResponse> setAccountName(int accountId, String name) async {
    final response = await http.put(
      Uri.parse(_url('/account/setName')),
      headers: _headers,
      body: jsonEncode({'accountId': accountId, 'name': name}),
    );
    return _parseResponse(response, null);
  }

  Future<ApiResponse> setAccountAsTop(int accountId) async {
    final response = await http.put(
      Uri.parse(_url('/account/setAsTop')),
      headers: _headers,
      body: jsonEncode({'accountId': accountId}),
    );
    return _parseResponse(response, null);
  }

  Future<ApiResponse> logout() async {
    final response = await http.delete(
      Uri.parse(_url('/logout')),
      headers: _headers,
    );
    return _parseResponse(response, null);
  }
}
