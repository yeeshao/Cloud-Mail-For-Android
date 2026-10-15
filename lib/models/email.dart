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

  factory Email.fromJson(Map<String, dynamic> json) {
    return Email(
      emailId: json['emailId'] ?? 0,
      sendEmail: (json['sendEmail'] ?? json['fromEmail'] ?? '').toString(),
      sendName: (json['sendName'] ?? json['fromName'] ?? json['name'] ?? '').toString(),
      subject: json['subject'] ?? '(无主题)',
      toEmail: (json['toEmail'] ?? json['receiverEmail'] ?? json['receiveEmail'] ?? json['recipientEmail'] ?? json['mailTo'] ?? json['to'] ?? '').toString(),
      toName: (json['toName'] ?? json['receiverName'] ?? json['receiveName'] ?? json['recipientName'] ?? '').toString(),
      createTime: json['createTime'] ?? '',
      type: json['type'] ?? 0,
      content: json['content'] ?? '',
      text: json['text'] ?? '',
      isDel: json['isDel'] ?? 0,
      isStar: json['isStar'] ?? (json['starId'] != null ? 1 : 0),
      status: json['status'] ?? 0,
      messageId: json['messageId'],
      attList: json['attList'] != null
          ? (json['attList'] as List)
              .map((e) => Attachment.fromJson(e))
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
