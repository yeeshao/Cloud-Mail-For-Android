import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/email.dart';
import '../../services/ai_service.dart';
import '../../services/api_service.dart';
import '../../services/translate_service.dart';
import '../../utils/storage.dart';
import '../../utils/theme.dart';

class EmailDetailScreen extends StatefulWidget {
  final Email email;
  final CloudMailApi api;

  const EmailDetailScreen({
    super.key,
    required this.email,
    required this.api,
  });

  @override
  State<EmailDetailScreen> createState() => _EmailDetailScreenState();
}

class _EmailDetailScreenState extends State<EmailDetailScreen> {
  late Email _email;
  bool _isStarred = false;
  bool _loading = false;
  bool _translating = false;
  String? _translatedText;
  bool _showingTranslation = false;

  @override
  void initState() {
    super.initState();
    _email = widget.email;
    _isStarred = _email.isStarred;
  }

  Future<void> _copyEmailContent() async {
    final plain = _email.text.isNotEmpty
        ? _email.text
        : _email.content.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    final header = '主题: ${_email.subject}\n'
        '发件人: ${_email.sendName} <${_email.sendEmail}>\n'
        '收件人: ${_email.toName} <${_email.toEmail}>\n'
        '时间: ${_email.createTime}\n\n';
    await Clipboard.setData(ClipboardData(text: '$header$plain'));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('邮件内容已复制')),
      );
    }
  }

  String _formatFullTime(String timeStr) {
    try {
      final value = timeStr.trim();
      final hasZone = RegExp(r'(Z|[+-]\\d{2}:?\\d{2})$', caseSensitive: false)
          .hasMatch(value);
      final normalized = value.contains('T') ? value : value.replaceFirst(' ', 'T');
      final parsed = DateTime.parse(normalized);
      final dt = hasZone
          ? parsed.toUtc().add(const Duration(hours: 8))
          : DateTime.utc(parsed.year, parsed.month, parsed.day, parsed.hour,
                  parsed.minute, parsed.second, parsed.millisecond, parsed.microsecond)
              .add(const Duration(hours: 8));
      return DateFormat('yyyy-MM-dd HH:mm').format(dt);
    } catch (_) {
      return timeStr;
    }
  }

  /// 一键翻译邮件全文
  ///
  /// 优先使用 LibreTranslate 免费 API（无需配置），
  /// 失败时回退到 AI 翻译（需要配置 API Key）。
  Future<void> _translateEmail() async {
    setState(() => _translating = true);

    try {
      final plainText = _email.text.isNotEmpty
          ? _email.text
          : _email.content.replaceAll(RegExp(r'<[^>]*>'), '').trim();

      // 1. 先试 LibreTranslate（免费，无需配置）
      final libreResult = await TranslateService.translateToChinese(plainText);

      if (libreResult != null && libreResult.isNotEmpty) {
        setState(() {
          _translatedText = libreResult;
          _showingTranslation = true;
        });
        return;
      }

      // 2. LibreTranslate 失败，回退到 AI 翻译
      final ai = AiService();
      if (!ai.isConfigured) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('翻译服务暂不可用，请稍后重试或配置 AI API Key')),
          );
        }
        return;
      }

      final aiResult = await ai.translateText(plainText);
      if (aiResult.startsWith('API 错误') ||
          aiResult.startsWith('请求失败') ||
          aiResult.startsWith('请先')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(aiResult)),
          );
        }
      } else {
        setState(() {
          _translatedText = aiResult;
          _showingTranslation = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('翻译失败: ${ErrorMessages.fromException(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  Future<void> _toggleStar() async {
    setState(() => _loading = true);
    try {
      final response = _isStarred
          ? await widget.api.cancelStar(_email.emailId)
          : await widget.api.addStar(_email.emailId);
      if (response.isSuccess) {
        setState(() => _isStarred = !_isStarred);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('星标操作失败: ${response.message}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessages.fromException(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteEmail() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除邮件'),
        content: const Text('确定要删除这封邮件吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final response = await widget.api.deleteEmails(_email.emailId.toString());
      if (response.isSuccess) {
        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已移到垃圾箱')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: ${response.message}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessages.fromException(e))),
        );
      }
    }
  }

  void _reply() {
    Navigator.pushNamed(
      context,
      '/compose',
      arguments: {
        'api': widget.api,
        'replyEmail': _email,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isGoogle = themeProvider.isGoogle;
    final senderName = _email.isSent ? _email.toName : _email.sendName;
    final senderEmail = _email.isSent ? _email.toEmail : _email.sendEmail;
    final displayName =
        senderName.isNotEmpty ? senderName : senderEmail.split('@').first;
    final accountColor = AppTheme.accountColor(senderEmail);

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            // ===== 固定顶部操作栏 =====
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(
                  bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      _folderLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _isStarred ? Icons.star_rounded : Icons.star_border_rounded,
                      color: _isStarred ? cs.tertiary : null,
                      size: 24,
                    ),
                    onPressed: _loading ? null : _toggleStar,
                    tooltip: _isStarred ? '取消星标' : '星标',
                  ),
                  IconButton(
                    icon: const Icon(Icons.reply_rounded, size: 22),
                    onPressed: _reply,
                    tooltip: '回复',
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'delete':
                          _deleteEmail();
                          break;
                        case 'copy':
                          _copyEmailContent();
                          break;
                        case 'translate':
                          if (_showingTranslation) {
                            setState(() => _showingTranslation = false);
                          } else {
                            _translateEmail();
                          }
                          break;

                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'copy',
                        child: Row(children: [
                          Icon(Icons.copy_all_outlined, size: 20),
                          SizedBox(width: 8),
                          Text('复制邮件内容'),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'translate',
                        child: Row(children: [
                          Icon(
                            _showingTranslation
                                ? Icons.visibility_off_outlined
                                : Icons.translate_outlined,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(_showingTranslation ? '隐藏翻译' : '一键翻译'),
                        ]),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline, size: 20),
                          SizedBox(width: 8),
                          Text('删除'),
                        ]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // ===== 邮件内容 =====
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  width: MediaQuery.of(context).size.width,
                  color: cs.surface,
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildEmailHeader(
                          cs: cs,
                          isGoogle: isGoogle,
                          isDark: isDark,
                          senderEmail: senderEmail,
                          displayName: displayName,
                          accountColor: accountColor,
                        ),
                        Container(
                          height: 0.5,
                          color: cs.outlineVariant,
                        ),
                        _buildEmailBody(isDark),
                        // 翻译结果
                        if (_translating) ...[
                          const SizedBox(height: 24),
                          Center(
                            child: Column(
                              children: [
                                const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '正在翻译...',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_showingTranslation && _translatedText != null) ...[
                          Container(
                            height: 0.5,
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            color: cs.outlineVariant,
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.translate_outlined, size: 18, color: cs.primary),
                                    const SizedBox(width: 8),
                                    Text(
                                      '中文翻译',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SelectableText(
                                  _translatedText!,
                                  style: TextStyle(
                                    fontSize: 15,
                                    height: 1.6,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _folderLabel {
    if (_email.isSent) return '已发送';
    return '邮件详情';
  }

  Widget _buildAttachmentsMini(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.attach_file, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_email.attList!.length} 个附件',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: cs.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailHeader({
    required ColorScheme cs,
    required bool isGoogle,
    required bool isDark,
    required String senderEmail,
    required String displayName,
    required Color accountColor,
  }) {
    final recipientName = _email.toName;
    final recipientEmail = _email.toEmail;
    final recipientDisplay = recipientName.isNotEmpty
        ? (recipientEmail.isNotEmpty
            ? '$recipientName <$recipientEmail>'
            : recipientName)
        : (recipientEmail.isNotEmpty ? recipientEmail : '（无）');

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _email.subject,
            style: TextStyle(
              fontSize: isGoogle ? 20 : 22,
              fontWeight: FontWeight.bold,
              height: 1.3,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              isGoogle
                  ? Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: accountColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          displayName.isNotEmpty
                              ? displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    )
                  : CircleAvatar(
                      radius: 20,
                      backgroundColor: accountColor,
                      child: Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      senderEmail,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatFullTime(_email.createTime),
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '收件人: $recipientDisplay',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_email.attList != null && _email.attList!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildAttachmentsMini(isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildEmailBody(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final content = _email.content;
    final hasHtml = content.contains('<') && content.contains('>');

    if (!hasHtml && content.trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(Icons.drafts_outlined,
                size: 48, color: cs.onSurfaceVariant.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text(
              '这封邮件是空的',
              style: TextStyle(
                color: cs.onSurfaceVariant.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    // 深色模式下增强对比度
    final textColor = isDark ? Colors.white : cs.onSurface;

    return Container(
      padding: const EdgeInsets.all(16),
      child: hasHtml
          ? HtmlWidget(
              content,
              onTapUrl: (url) async {
                final uri = Uri.parse(url);
                try {
                  await launchUrl(uri,
                      mode: LaunchMode.externalApplication);
                } catch (_) {}
                return true;
              },
              textStyle: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: textColor,
              ),
            )
          : SelectableText(
              content,
              style: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: textColor,
              ),
            ),
    );
  }
}
