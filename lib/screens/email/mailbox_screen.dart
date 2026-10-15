import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/email.dart';
import '../../services/api_service.dart';
import '../../utils/glass.dart';
import '../../utils/storage.dart';
import '../../utils/theme.dart';
import '../settings/settings_screen.dart';
import '../accounts/account_screen.dart';
import 'email_detail_screen.dart';
import 'compose_screen.dart';

class MailboxScreen extends StatefulWidget {
  final CloudMailApi api;

  const MailboxScreen({super.key, required this.api});

  @override
  State<MailboxScreen> createState() => _MailboxScreenState();
}

/// 邮件文件夹
enum MailFolder { inbox, sent, starred, trash }

class _MailboxScreenState extends State<MailboxScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  MailFolder _currentFolder = MailFolder.inbox;
  List<Email> _emails = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int? _lastEmailId;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;
  String _searchQuery = '';

  bool _silentRefreshing = false;

  // 多选模式
  bool _selectMode = false;
  final Set<int> _selectedEmailIds = {};
  bool _batchLoading = false;
  List<Account> _accounts = [];
  bool _allAccounts = false;

  @override
  void initState() {
    super.initState();
    _initData();
    _scrollController.addListener(_scrollListener);
  }

  Future<void> _initData() async {
    try {
      final accResp = await widget.api.getAccountList();
      if (accResp.isSuccess && accResp.data != null) {
        final accounts = accResp.data!;
        if (mounted) setState(() => _accounts = accounts);
        if (accounts.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('暂无邮箱账户，请先添加账户')),
            );
          }
        } else {
          final currentId = StorageService.currentAccountId;
          final exists = accounts.any((a) => a.accountId == currentId);
          if (!exists) {
            StorageService.currentAccountId = accounts.first.accountId;
          }
        }
      }
    } catch (_) {}
    _loadEmails();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  int get _emailType {
    switch (_currentFolder) {
      case MailFolder.inbox:
      case MailFolder.starred:
      case MailFolder.trash:
        return 0;
      case MailFolder.sent:
        return 1;
    }
  }

  String get _folderTitle {
    switch (_currentFolder) {
      case MailFolder.inbox:
        return '收件箱';
      case MailFolder.sent:
        return '已发送';
      case MailFolder.starred:
        return '星标邮件';
      case MailFolder.trash:
        return '垃圾箱';
    }
  }

  String get _cacheKey => _currentFolder.name;

  int? get _queryAccountId => _allAccounts ? null : StorageService.currentAccountId;

  String _formatTime(String timeStr) {
    try {
      final dt = DateTime.parse(timeStr).toLocal();
      return '${dt.year}年${dt.month}月${dt.day}日${dt.hour.toString().padLeft(2, '0')}：${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return timeStr;
    }
  }

  String _getPreview(Email email) {
    final text = email.text.isNotEmpty
        ? email.text
        : email.content.replaceAll(RegExp(r'<[^>]*>'), '');
    return text.length > 100 ? '${text.substring(0, 100)}...' : text;
  }

  List<Email> get _filteredEmails {
    if (_searchQuery.isEmpty) return _emails;
    final q = _searchQuery.toLowerCase();
    return _emails.where((e) {
      return e.subject.toLowerCase().contains(q) ||
          e.sendName.toLowerCase().contains(q) ||
          e.sendEmail.toLowerCase().contains(q) ||
          e.toEmail.toLowerCase().contains(q) ||
          e.toName.toLowerCase().contains(q) ||
          e.text.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _loadEmails() async {
    _exitSelectMode();

    final cached = StorageService.getMailCache(_cacheKey, _queryAccountId);
    final hasCache = cached != null && cached.isNotEmpty;
    if (hasCache) {
      setState(() {
        _emails = cached.map((e) => Email.fromJson(e)).toList();
        _loading = false;
        _silentRefreshing = true;
        _hasMore = _emails.length >= 20;
        if (_emails.isNotEmpty) {
          _lastEmailId = _emails.last.emailId;
        }
      });
    } else {
      setState(() {
        _loading = true;
        _emails = [];
        _lastEmailId = null;
        _hasMore = true;
      });
    }

    try {
      if (_currentFolder == MailFolder.starred) {
        final response = await widget.api.getStarList(size: 20);
        if (response.isSuccess && response.data != null) {
          final fresh = response.data!;
          setState(() {
            _emails = fresh;
            _hasMore = fresh.length >= 20;
            if (fresh.isNotEmpty) {
              _lastEmailId = fresh.last.emailId;
            }
          });
        }
      } else {
        final isDel = _currentFolder == MailFolder.trash ? 1 : null;
        final response = _allAccounts
            ? await widget.api.getAllEmailList(
                type: _emailType,
                size: 20,
                timeSort: 0,
                isDel: isDel,
              )
            : await widget.api.getEmailList(
                accountId: _queryAccountId,
                type: _emailType,
                size: 20,
                timeSort: 0,
                isDel: isDel,
              );
        if (response.isSuccess && response.data != null) {
          final fresh = response.data!.list;
          setState(() {
            _emails = fresh;
            _hasMore = fresh.length >= 20;
            if (fresh.isNotEmpty) {
              _lastEmailId = fresh.last.emailId;
            }
          });
          StorageService.setMailCache(
            _cacheKey,
            _queryAccountId,
            fresh.map((e) => e.toJson()).toList(),
          );
        }
      }
    } catch (e) {
      if (mounted && !hasCache) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessages.fromException(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _silentRefreshing = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);

    try {
      if (_currentFolder == MailFolder.starred) {
        final response = await widget.api.getStarList(
          size: 20,
          emailId: _lastEmailId,
        );
        if (response.isSuccess && response.data != null) {
          setState(() {
            _emails.addAll(response.data!);
            _hasMore = response.data!.length >= 20;
            if (response.data!.isNotEmpty) {
              _lastEmailId = response.data!.last.emailId;
            }
          });
        }
      } else {
        final isDel = _currentFolder == MailFolder.trash ? 1 : null;
        final response = _allAccounts
            ? await widget.api.getAllEmailList(
                type: _emailType,
                size: 20,
                emailId: _lastEmailId,
                timeSort: 0,
                isDel: isDel,
              )
            : await widget.api.getEmailList(
                accountId: _queryAccountId,
                type: _emailType,
                size: 20,
                emailId: _lastEmailId,
                timeSort: 0,
                isDel: isDel,
              );
        if (response.isSuccess && response.data != null) {
          setState(() {
            _emails.addAll(response.data!.list);
            _hasMore = response.data!.list.length >= 20;
            if (response.data!.list.isNotEmpty) {
              _lastEmailId = response.data!.list.last.emailId;
            }
          });
        }
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _onRefresh() async {
    await _loadEmails();
  }

  void _openEmail(Email email) async {
    if (_selectMode) {
      _toggleSelect(email.emailId);
      return;
    }
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => EmailDetailScreen(email: email, api: widget.api),
      ),
    );
    if (result == true) {
      _loadEmails();
    }
  }

  // ========== 多选模式相关 ==========

  void _enterSelectMode() {
    setState(() => _selectMode = true);
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selectedEmailIds.clear();
    });
  }

  void _toggleSelect(int emailId) {
    setState(() {
      if (_selectedEmailIds.contains(emailId)) {
        _selectedEmailIds.remove(emailId);
        if (_selectedEmailIds.isEmpty) {
          _selectMode = false;
        }
      } else {
        _selectedEmailIds.add(emailId);
      }
    });
  }

  void _selectAll() {
    setState(() {
      for (final email in _filteredEmails) {
        _selectedEmailIds.add(email.emailId);
      }
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedEmailIds.clear();
      _selectMode = false;
    });
  }

  bool get _isAllSelected {
    if (_filteredEmails.isEmpty) return false;
    return _filteredEmails.every((e) => _selectedEmailIds.contains(e.emailId));
  }

  Future<void> _batchDelete() async {
    if (_selectedEmailIds.isEmpty || _batchLoading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除邮件'),
        content: Text('确定要删除选中的 ${_selectedEmailIds.length} 封邮件吗？'),
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

    setState(() => _batchLoading = true);
    try {
      final ids = _selectedEmailIds.join(',');
      final response = await widget.api.deleteEmails(ids);
      if (response.isSuccess) {
        setState(() {
          _emails.removeWhere((e) => _selectedEmailIds.contains(e.emailId));
          _selectedEmailIds.clear();
          _selectMode = false;
        });
        if (mounted) {
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
    } finally {
      if (mounted) setState(() => _batchLoading = false);
    }
  }

  void _navigateTo(MailFolder folder) {
    setState(() {
      _currentFolder = folder;
    });
    Navigator.pop(context);
    _loadEmails();
  }

  void _openCompose() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => ComposeScreen(api: widget.api),
      ),
    ).then((result) {
      if (result == true) {
        _loadEmails();
      }
    });
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => SettingsScreen(api: widget.api),
      ),
    );
  }

  void _openAccounts() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => AccountScreen(api: widget.api),
      ),
    ).then((_) {
      _loadEmails();
    });
  }

  Future<void> _toggleStar(Email email) async {
    try {
      final response = email.isStarred
          ? await widget.api.cancelStar(email.emailId)
          : await widget.api.addStar(email.emailId);
      if (response.isSuccess) {
        setState(() {
          final idx = _emails.indexWhere((e) => e.emailId == email.emailId);
          if (idx >= 0) {
            _emails[idx] = Email(
              emailId: email.emailId,
              sendEmail: email.sendEmail,
              sendName: email.sendName,
              subject: email.subject,
              toEmail: email.toEmail,
              toName: email.toName,
              createTime: email.createTime,
              type: email.type,
              content: email.content,
              text: email.text,
              isDel: email.isDel,
              isStar: email.isStarred ? 0 : 1,
              status: email.status,
              messageId: email.messageId,
              attList: email.attList,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMessages.fromException(e))),
        );
      }
    }
  }

  Future<void> _deleteEmail(Email email) async {
    try {
      final response = await widget.api.deleteEmails(email.emailId.toString());
      if (response.isSuccess) {
        setState(() {
          _emails.removeWhere((e) => e.emailId == email.emailId);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已移到垃圾箱')),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isGoogle = themeProvider.isGoogle;
    final hasBg = themeProvider.hasCustomBackground;

    final content = SafeArea(
      child: Column(
        children: [
          GlassBox(
            isDark: isDark,
            blur: 25,
            opacity: 0.7,
            radius: 0,
            child: _selectMode
                ? _buildSelectAppBar(isDark)
                : (isGoogle
                    ? _buildGoogleAppBar(isDark)
                    : _buildAppleAppBar(isDark)),
          ),
          if (_selectMode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.3),
                border: Border(
                  bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '已选 ${_selectedEmailIds.length} 封',
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _batchLoading ? null : _batchDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('删除'),
                    style: TextButton.styleFrom(foregroundColor: cs.error),
                  ),
                ],
              ),
            ),
          if (_silentRefreshing)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: cs.primaryContainer.withOpacity(0.4),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      valueColor: AlwaysStoppedAnimation(cs.primary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '正在获取最新邮件…',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? _buildLoadingList(isGoogle)
                : _filteredEmails.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _onRefresh,
                        color: Theme.of(context).colorScheme.primary,
                        child: isGoogle
                            ? _buildGoogleEmailList()
                            : _buildAppleEmailList(),
                      ),
          ),
        ],
      ),
    );

    return Scaffold(
      key: _scaffoldKey,
      body: hasBg && themeProvider.customBackgroundImage != null
          ? Stack(
              children: [
                Positioned.fill(
                  child: Image.file(
                    File(themeProvider.customBackgroundImage!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                content,
              ],
            )
          : content,
      drawer: _selectMode ? null : _buildDrawer(isDark, isGoogle),
      bottomNavigationBar: _selectMode ? null : _buildBottomNavigationBar(),
      floatingActionButton: _selectMode
          ? null
          : FloatingActionButton(
              onPressed: _openCompose,
              tooltip: '写邮件',
              child: const Icon(Icons.edit_outlined),
            ),
    );
  }

  // ========== 多选模式 AppBar ==========
  Widget _buildSelectAppBar(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _deselectAll,
              ),
              const SizedBox(width: 4),
              Text(
                '选择邮件',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _isAllSelected ? _deselectAll : _selectAll,
                icon: Icon(
                  _isAllSelected
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 20,
                ),
                label: Text(_isAllSelected ? '取消全选' : '全选'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== Google 风格 AppBar ====================
  Widget _buildGoogleAppBar(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: cs.surfaceVariant,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) {
                      setState(() {
                        _searchQuery = v;
                        _searching = v.isNotEmpty;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: '搜索邮件',
                      hintStyle: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 15,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: cs.onSurfaceVariant,
                        size: 20,
                      ),
                      suffixIcon: _searching
                          ? IconButton(
                              icon: Icon(
                                Icons.close,
                                color: cs.onSurfaceVariant,
                                size: 18,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _searching = false;
                                });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildAccountAvatar(),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _folderTitle,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w400,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'select':
                        _enterSelectMode();
                        break;
                      case 'refresh':
                        _loadEmails();
                        break;
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'select',
                      child: Row(children: [
                        Icon(Icons.checklist_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('选择邮件'),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'refresh',
                      child: Row(children: [
                        Icon(Icons.refresh_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('刷新'),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountAvatar() {
    Account? account;
    for (final item in _accounts) {
      if (item.accountId == StorageService.currentAccountId) { account = item; break; }
    }
    final email = _allAccounts ? '全部邮箱' : (account?.email ?? StorageService.email ?? '');
    final accountColor = AppTheme.accountColor(email);
    return Tooltip(
      message: '切换邮箱账户',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _showAccountPicker,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: accountColor, shape: BoxShape.circle),
          child: Center(
            child: Text(
              _allAccounts ? '全' : (email.isNotEmpty ? email[0].toUpperCase() : '?'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAccountPicker() async {
    // 账户列表已在初始化时加载；不要在点击头像后再等待网络请求。
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
                  child: Text('切换邮箱账户', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(sheetContext).colorScheme.primary,
                    child: const Icon(Icons.all_inbox, color: Colors.white),
                  ),
                  title: const Text('全部邮箱'),
                  subtitle: const Text('合并查看所有账户的邮件'),
                  trailing: _allAccounts ? Icon(Icons.check_circle, color: cs.primary) : null,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    if (!_allAccounts) {
                      setState(() {
                        _allAccounts = true;
                        _emails = [];
                        _lastEmailId = null;
                        _hasMore = true;
                      });
                      _loadEmails();
                    }
                  },
                ),
                if (_accounts.isEmpty)
                  const Padding(padding: EdgeInsets.all(16), child: Text('暂无其他邮箱账户'))
                else
                  ..._accounts.map((account) {
                    final selected = !_allAccounts && account.accountId == StorageService.currentAccountId;
                    final color = AppTheme.accountColor(account.email);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: CircleAvatar(
                        backgroundColor: color,
                        child: Text(account.email.isNotEmpty ? account.email[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text(account.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(account.email, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: selected ? Icon(Icons.check_circle, color: cs.primary) : null,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        if (_allAccounts || StorageService.currentAccountId != account.accountId) {
                          setState(() {
                            _allAccounts = false;
                            StorageService.currentAccountId = account.accountId;
                            _emails = [];
                            _lastEmailId = null;
                            _hasMore = true;
                          });
                          _loadEmails();
                        }
                      },
                    );
                  }),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: const Text('管理邮箱账户'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openAccounts();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomNavigationBar() {
    final cs = Theme.of(context).colorScheme;
    const folders = <MailFolder>[MailFolder.inbox, MailFolder.sent, MailFolder.starred, MailFolder.trash];
    const labels = <String>['收件箱', '已发送', '星标', '垃圾箱'];
    const icons = <IconData>[Icons.inbox_outlined, Icons.send_outlined, Icons.star_border_rounded, Icons.delete_outline_rounded];
    final selectedIndex = folders.indexOf(_currentFolder);
    return NavigationBar(
      height: 68,
      selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      backgroundColor: cs.surface,
      indicatorColor: cs.primaryContainer,
      onDestinationSelected: (index) {
        final folder = folders[index];
        if (folder == _currentFolder) return;
        setState(() {
          _currentFolder = folder;
          _emails = [];
          _lastEmailId = null;
          _hasMore = true;
          _searchQuery = '';
          _searching = false;
          _searchController.clear();
        });
        _loadEmails();
      },
      destinations: List.generate(folders.length, (index) => NavigationDestination(
        icon: Icon(icons[index]),
        selectedIcon: Icon(icons[index]),
        label: labels[index],
      )),
    );
  }

  // ==================== Apple 风格 AppBar ====================
  Widget _buildAppleAppBar(bool isDark) {
    final cs = Theme.of(context).colorScheme;
    final email = StorageService.email ?? '';

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.menu, size: 24),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              Expanded(
                child: Text(
                  _folderTitle,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
              ),
              _buildAccountAvatar(),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.search, size: 22),
                onPressed: () {
                  setState(() => _searching = !_searching);
                  if (!_searching) {
                    _searchController.clear();
                    _searchQuery = '';
                  }
                },
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'select':
                      _enterSelectMode();
                      break;
                    case 'refresh':
                      _loadEmails();
                      break;
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'select',
                    child: Row(children: [
                      Icon(Icons.checklist_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('选择邮件'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'refresh',
                    child: Row(children: [
                      Icon(Icons.refresh_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('刷新'),
                    ]),
                  ),
                ],
              ),
            ],
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _searching
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(height: 0, width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: TextField(
                controller: _searchController,
                autofocus: _searching,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: '搜索邮件...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.cancel_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searching = false;
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Google 风格邮件列表 ====================
  Widget _buildGoogleEmailList() {
    final emails = _filteredEmails;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: emails.length + (_loadingMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == emails.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return RepaintBoundary(child: _buildGoogleEmailItem(emails[i]));
      },
    );
  }

  Widget _buildGoogleEmailItem(Email email) {
    final cs = Theme.of(context).colorScheme;
    final senderName = email.isSent
        ? (email.toName.isNotEmpty
            ? email.toName
            : email.toEmail.split('@').first)
        : (email.sendName.isNotEmpty
            ? email.sendName
            : email.sendEmail.split('@').first);
    final accountColor =
        AppTheme.accountColor(email.isSent ? email.toEmail : email.sendEmail);
    final hasAttachment =
        email.attList != null && email.attList!.isNotEmpty;
    final isSelected = _selectedEmailIds.contains(email.emailId);

    return Dismissible(
      key: ValueKey('email-${email.emailId}'),
      direction: (_selectMode || !StorageService.swipeActionsEnabled)
          ? DismissDirection.none
          : DismissDirection.horizontal,
      background: Container(
        color: cs.primary,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: Icon(
          email.isStarred ? Icons.star : Icons.star_border,
          color: cs.onPrimary,
        ),
      ),
      secondaryBackground: Container(
        color: cs.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: cs.onError),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await _toggleStar(email);
          return false;
        }
        return true;
      },
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          _deleteEmail(email);
        }
      },
      child: Material(
        color: isSelected ? cs.primaryContainer.withOpacity(0.3) : Colors.transparent,
        child: InkWell(
          onTap: () => _openEmail(email),
          onLongPress: () {
            if (!_selectMode) {
              _enterSelectMode();
              _toggleSelect(email.emailId);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 选择框
                if (_selectMode)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 8),
                    child: Icon(
                      isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 22,
                      color: isSelected ? cs.primary : cs.onSurfaceVariant,
                    ),
                  )
                else
                  // 星标按钮
                  GestureDetector(
                    onTap: () => _toggleStar(email),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2, right: 12),
                      child: Icon(
                        email.isStarred ? Icons.star : Icons.star_border,
                        size: 18,
                        color: email.isStarred
                            ? cs.tertiary
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                // 方形圆角头像
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accountColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      senderName.isNotEmpty
                          ? senderName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 主体内容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              senderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatTime(email.createTime),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (hasAttachment) ...[
                            Icon(
                              Icons.attach_file,
                              size: 14,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              _getPreview(email),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== Apple 风格邮件列表 ====================
  Widget _buildAppleEmailList() {
    final emails = _filteredEmails;
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: emails.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 72, endIndent: 16),
      itemBuilder: (ctx, i) {
        if (i == emails.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _buildAppleEmailItem(emails[i]);
      },
    );
  }

  Widget _buildAppleEmailItem(Email email) {
    final cs = Theme.of(context).colorScheme;
    final senderName = email.isSent
        ? (email.toName.isNotEmpty
            ? email.toName
            : email.toEmail.split('@').first)
        : (email.sendName.isNotEmpty
            ? email.sendName
            : email.sendEmail.split('@').first);
    final accountColor =
        AppTheme.accountColor(email.isSent ? email.toEmail : email.sendEmail);
    final isSelected = _selectedEmailIds.contains(email.emailId);

    return Dismissible(
      key: ValueKey('email-${email.emailId}'),
      direction: (_selectMode || !StorageService.swipeActionsEnabled)
          ? DismissDirection.none
          : DismissDirection.horizontal,
      background: Container(
        color: cs.primary,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: Icon(
          email.isStarred ? Icons.star : Icons.star_border,
          color: cs.onPrimary,
        ),
      ),
      secondaryBackground: Container(
        color: cs.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: cs.onError),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await _toggleStar(email);
          return false;
        }
        return true;
      },
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          _deleteEmail(email);
        }
      },
      child: Material(
        color: isSelected ? cs.primaryContainer.withOpacity(0.3) : Colors.transparent,
        child: InkWell(
          onTap: () => _openEmail(email),
          onLongPress: () {
            if (!_selectMode) {
              _enterSelectMode();
              _toggleSelect(email.emailId);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 选择框
                if (_selectMode)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 8),
                    child: Icon(
                      isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 22,
                      color: isSelected ? cs.primary : cs.onSurfaceVariant,
                    ),
                  )
                else
                  // 圆形头像
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: accountColor,
                    child: Text(
                      senderName.isNotEmpty
                          ? senderName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                const SizedBox(width: 12),
                // 主体
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              senderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (email.isStarred)
                            Icon(Icons.star, size: 14, color: cs.tertiary),
                          const SizedBox(width: 4),
                          Text(
                            _formatTime(email.createTime),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getPreview(email),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== 抽屉 ====================
  Widget _buildDrawer(bool isDark, bool isGoogle) {
    final cs = Theme.of(context).colorScheme;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final email = StorageService.email ?? '';
    final accountColor = AppTheme.accountColor(email);

    return Drawer(
      backgroundColor: cs.surface,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accountColor,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _allAccounts ? '全' : (email.isNotEmpty ? email[0].toUpperCase() : '?'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          email.isNotEmpty
                              ? email.split('@').first
                              : '未登录',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  _buildSectionLabel('邮箱'),
                  _buildDrawerItem(
                    icon: Icons.inbox_outlined,
                    title: '收件箱',
                    folder: MailFolder.inbox,
                  ),
                  _buildDrawerItem(
                    icon: Icons.send_outlined,
                    title: '已发送',
                    folder: MailFolder.sent,
                  ),
                  _buildDrawerItem(
                    icon: Icons.star_border,
                    title: '星标邮件',
                    folder: MailFolder.starred,
                  ),
                  _buildDrawerItem(
                    icon: Icons.delete_outline,
                    title: '垃圾箱',
                    folder: MailFolder.trash,
                  ),
                  const Divider(),
                  _buildSectionLabel('工具'),
                  _buildPlainItem(
                    icon: Icons.auto_awesome_outlined,
                    title: 'AI 助手',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/ai',
                          arguments: {'api': widget.api});
                    },
                  ),
                  _buildPlainItem(
                    icon: Icons.contacts_outlined,
                    title: '联系人',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/contacts',
                          arguments: {'api': widget.api});
                    },
                  ),
                  _buildPlainItem(
                    icon: Icons.account_circle_outlined,
                    title: '邮箱账户',
                    onTap: _openAccounts,
                  ),
                  _buildPlainItem(
                    icon: Icons.settings_outlined,
                    title: '设置',
                    onTap: _openSettings,
                  ),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: ListTile(
                leading: Icon(
                  isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  size: 22,
                  color: cs.onSurfaceVariant,
                ),
                title: Text(
                  '深色模式',
                  style: TextStyle(color: cs.onSurface),
                ),
                trailing: Switch(
                  value: isDark,
                  onChanged: (val) {
                    themeProvider.setThemeMode(
                      val ? ThemeMode.dark : ThemeMode.light,
                    );
                  },
                ),
                onTap: () {
                  themeProvider.setThemeMode(
                    isDark ? ThemeMode.light : ThemeMode.dark,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required MailFolder folder,
  }) {
    final selected = _currentFolder == folder;
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: selected ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: selected ? cs.primary : cs.onSurfaceVariant,
          size: 22,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? cs.primary : cs.onSurface,
          ),
        ),
        onTap: () => _navigateTo(folder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9999),
        ),
      ),
    );
  }

  Widget _buildPlainItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ListTile(
        leading: Icon(icon, color: cs.onSurfaceVariant, size: 22),
        title: Text(
          title,
          style: TextStyle(color: cs.onSurface),
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9999),
        ),
      ),
    );
  }

  // ==================== 加载/空状态 ====================
  Widget _buildLoadingList(bool isGoogle) {
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: 10,
      separatorBuilder: (_, __) =>
          Divider(height: 1, indent: isGoogle ? 76 : 72, endIndent: 16),
      itemBuilder: (ctx, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.surfaceVariant,
                shape: isGoogle ? BoxShape.rectangle : BoxShape.circle,
                borderRadius:
                    isGoogle ? BorderRadius.circular(12) : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: 120,
                    decoration: BoxDecoration(
                      color: cs.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 12,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: cs.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 12,
                    width: 200,
                    decoration: BoxDecoration(
                      color: cs.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final cs = Theme.of(context).colorScheme;
    IconData icon;
    String text;
    switch (_currentFolder) {
      case MailFolder.inbox:
        icon = Icons.inbox_outlined;
        text = '收件箱为空';
        break;
      case MailFolder.sent:
        icon = Icons.send_outlined;
        text = '还没有发送过邮件';
        break;
      case MailFolder.starred:
        icon = Icons.star_border;
        text = '还没有星标邮件';
        break;
      case MailFolder.trash:
        icon = Icons.delete_outline;
        text = '垃圾箱是空的';
        break;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: cs.onSurfaceVariant.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(
            text,
            style: TextStyle(
              fontSize: 15,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          if (_currentFolder != MailFolder.trash)
            TextButton.icon(
              onPressed: _loadEmails,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('刷新'),
            ),
        ],
      ),
    );
  }
}
