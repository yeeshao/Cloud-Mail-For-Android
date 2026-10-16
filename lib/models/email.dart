import 'dart:convert';

class Email {
  final int emailId;
  final String sendEmail;
  final String sendName;
  final String subject;
  final String toEmail;
  final String toName;
  final String createTime;
  final int type;
  final String content;
  final String text;
  final int isDel;
  final int isStar;
  final int status;
  final String? messageId;
  final List<Attachment>? attList;

  Email({
    required this.emailId,
    required this.sendEmail,
    required this.sendName,
    required this.subject,
    required this.toEmail,
    required this.toName,
    required this.createTime,
    required this.type,
    required this.content,
    required this.text,
    required this.isDel,
    this.isStar = 0,
    this.status = 0,
    this.messageId,
    this.attList,
  });

  static String _mailField(dynamic value) {
    if (value == null) return '';
    if (value is String || value is num) return value.toString();
    if (value is List) {
      return value.map(_mailField).where((s) => s.trim().isNotEmpty).join(', ');
    }
    if (value is Map) {
      final m = Map<String, dynamic>.from(value);
      final name = (m['name'] ?? m['personal'] ?? m['toName'] ?? m['receiverName'] ?? '').toString();
      final address = (m['email'] ?? m['address'] ?? m['mail'] ?? m['emailAddress'] ?? m['toEmail'] ?? '').toString();
      if (name.isNotEmpty && address.isNotEmpty) return '$name <$address>';
      if (address.isNotEmpty) return address;
      if (name.isNotEmpty) return name;
      return m.values.map(_mailField).where((s) => s.trim().isNotEmpty).join(', ');
    }
    return value.toString();
  }

  // 统一状态：1 表示已读，0 表示未读。
  // 不要优先读取通用的 `status`：部分服务端用它表示邮件发送/同步状态，
  // 会覆盖真正的 isRead/read/seen 字段，导致所有邮件看起来状态相同。
  static int _parseReadStatus(Map<String, dynamic> json) {
    dynamic findReadValue(Map source) {
      const explicitKeys = [
        'isRead', 'is_read', 'readStatus', 'read_status', 'read',
        'seen', 'isSeen', 'is_seen', 'readFlag', 'read_flag',
        'isReaded', 'readed', 'unread', 'isUnread', 'is_unread',
      ];
      for (final key in explicitKeys) {
        if (source.containsKey(key) && source[key] != null) {
          return {'__key': key, '__value': source[key]};
        }
      }
      // 常见接口会将邮件字段包在 data/mail/emailInfo 中。
      for (final key in ['mail', 'email', 'emailInfo', 'mailInfo', 'data']) {
        final nested = source[key];
        if (nested is Map) {
          final value = findReadValue(nested);
          if (value != null) return value;
        }
      }
      // 只有不存在任何明确的已读字段时，才兼容通用 status。
      if (source.containsKey('status') && source['status'] != null) {
        return {'__key': 'status', '__value': source['status']};
      }
      return null;
    }

    final found = findReadValue(json);
    if (found == null) return 0;
    final key = found['__key'].toString();
    final raw = found['__value'];

    bool? parsed;
    if (raw is bool) {
      parsed = raw;
    } else if (raw is num) {
      parsed = raw != 0;
    } else if (raw != null) {
      final value = raw.toString().trim().toLowerCase();
      if (['1', 'true', 'read', '已读', 'yes', 'seen'].contains(value)) {
        parsed = true;
      } else if (['0', 'false', 'unread', '未读', 'no', 'unseen'].contains(value)) {
        parsed = false;
      }
    }

    if (parsed == null) return 0;
    // unread/isUnread 字段语义与 isRead 相反。
    if (key == 'unread' || key == 'isUnread' || key == 'is_unread') {
      parsed = !parsed;
    }
    return parsed ? 1 : 0;
  }

  factory Email.fromJson(Map<String, dynamic> json) {
    // 网页端/不同接口对收件人的字段命名并不完全一致。
    // recipient 可能是 JSON 字符串、对象、数组，或嵌套在 data/mailInfo 中。
    dynamic firstPresent(Map source, List<String> keys) {
      for (final key in keys) {
        final value = source[key];
        if (value != null && value.toString().trim().isNotEmpty) return value;
      }
      return null;
    }

    dynamic rawTo = firstPresent(json, [
      'toEmail', 'receiverEmail', 'receiveEmail', 'recipientEmail',
      'mailTo', 'to', 'recipients', 'recipient', 'receiver', 'receivers',
      'toAddress', 'receiveAddress', 'mailReceiver', 'receiveUser',
    ]);
    dynamic rawToName = firstPresent(json, [
      'toName', 'receiverName', 'receiveName', 'recipientName',
      'receiverNick', 'toNick', 'receiveNick',
    ]);

    if (rawTo is String) {
      final value = rawTo.trim();
      if ((value.startsWith('[') && value.endsWith(']')) ||
          (value.startsWith('{') && value.endsWith('}'))) {
        try {
          rawTo = jsonDecode(value);
        } catch (_) {}
      }
    }

    // 有些响应把收件人信息包在 recipient/to 对象的 address/email 字段里。
    if (rawTo == null) {
      final nested = firstPresent(json, ['mail', 'emailInfo', 'mailInfo', 'data']);
      if (nested is Map) {
        rawTo = firstPresent(nested, [
          'toEmail', 'receiverEmail', 'receiveEmail', 'recipientEmail',
          'to', 'recipients', 'recipient', 'receiver', 'receivers',
        ]);
        rawToName = rawToName ?? firstPresent(nested, [
          'toName', 'receiverName', 'receiveName', 'recipientName',
        ]);
      }
    }

    String stringField(dynamic value, [String fallback = '']) =>
        value == null ? fallback : value.toString();

    return Email(
      emailId: int.tryParse(stringField(json['emailId'] ?? json['id'])) ?? 0,
      sendEmail: stringField(json['sendEmail'] ?? json['fromEmail'] ?? json['senderEmail']),
      sendName: stringField(json['sendName'] ?? json['fromName'] ?? json['senderName'] ?? json['name']),
      subject: stringField(json['subject'] ?? json['title'], '(无主题)'),
      toEmail: _mailField(rawTo),
      toName: _mailField(rawToName),
      createTime: stringField(json['createTime'] ?? json['sendTime'] ?? json['sentDate'] ?? json['date']),
      type: int.tryParse(stringField(json['type'] ?? json['mailType'])) ?? 0,
      content: stringField(json['content'] ?? json['html'] ?? json['body']),
      text: stringField(json['text'] ?? json['textContent'] ?? json['plainText']),
      isDel: int.tryParse(stringField(json['isDel'] ?? json['deleted'])) ?? 0,
      isStar: int.tryParse(stringField(json['isStar'] ?? (json['starId'] != null ? 1 : 0))) ?? 0,
      status: _parseReadStatus(json),
      messageId: json['messageId']?.toString(),
      attList: json['attList'] is List
          ? (json['attList'] as List)
              .whereType<Map>()
              .map((e) => Attachment.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : null,
    );
  }

  bool get isReceived => type == 0;
  bool get isSent => type == 1;
  bool get isStarred => isStar == 1;
  bool get isDeleted => isDel == 1 || isDel == 2;
  bool get isRead => status == 1;

  /// 序列化为 JSON，用于本地缓存
  Map<String, dynamic> toJson() => {
        'emailId': emailId,
        'sendEmail': sendEmail,
        'sendName': sendName,
        'subject': subject,
        'toEmail': toEmail,
        'toName': toName,
        'createTime': createTime,
        'type': type,
        'content': content,
        'text': text,
        'isDel': isDel,
        'isStar': isStar,
        'status': status,
        'messageId': messageId,
        'attList': attList?.map((a) => a.toJson()).toList(),
      };
}

class Attachment {
  final int attId;
  final String fileName;
  final String fileSize;
  final String contentType;
  final String? contentId;
  final String? url;

  Attachment({
    required this.attId,
    required this.fileName,
    required this.fileSize,
    required this.contentType,
    this.contentId,
    this.url,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      attId: json['attId'] ?? 0,
      fileName: json['fileName'] ?? json['filename'] ?? '未命名',
      fileSize: json['fileSize']?.toString() ?? '0',
      contentType: json['contentType'] ?? json['type'] ?? 'application/octet-stream',
      contentId: json['contentId'],
      url: json['url'],
    );
  }

  Map<String, dynamic> toJson() => {
        'attId': attId,
        'fileName': fileName,
        'fileSize': fileSize,
        'contentType': contentType,
        'contentId': contentId,
        'url': url,
      };
}

class Account {
  final int accountId;
  final String email;
  final String name;
  final int userId;
  final int isTop;
  final int allReceive;

  Account({
    required this.accountId,
    required this.email,
    required this.name,
    required this.userId,
    this.isTop = 0,
    this.allReceive = 0,
  });

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      accountId: json['accountId'] ?? 0,
      email: json['email'] ?? '',
      name: json['name'] ?? '',
      userId: json['userId'] ?? 0,
      isTop: json['isTop'] ?? 0,
      allReceive: json['allReceive'] ?? 0,
    );
  }

  String get displayName => name.isNotEmpty ? name : email.split('@').first;
}

class ApiResponse<T> {
  final int code;
  final String message;
  final T? data;

  ApiResponse({
    required this.code,
    required this.message,
    this.data,
  });

  bool get isSuccess => code >= 200 && code < 300;

  factory ApiResponse.fromJson(Map<String, dynamic> json, T Function(dynamic)? dataParser) {
    T? parsedData;
    if (json['data'] != null && dataParser != null) {
      try {
        parsedData = dataParser(json['data']);
      } catch (_) {
        // 数据解析失败，但不影响判断成功与否
      }
    }
    return ApiResponse<T>(
      code: json['code'] ?? (json['success'] == true ? 200 : 0),
      message: json['message'] ?? json['msg'] ?? '',
      data: parsedData,
    );
  }
}

class EmailListResult {
  final List<Email> list;
  final int total;
  final Email? latestEmail;

  EmailListResult({
    required this.list,
    required this.total,
    this.latestEmail,
  });
}
