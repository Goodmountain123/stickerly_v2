import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:stickerly_v2/app/assets/stickerly_assets.dart';
import 'package:stickerly_v2/app/theme/stickerly_colors.dart';
import 'package:stickerly_v2/app/widgets/asset_file_image.dart';
import 'package:stickerly_v2/app/widgets/stickerly_wordmark.dart';
import 'package:stickerly_v2/core/audio/stickerly_sfx.dart';
import 'package:stickerly_v2/features/assets/data/asset_preferences.dart';
import 'package:stickerly_v2/features/assets/domain/asset_catalog.dart';
import 'package:stickerly_v2/features/auth/domain/account_profile.dart';
import 'package:stickerly_v2/features/editor/presentation/editor_screen.dart';
import 'package:stickerly_v2/features/projects/domain/canvas_preset.dart';
import 'package:stickerly_v2/features/projects/domain/project_repository.dart';
import 'package:stickerly_v2/features/projects/domain/sticker_project.dart';
import 'package:stickerly_v2/features/projects/presentation/projects_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum _HomeTab { menu, stickerBook, drawer }

enum _StoreSort { latest, price, name }

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({
    required this.repository,
    required this.assetCatalogLoader,
    required this.account,
    required this.onAccountUpdated,
    required this.onAvatarUpdated,
    required this.onLogout,
    super.key,
  });

  final ProjectRepository repository;
  final AssetCatalogLoader assetCatalogLoader;
  final AccountProfile? account;
  final Future<AccountProfile> Function(String displayName) onAccountUpdated;
  final Future<AccountProfile> Function(String imagePath) onAvatarUpdated;
  final Future<void> Function() onLogout;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  static const _welcomeMessages = [
    '오늘은 뭘 하고 놀까요?',
    '어서오세요, 반가워요!',
    '예쁘게 꾸며봐요!',
  ];

  late final ProjectsController _controller;
  late final AssetPreferences _assetPreferences;
  Timer? _welcomeTimer;
  var _welcomeIndex = 0;
  var _tab = _HomeTab.menu;
  var _packQuery = '';
  var _hiddenPackIds = <String>{};

  @override
  void initState() {
    super.initState();
    _controller = ProjectsController(
      widget.repository,
      widget.assetCatalogLoader,
    )..initialize();
    _assetPreferences = AssetPreferences();
    unawaited(_loadAssetPreferences());
    _welcomeTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        setState(
          () => _welcomeIndex = (_welcomeIndex + 1) % _welcomeMessages.length,
        );
      }
    });
  }

  Future<void> _loadAssetPreferences() async {
    final hiddenPackIds = await _assetPreferences.loadHiddenPackIds();
    if (!mounted) return;
    setState(() => _hiddenPackIds = hiddenPackIds);
  }

  Future<void> _setPackEnabled(String packId, bool enabled) async {
    setState(() {
      final next = {..._hiddenPackIds};
      if (enabled) {
        next.remove(packId);
      } else {
        next.add(packId);
      }
      _hiddenPackIds = next;
    });
    await _assetPreferences.saveHiddenPackIds(_hiddenPackIds);
  }

  void _setHomeTab(_HomeTab tab) {
    if (_tab != tab) StickerlySfx.play(StickerlyAssets.soundPage);
    setState(() => _tab = tab);
    if (tab == _HomeTab.drawer || tab == _HomeTab.stickerBook) {
      unawaited(_controller.initialize());
    }
  }

  @override
  void dispose() {
    _welcomeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StickerlyColors.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _HomeHeader(
              message: _tab == _HomeTab.menu
                  ? _welcomeMessages[_welcomeIndex]
                  : switch (_tab) {
                      _HomeTab.stickerBook => '스티커북',
                      _HomeTab.drawer => '내 스티커',
                      _HomeTab.menu => _welcomeMessages[_welcomeIndex],
                    },
              showWelcome: _tab == _HomeTab.menu,
              showBack: _tab != _HomeTab.menu,
              onBack: () => _setHomeTab(_HomeTab.menu),
              avatarUrl: widget.account?.avatarUrl,
              onProfileAction: (action) {
                if (action == _ProfileAction.logout) {
                  unawaited(widget.onLogout());
                  return;
                }
                if (action == _ProfileAction.profile) {
                  final account = widget.account;
                  if (account != null) {
                    StickerlySfx.play(StickerlyAssets.soundPage);
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _MyPage(
                          account: account,
                          onAccountUpdated: widget.onAccountUpdated,
                          onAvatarUpdated: widget.onAvatarUpdated,
                        ),
                      ),
                    );
                  }
                  return;
                }
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('설정은 준비 중이에요.')));
              },
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  if (_controller.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (_controller.error != null) {
                    return _ErrorState(onRetry: _controller.initialize);
                  }
                  return switch (_tab) {
                    _HomeTab.menu => _buildHomeMenu(),
                    _HomeTab.stickerBook => _buildStickerBook(),
                    _HomeTab.drawer => _buildDrawer(),
                  };
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeMenu() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        final cards = [
          _HomeMenuCard(
            title: '스티커북',
            subtitle: '스티커북 꾸미기',
            icon: Icons.auto_stories_rounded,
            colors: const [Color(0xFFF4A0B9), Color(0xFFFFD8C2)],
            onTap: () => _setHomeTab(_HomeTab.stickerBook),
          ),
          _HomeMenuCard(
            title: '내 스티커',
            subtitle: '내가 가진 스티커팩',
            icon: Icons.inventory_2_rounded,
            colors: const [Color(0xFFB8C5E0), Color(0xFFC8DDC8)],
            onTap: () => _setHomeTab(_HomeTab.drawer),
          ),
        ];
        return Padding(
          padding: EdgeInsets.fromLTRB(
            landscape ? 16 : 20,
            landscape ? 8 : 8,
            landscape ? 16 : 20,
            landscape ? 12 : 18,
          ),
          child: Column(
            children: [
              Expanded(
                child: Transform.translate(
                  offset: Offset(0, landscape ? -8 : -16),
                  child: landscape
                      ? Row(
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 18),
                            Expanded(child: cards[1]),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 170,
                              child: cards[0],
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 170,
                              child: cards[1],
                            ),
                          ],
                        ),
                ),
              ),
              Transform.translate(
                offset: Offset(0, landscape ? 4 : 8),
                child: SizedBox(
                  width: constraints.maxWidth + 80,
                  child: const _HomeAdPlaceholder(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStickerBook() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth >= 761 ? 200.0 : 148.0;
        final columns = (constraints.maxWidth / (cardWidth + 14)).floor().clamp(
          2,
          6,
        );
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.9,
          ),
          itemCount: _controller.projects.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _NewProjectCard(
                onTap: () => _showNewProjectDialog(context),
              );
            }
            final project = _controller.projects[index - 1];
            return _ProjectCard(
              project: project,
              catalog: _controller.catalog,
              onOpen: () => _openProject(project),
              onDelete: () => _confirmDeleteProject(project),
              onDuplicate: () => _controller.duplicateProject(project),
              onRename: () => _showRenameDialog(context, project),
            );
          },
        );
      },
    );
  }

  Widget _buildDrawer() {
    final query = _packQuery.trim().toLowerCase();
    final packs = _controller.packs
        .where((pack) => pack.name.toLowerCase().contains(query))
        .toList();
    final hiddenCount = _hiddenPackIds.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () {
                  StickerlySfx.play(StickerlyAssets.soundPage);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _StoreScreen(
                        account: widget.account,
                        catalog: _controller.catalog,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.storefront_rounded),
                label: const Text('상점'),
                style: FilledButton.styleFrom(
                  foregroundColor: StickerlyColors.ink,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: StickerlyColors.line, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: TextField(
              onChanged: (value) => setState(() => _packQuery = value),
              decoration: InputDecoration(
                hintText: '팩 이름 검색',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: StickerlyColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: StickerlyColors.line,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: hiddenCount == 0
              ? const SizedBox(height: 4)
              : Padding(
                  key: ValueKey(hiddenCount),
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '$hiddenCount개 팩 숨김 · 숨긴 팩은 편집기 목록에서 빠져요',
                    style: const TextStyle(
                      color: Color(0xFF8B8194),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ),
        Expanded(
          child: packs.isEmpty
              ? const Center(child: Text('찾는 팩이 없어요'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final pack in packs)
                          SizedBox(
                            width: 152,
                            height: 184,
                            child: _DrawerPackCard(
                              pack: pack,
                              catalog: _controller.catalog,
                              enabled: !_hiddenPackIds.contains(pack.id),
                              downloading: pack.stickers.any(
                                (item) => _controller.downloadingAssetIds
                                    .contains(item.id),
                              ),
                              onChanged: (value) =>
                                  unawaited(_setPackEnabled(pack.id, value)),
                              onDownload: () =>
                                  unawaited(_controller.downloadPack(pack)),
                              onOpen: () => _openPackDetails(pack),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _showNewProjectDialog(BuildContext context) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) =>
            const _ProjectNameScreen(title: '새 스티커북', actionLabel: '만들기'),
      ),
    );
    if (result == null) return;
    final projectTitle = result.trim().isEmpty
        ? _nextStickerBookTitle()
        : result.trim();
    final project = await _controller.createProject(
      title: projectTitle,
      preset: CanvasPreset.square,
    );
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await _openProject(project);
  }

  String _nextStickerBookTitle() {
    final existing = _controller.projects
        .map((project) => project.title)
        .toSet();
    var index = 1;
    while (existing.contains('스티커북 $index')) {
      index += 1;
    }
    return '스티커북 $index';
  }

  Future<void> _confirmDeleteProject(StickerProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('스티커북 삭제'),
        content: Text('"${project.title}"을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: StickerlyColors.danger,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _controller.deleteProject(project);
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    StickerProject project,
  ) async {
    final title = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => _ProjectNameScreen(
          title: '이름 바꾸기',
          actionLabel: '저장',
          initialValue: project.title,
        ),
      ),
    );
    if (title != null) await _controller.renameProject(project, title);
  }

  Future<void> _openProject(StickerProject project) async {
    StickerlySfx.play(StickerlyAssets.soundPage);
    await _controller.initialize();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => EditorScreen(
          project: project,
          repository: widget.repository,
          catalog: _controller.catalog,
          hiddenPackIds: _hiddenPackIds,
          onDownloadPack: _controller.downloadPack,
        ),
      ),
    );
    await _controller.initialize();
  }

  Future<void> _openPackDetails(StickerPack pack) async {
    StickerlySfx.play(StickerlyAssets.soundPage);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _PackDetailsScreen(pack: pack, catalog: _controller.catalog),
      ),
    );
  }
}

class _ProjectNameScreen extends StatefulWidget {
  const _ProjectNameScreen({
    required this.title,
    required this.actionLabel,
    this.initialValue = '',
  });

  final String title;
  final String actionLabel;
  final String initialValue;

  @override
  State<_ProjectNameScreen> createState() => _ProjectNameScreenState();
}

class _ProjectNameScreenState extends State<_ProjectNameScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            StickerlySfx.play(StickerlyAssets.soundPage);
            Navigator.pop(context);
          },
          icon: Image.asset(StickerlyAssets.back, width: 24, height: 24),
        ),
        title: Text(widget.title),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: 40,
                decoration: const InputDecoration(hintText: '스티커북 이름'),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.message,
    required this.showWelcome,
    required this.showBack,
    required this.onBack,
    required this.avatarUrl,
    required this.onProfileAction,
  });

  final String message;
  final bool showWelcome;
  final bool showBack;
  final VoidCallback onBack;
  final String? avatarUrl;
  final ValueChanged<_ProfileAction> onProfileAction;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final mobile = size.width <= 760 || landscape;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFFFF0DC),
            Color(0xFFFFE2D6),
            Color(0xFFF4E5EA),
            Color(0xFFE8E1F1),
          ],
        ),
        border: Border(bottom: BorderSide(color: StickerlyColors.line)),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              landscape ? 6 : 16,
              landscape ? 2.4 : (mobile ? 9 : 16),
              landscape ? 6 : 16,
              landscape ? 2.4 : 9,
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: showBack ? onBack : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: landscape ? 2.4 : 4,
                    ),
                    child: StickerlyWordmark(
                      scale: showBack
                          ? (landscape ? 0.45 : 0.72)
                          : (landscape ? 0.6 : 1),
                    ),
                  ),
                ),
                if (showBack) ...[
                  SizedBox(width: landscape ? 6 : 10),
                  InkWell(
                    onTap: onBack,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: landscape ? 1.8 : 3,
                        vertical: landscape ? 3.6 : 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            StickerlyAssets.back,
                            width: landscape ? 18 : 30,
                            height: landscape ? 18 : 30,
                          ),
                          Text(
                            message,
                            style: TextStyle(
                              color: StickerlyColors.inkSoft,
                              fontSize: landscape ? 15 : 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (!mobile) ...[
                  const SizedBox(width: 18),
                  if (!showBack)
                    Expanded(child: Text(message))
                  else
                    const Spacer(),
                ] else
                  const Spacer(),
                _ProfileMenuButton(
                  compact: landscape,
                  avatarUrl: avatarUrl,
                  onSelected: onProfileAction,
                ),
              ],
            ),
          ),
          if (!landscape && mobile && showWelcome)
            Container(
              width: double.infinity,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.52),
                border: const Border(
                  top: BorderSide(color: StickerlyColors.line),
                ),
              ),
              child: ClipRect(child: _SlotMachineWelcomeText(message: message)),
            ),
        ],
      ),
    );
  }
}

class _SlotMachineWelcomeText extends StatefulWidget {
  const _SlotMachineWelcomeText({required this.message});

  final String message;

  @override
  State<_SlotMachineWelcomeText> createState() =>
      _SlotMachineWelcomeTextState();
}

class _SlotMachineWelcomeTextState extends State<_SlotMachineWelcomeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  String? _previousMessage;
  late String _currentMessage;

  @override
  void initState() {
    super.initState();
    _currentMessage = widget.message;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..value = 1;
  }

  @override
  void didUpdateWidget(covariant _SlotMachineWelcomeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message == widget.message) return;
    _previousMessage = _currentMessage;
    _currentMessage = widget.message;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 25, fontWeight: FontWeight.w400);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final progress = Curves.easeInOutCubic.transform(_controller.value);
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (_previousMessage != null && progress < 1)
                  Transform.translate(
                    offset: Offset(0, height * progress),
                    child: Center(child: Text(_previousMessage!, style: style)),
                  ),
                Transform.translate(
                  offset: Offset(0, height * (progress - 1)),
                  child: Center(child: Text(_currentMessage, style: style)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

enum _ProfileAction { profile, settings, logout }

class _MyPage extends StatefulWidget {
  const _MyPage({
    required this.account,
    required this.onAccountUpdated,
    required this.onAvatarUpdated,
  });

  final AccountProfile account;
  final Future<AccountProfile> Function(String displayName) onAccountUpdated;
  final Future<AccountProfile> Function(String imagePath) onAvatarUpdated;

  @override
  State<_MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<_MyPage> {
  late AccountProfile _account = widget.account;
  var _savingName = false;
  var _savingAvatar = false;

  Future<void> _editName() async {
    final controller = TextEditingController(text: _account.displayName);
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('닉네임 수정'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '닉네임'),
          onSubmitted: (value) {
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.pop(context, value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(context);
            },
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.pop(context, controller.text);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    final trimmed = nextName?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == _account.displayName) {
      return;
    }
    setState(() => _savingName = true);
    try {
      final updated = await widget.onAccountUpdated(trimmed);
      if (!mounted) return;
      setState(() => _account = updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('닉네임을 바꿨어요.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('닉네임 저장에 실패했어요. SQL을 다시 실행해 주세요.')),
      );
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _editAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 88,
    );
    if (picked == null) return;
    setState(() => _savingAvatar = true);
    try {
      final updated = await widget.onAvatarUpdated(picked.path);
      if (!mounted) return;
      setState(() => _account = updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('프로필 사진을 바꿨어요.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('프로필 사진 저장에 실패했어요. SQL을 다시 실행해 주세요.')),
      );
    } finally {
      if (mounted) setState(() => _savingAvatar = false);
    }
  }

  void _showPointPlaceholder() {
    StickerlySfx.play(StickerlyAssets.soundPage);
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const _PointStoreScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StickerlyColors.paper,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Image.asset(StickerlyAssets.back, width: 24, height: 24),
        ),
        title: const Text('마이페이지'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: Colors.white,
                    backgroundImage: _account.avatarUrl == null
                        ? null
                        : NetworkImage(_account.avatarUrl!),
                    child: _account.avatarUrl == null
                        ? const Icon(Icons.person_rounded, size: 52)
                        : null,
                  ),
                  Positioned(
                    right: -6,
                    bottom: -6,
                    child: Material(
                      color: StickerlyColors.pink,
                      shape: const CircleBorder(),
                      elevation: 4,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _savingAvatar ? null : _editAvatar,
                        child: SizedBox.square(
                          dimension: 42,
                          child: Center(
                            child: _savingAvatar
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Image.asset(
                                    StickerlyAssets.edit,
                                    width: 22,
                                    height: 22,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: InkWell(
                onTap: _savingName ? null : _editName,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _account.displayName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _savingName
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.edit_rounded, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            Text(
              _account.email,
              textAlign: TextAlign.center,
              style: const TextStyle(color: StickerlyColors.inkSoft),
            ),
            const SizedBox(height: 28),
            _AccountInfoCard(
              icon: Icons.toll_rounded,
              label: '보유 포인트',
              value: '${_formatPoints(_account.points)} P',
              trailing: FilledButton.tonal(
                onPressed: _showPointPlaceholder,
                child: const Text('충전'),
              ),
            ),
            const SizedBox(height: 12),
            _AccountInfoCard(
              icon: Icons.collections_bookmark_rounded,
              label: '사용 가능한 어셋 팩',
              value: '${_account.packIds.length}개',
            ),
          ],
        ),
      ),
    );
  }

  static String _formatPoints(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }
}

class _AccountInfoCard extends StatelessWidget {
  const _AccountInfoCard({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: StickerlyColors.line),
      ),
      child: Row(
        children: [
          Icon(icon, color: StickerlyColors.pink, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

class _StoreProduct {
  const _StoreProduct({
    required this.id,
    required this.name,
    required this.description,
    required this.priceAmount,
    required this.currency,
    required this.createdAt,
    required this.packIds,
    required this.catalogPackIds,
    this.thumbnailUrl,
  });

  final String id;
  final String name;
  final String description;
  final int priceAmount;
  final String currency;
  final DateTime createdAt;
  final List<String> packIds;
  final List<String> catalogPackIds;
  final String? thumbnailUrl;
}

class _StoreScreen extends StatefulWidget {
  const _StoreScreen({required this.account, required this.catalog});

  final AccountProfile? account;
  final AssetCatalog catalog;

  @override
  State<_StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<_StoreScreen> {
  final _searchController = TextEditingController();
  var _sort = _StoreSort.latest;
  var _loading = true;
  var _buyingProductId = '';
  String? _error;
  var _products = <_StoreProduct>[];
  late int _points = widget.account?.points ?? 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProducts());
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('products')
          .select(
            'id,name,description,price_amount,currency,thumbnail_storage_path,created_at,product_packs(pack_id,sticker_packs(legacy_id))',
          )
          .eq('published', true);
      final products = <_StoreProduct>[];
      for (final row in (rows as List<dynamic>).cast<Map<String, dynamic>>()) {
        final productPackRows =
            (row['product_packs'] as List<dynamic>? ?? const [])
                .cast<Map<String, dynamic>>();
        final packIds = productPackRows
            .map((item) => item['pack_id'] as String)
            .toList(growable: false);
        final catalogPackIds = productPackRows
            .map(
              (item) =>
                  (item['sticker_packs'] as Map<String, dynamic>?)?['legacy_id']
                      as String? ??
                  item['pack_id'] as String,
            )
            .toList(growable: false);
        final thumbnailPath = row['thumbnail_storage_path'] as String?;
        String? thumbnailUrl;
        if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
          try {
            thumbnailUrl = await client.storage
                .from('assets')
                .createSignedUrl(thumbnailPath, 3600);
          } catch (_) {
            thumbnailUrl = null;
          }
        }
        thumbnailUrl ??= catalogPackIds
            .map(
              (id) => widget.catalog.packs
                  .where((pack) => pack.id == id)
                  .firstOrNull
                  ?.thumbnail,
            )
            .whereType<String>()
            .where((path) => path.isNotEmpty)
            .firstOrNull;
        thumbnailUrl ??= catalogPackIds
            .map(
              (id) => widget.catalog.packs
                  .where((pack) => pack.id == id)
                  .firstOrNull
                  ?.stickers
                  .firstOrNull
                  ?.assetPath,
            )
            .whereType<String>()
            .where((path) => path.isNotEmpty)
            .firstOrNull;
        products.add(
          _StoreProduct(
            id: row['id'] as String,
            name: row['name'] as String? ?? '상품',
            description: row['description'] as String? ?? '',
            priceAmount: (row['price_amount'] as num?)?.toInt() ?? 0,
            currency: row['currency'] as String? ?? 'KRW',
            packIds: packIds,
            catalogPackIds: catalogPackIds,
            createdAt:
                DateTime.tryParse(row['created_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
            thumbnailUrl: thumbnailUrl,
          ),
        );
      }
      if (!mounted) return;
      setState(() => _products = products);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '상품을 불러오지 못했어요.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_StoreProduct> get _visibleProducts {
    final query = _searchController.text.trim().toLowerCase();
    final visible = _products
        .where(
          (product) =>
              query.isEmpty ||
              product.name.toLowerCase().contains(query) ||
              product.description.toLowerCase().contains(query),
        )
        .toList();
    switch (_sort) {
      case _StoreSort.latest:
        visible.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _StoreSort.price:
        visible.sort((a, b) => a.priceAmount.compareTo(b.priceAmount));
      case _StoreSort.name:
        visible.sort((a, b) => a.name.compareTo(b.name));
    }
    return visible;
  }

  Future<void> _goToPointStore() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const _PointStoreScreen()));
  }

  Future<bool> _confirmCharge() async {
    final charge = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('포인트가 모자라요'),
        content: const Text('충전할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('아니요'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('예'),
          ),
        ],
      ),
    );
    return charge == true;
  }

  Future<void> _buyProduct(_StoreProduct product) async {
    if (widget.account == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인이 필요해요.')));
      return;
    }
    if (_points < product.priceAmount) {
      if (await _confirmCharge() && mounted) await _goToPointStore();
      return;
    }
    setState(() => _buyingProductId = product.id);
    try {
      final row = await Supabase.instance.client.rpc(
        'purchase_product_with_points',
        params: {'target_product_id': product.id},
      );
      if (!mounted) return;
      final data = row as Map<String, dynamic>;
      setState(() => _points = (data['points'] as num).toInt());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${product.name} 구매 완료!')));
    } on PostgrestException catch (error) {
      if (!mounted) return;
      if (error.message.contains('INSUFFICIENT_POINTS')) {
        if (await _confirmCharge() && mounted) await _goToPointStore();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('구매에 실패했어요.')));
      }
    } finally {
      if (mounted) setState(() => _buyingProductId = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _visibleProducts;
    return Scaffold(
      backgroundColor: StickerlyColors.paper,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Image.asset(StickerlyAssets.back, width: 24, height: 24),
        ),
        title: const Text('상점'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Text(
                '${_points.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',')} P',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '상품 검색',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                          color: StickerlyColors.line,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                          color: StickerlyColors.line,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<_StoreSort>(
                    segments: const [
                      ButtonSegment(
                        value: _StoreSort.latest,
                        label: Text('최신순'),
                        icon: Icon(Icons.schedule_rounded),
                      ),
                      ButtonSegment(
                        value: _StoreSort.price,
                        label: Text('가격순'),
                        icon: Icon(Icons.payments_rounded),
                      ),
                      ButtonSegment(
                        value: _StoreSort.name,
                        label: Text('이름순'),
                        icon: Icon(Icons.sort_by_alpha_rounded),
                      ),
                    ],
                    selected: {_sort},
                    onSelectionChanged: (value) {
                      StickerlySfx.play(StickerlyAssets.soundFlip);
                      setState(() => _sort = value.single);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (_loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (_error != null) {
                    return _ErrorState(onRetry: _loadProducts);
                  }
                  if (products.isEmpty) {
                    return const Center(child: Text('상품이 없어요.'));
                  }
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth > 760
                          ? 3
                          : constraints.maxWidth > 500
                          ? 2
                          : 1;
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: columns == 1 ? 1.05 : 0.78,
                        ),
                        itemCount: products.length,
                        itemBuilder: (context, index) => _StoreProductCard(
                          product: products[index],
                          buying: _buyingProductId == products[index].id,
                          onOpen: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _ProductDetailsScreen(
                                product: products[index],
                                catalog: widget.catalog,
                                onBuy: () => _buyProduct(products[index]),
                              ),
                            ),
                          ),
                          onBuy: () => _buyProduct(products[index]),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreProductCard extends StatelessWidget {
  const _StoreProductCard({
    required this.product,
    required this.buying,
    required this.onOpen,
    required this.onBuy,
  });

  final _StoreProduct product;
  final bool buying;
  final VoidCallback onOpen;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: StickerlyColors.line, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Color(0xFFFFF4F9)),
                child: product.thumbnailUrl == null
                    ? const Icon(
                        Icons.storefront_rounded,
                        size: 58,
                        color: StickerlyColors.pink,
                      )
                    : Image.network(product.thumbnailUrl!, fit: BoxFit.cover),
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Text(
                        product.description.isEmpty
                            ? '상품 설명이 없어요.'
                            : product.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: StickerlyColors.inkSoft,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${product.priceAmount.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',')} ${product.currency}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: StickerlyColors.purple,
                            ),
                          ),
                        ),
                        FilledButton(
                          onPressed: buying ? null : onBuy,
                          child: buying
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('구매'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductDetailsScreen extends StatefulWidget {
  const _ProductDetailsScreen({
    required this.product,
    required this.catalog,
    required this.onBuy,
  });

  final _StoreProduct product;
  final AssetCatalog catalog;
  final VoidCallback onBuy;

  @override
  State<_ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<_ProductDetailsScreen> {
  var _remoteStickerPaths = <String>[];
  var _remoteBackgroundPaths = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_loadRemoteAssets());
  }

  Future<void> _loadRemoteAssets() async {
    if (widget.product.packIds.isEmpty) return;
    try {
      final client = Supabase.instance.client;
      final results = await Future.wait([
        client
            .from('stickers')
            .select('storage_path')
            .inFilter('pack_id', widget.product.packIds)
            .order('position'),
        client
            .from('backgrounds')
            .select('storage_path')
            .inFilter('pack_id', widget.product.packIds)
            .order('position'),
      ]);
      Future<List<String>> signed(List<dynamic> rows) async {
        final paths = <String>[];
        for (final row in rows.cast<Map<String, dynamic>>()) {
          final storagePath = row['storage_path'] as String?;
          if (storagePath == null || storagePath.isEmpty) continue;
          try {
            paths.add(
              await client.storage
                  .from('assets')
                  .createSignedUrl(storagePath, 3600),
            );
          } catch (_) {}
        }
        return paths;
      }

      final stickerPaths = await signed(results[0] as List<dynamic>);
      final backgroundPaths = await signed(results[1] as List<dynamic>);
      if (!mounted) return;
      setState(() {
        _remoteStickerPaths = stickerPaths;
        _remoteBackgroundPaths = backgroundPaths;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final packs = product.catalogPackIds
        .map(
          (id) =>
              widget.catalog.packs.where((pack) => pack.id == id).firstOrNull,
        )
        .whereType<StickerPack>()
        .toList(growable: false);
    final backgroundPaths = _remoteBackgroundPaths.isNotEmpty
        ? _remoteBackgroundPaths
        : widget.catalog.backgrounds
              .where(
                (item) =>
                    packs.any((pack) => pack.backgroundIds.contains(item.id)),
              )
              .map((item) => item.assetPath)
              .toList(growable: false);
    final stickerPaths = _remoteStickerPaths.isNotEmpty
        ? _remoteStickerPaths
        : packs
              .expand((pack) => pack.stickers)
              .map((item) => item.assetPath)
              .toList(growable: false);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: StickerlyColors.paper,
        appBar: AppBar(
          title: Text(
            product.name,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 96,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: product.thumbnailUrl == null
                              ? const ColoredBox(
                                  color: Color(0xFFFFF4F9),
                                  child: Icon(
                                    Icons.storefront_rounded,
                                    color: StickerlyColors.pink,
                                    size: 42,
                                  ),
                                )
                              : AssetFileImage(
                                  path: product.thumbnailUrl!,
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              product.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              product.description.isEmpty
                                  ? '상품 설명이 없어요.'
                                  : product.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: StickerlyColors.inkSoft,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${product.priceAmount.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',')} ${product.currency}',
                                    style: const TextStyle(
                                      color: StickerlyColors.purple,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                FilledButton(
                                  onPressed: widget.onBuy,
                                  child: const Text('구매'),
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
            const TabBar(
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorWeight: 4,
              labelColor: StickerlyColors.ink,
              unselectedLabelColor: StickerlyColors.inkSoft,
              tabs: [
                Tab(text: '배경'),
                Tab(text: '스티커'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _AssetThumbnailGrid(
                    paths: backgroundPaths,
                    fit: BoxFit.cover,
                  ),
                  _AssetThumbnailGrid(paths: stickerPaths, fit: BoxFit.contain),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PointStoreScreen extends StatefulWidget {
  const _PointStoreScreen();

  @override
  State<_PointStoreScreen> createState() => _PointStoreScreenState();
}

class _PointStoreScreenState extends State<_PointStoreScreen> {
  static const _presets = [
    (price: 1000, base: 1000, bonus: 0),
    (price: 3000, base: 3000, bonus: 0),
    (price: 6000, base: 5000, bonus: 1000),
    (price: 10000, base: 10000, bonus: 2000),
  ];
  var _selected = 1000;

  ({int price, int base, int bonus}) get _selectedPreset =>
      _presets.firstWhere((preset) => preset.price == _selected);

  int get _points => _selectedPreset.base + _selectedPreset.bonus;

  void _buyPlaceholder() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${_selected.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',')}원 충전은 준비 중이에요.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StickerlyColors.paper,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Image.asset(StickerlyAssets.back, width: 24, height: 24),
        ),
        title: const Text('포인트 충전'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '충전할 포인트를 골라주세요',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView.separated(
                  itemCount: _presets.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final preset = _presets[index];
                    final price = preset.price;
                    final points = preset.base + preset.bonus;
                    final selected = price == _selected;
                    return InkWell(
                      onTap: () {
                        StickerlySfx.play(StickerlyAssets.soundFlip);
                        setState(() => _selected = price);
                      },
                      borderRadius: BorderRadius.circular(24),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: selected ? StickerlyColors.pink : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: selected
                                ? StickerlyColors.pink
                                : StickerlyColors.line,
                            width: 2,
                          ),
                          boxShadow: [
                            if (selected)
                              BoxShadow(
                                color: StickerlyColors.pink.withValues(
                                  alpha: 0.25,
                                ),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 104,
                              decoration: BoxDecoration(
                                color: selected
                                    ? Colors.white.withValues(alpha: 0.18)
                                    : const Color(0xFFFFF4F9),
                                borderRadius: BorderRadius.circular(28),
                              ),
                              child: Icon(
                                Icons.toll_rounded,
                                size: 34,
                                color: selected
                                    ? Colors.white
                                    : StickerlyColors.purple,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    preset.bonus > 0
                                        ? '${preset.base.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',')} + ${preset.bonus.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',')} P'
                                        : '${points.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',')} P',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 25,
                                      fontWeight: FontWeight.w900,
                                      color: selected
                                          ? Colors.white
                                          : StickerlyColors.ink,
                                    ),
                                  ),
                                  if (preset.bonus > 0)
                                    Text(
                                      '총 ${points.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',')} P',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: selected
                                            ? Colors.white.withValues(
                                                alpha: 0.88,
                                              )
                                            : StickerlyColors.purple,
                                      ),
                                    ),
                                  Text(
                                    '${price.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',')}원',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: selected
                                          ? Colors.white.withValues(alpha: 0.88)
                                          : StickerlyColors.inkSoft,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _buyPlaceholder,
                icon: const Icon(Icons.shopping_bag_rounded),
                label: Text(
                  '${_points.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',')} P 충전',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  textStyle: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '결제 연결은 다음 단계에서 인앱결제로 붙일 예정이에요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: StickerlyColors.inkSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileMenuButton extends StatelessWidget {
  const _ProfileMenuButton({
    required this.onSelected,
    this.avatarUrl,
    this.compact = false,
  });

  final ValueChanged<_ProfileAction> onSelected;
  final String? avatarUrl;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: compact ? 8 : 15),
      child: PopupMenuButton<_ProfileAction>(
        onSelected: onSelected,
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: _ProfileAction.profile,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.person_rounded),
              title: Text('마이페이지'),
            ),
          ),
          PopupMenuItem(
            value: _ProfileAction.settings,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.settings_rounded),
              title: Text('설정'),
            ),
          ),
          PopupMenuItem(
            value: _ProfileAction.logout,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.logout_rounded),
              title: Text('로그아웃'),
            ),
          ),
        ],
        child: Container(
          width: compact ? 40 : 46,
          height: compact ? 40 : 46,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.86),
            shape: BoxShape.circle,
            border: Border.all(color: StickerlyColors.ink, width: 2.2),
          ),
          clipBehavior: Clip.antiAlias,
          child: avatarUrl == null || avatarUrl!.isEmpty
              ? Icon(Icons.person_rounded, size: compact ? 14.4 : 24)
              : Image.network(
                  avatarUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      Icon(Icons.person_rounded, size: compact ? 14.4 : 24),
                ),
        ),
      ),
    );
  }
}

class _HomeAdPlaceholder extends StatelessWidget {
  const _HomeAdPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 135,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: StickerlyColors.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: StickerlyColors.ink.withValues(alpha: 0.28),
          width: 1.5,
        ),
      ),
      child: const Text(
        '배너 광고',
        style: TextStyle(
          color: StickerlyColors.inkSoft,
          fontSize: 15,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _HomeMenuCard extends StatelessWidget {
  const _HomeMenuCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(30),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: StickerlyColors.ink.withValues(alpha: 0.72),
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: StickerlyColors.ink.withValues(alpha: 0.14),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: StickerlyColors.ink, size: 42),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: StickerlyColors.ink,
                    fontSize: 29,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    style: const TextStyle(
                      color: StickerlyColors.inkSoft,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectCard extends StatefulWidget {
  const _ProjectCard({
    required this.project,
    required this.catalog,
    required this.onOpen,
    required this.onDelete,
    required this.onDuplicate,
    required this.onRename,
  });

  final StickerProject project;
  final AssetCatalog catalog;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onRename;

  @override
  State<_ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<_ProjectCard> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final background = widget.catalog.backgrounds
        .where((item) => item.id == project.background?.id)
        .firstOrNull;
    final topSticker = [...project.stickerItems]
      ..sort((a, b) => b.zIndex.compareTo(a.zIndex));
    final stickerPath = topSticker.isEmpty
        ? null
        : widget.catalog.packs
              .where((pack) => pack.id == topSticker.first.packId)
              .firstOrNull
              ?.stickers
              .where((asset) => asset.id == topSticker.first.assetId)
              .firstOrNull
              ?.assetPath;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      elevation: 3,
      shadowColor: StickerlyColors.ink.withValues(alpha: 0.16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpen,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  if (project.thumbnailPath?.isNotEmpty == true)
                    AssetFileImage(
                      path: project.thumbnailPath!,
                      fit: BoxFit.cover,
                    )
                  else ...[
                    _DottedPreviewBackground(assetPath: background?.assetPath),
                    if (stickerPath != null)
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: AssetFileImage(
                          path: stickerPath,
                          fit: BoxFit.contain,
                        ),
                      ),
                  ],
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 7, 7, 9),
              color: Colors.white,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          project.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        visualDensity: VisualDensity.compact,
                        icon: Image.asset(
                          _expanded ? StickerlyAssets.up : StickerlyAssets.down,
                          width: 22,
                          height: 22,
                        ),
                      ),
                    ],
                  ),
                  if (_expanded) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _formatProjectDate(project.updatedAt),
                        style: const TextStyle(
                          color: StickerlyColors.inkSoft,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Spacer(),
                        TextButton(
                          onPressed: widget.onDuplicate,
                          style: TextButton.styleFrom(
                            backgroundColor: const Color(0xFFF1ECFF),
                            foregroundColor: const Color(0xFF6E54C9),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                          ),
                          child: const Text('복제'),
                        ),
                        TextButton(
                          onPressed: widget.onDelete,
                          style: TextButton.styleFrom(
                            backgroundColor: const Color(0xFFFFE8EF),
                            foregroundColor: StickerlyColors.danger,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                          ),
                          child: const Text('삭제'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatProjectDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}.${two(date.month)}.${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}

class _NewProjectCard extends StatelessWidget {
  const _NewProjectCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.86),
      borderRadius: BorderRadius.circular(15),
      elevation: 2,
      shadowColor: StickerlyColors.ink.withValues(alpha: 0.12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: CustomPaint(
          painter: _DotPainter(),
          child: Center(
            child: Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [StickerlyColors.pink, Color(0xFFFF91C5)],
                ),
              ),
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 42,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DottedPreviewBackground extends StatelessWidget {
  const _DottedPreviewBackground({this.assetPath});

  final String? assetPath;

  @override
  Widget build(BuildContext context) {
    if (assetPath != null && assetPath!.isNotEmpty) {
      return AssetFileImage(path: assetPath!, fit: BoxFit.cover);
    }
    return CustomPaint(painter: _DotPainter());
  }
}

class _DotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xFFFFF9F1), BlendMode.src);
    final paint = Paint()..color = StickerlyColors.ink.withValues(alpha: 0.1);
    for (double y = 1; y < size.height; y += 16) {
      for (double x = 1; x < size.width; x += 16) {
        canvas.drawCircle(Offset(x, y), 1.4, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DrawerPackCard extends StatelessWidget {
  const _DrawerPackCard({
    required this.pack,
    required this.catalog,
    required this.enabled,
    required this.downloading,
    required this.onChanged,
    required this.onDownload,
    required this.onOpen,
  });

  final StickerPack pack;
  final AssetCatalog catalog;
  final bool enabled;
  final bool downloading;
  final ValueChanged<bool> onChanged;
  final VoidCallback onDownload;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final background = catalog.backgrounds
        .where((item) => pack.backgroundIds.contains(item.id))
        .firstOrNull;
    final firstSticker = pack.stickers.firstOrNull;
    final needsDownload =
        pack.stickers.any((item) => !item.isUsable) ||
        (background != null && !background.isUsable);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: const BorderSide(color: StickerlyColors.line, width: 2),
        ),
        elevation: 4,
        shadowColor: StickerlyColors.ink.withValues(alpha: 0.18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      alignment: Alignment.center,
                      children: [
                        if (background != null && background.isUsable)
                          AssetFileImage(
                            path: background.assetPath,
                            fit: BoxFit.cover,
                          )
                        else
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFFFFF0F6), Color(0xFFEDF8FF)],
                              ),
                            ),
                          ),
                        if (firstSticker != null && firstSticker.isUsable)
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: AssetFileImage(
                              path: firstSticker.assetPath,
                              fit: BoxFit.contain,
                            ),
                          ),
                        if (needsDownload)
                          Center(
                            child: IconButton.filledTonal(
                              onPressed: downloading ? null : onDownload,
                              icon: downloading
                                  ? const SizedBox.square(
                                      dimension: 17,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.download_rounded),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    color: Colors.white,
                    child: Text(
                      pack.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                right: 2,
                top: 2,
                child: Transform.scale(
                  scale: 0.68,
                  alignment: Alignment.topRight,
                  child: Switch(
                    value: enabled,
                    activeThumbColor: StickerlyColors.pink,
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackDetailsScreen extends StatelessWidget {
  const _PackDetailsScreen({required this.pack, required this.catalog});

  final StickerPack pack;
  final AssetCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final backgrounds = catalog.backgrounds
        .where((item) => pack.backgroundIds.contains(item.id))
        .toList(growable: false);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: StickerlyColors.paper,
        appBar: AppBar(
          title: Text(
            pack.name,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Material(
                  color: Colors.white,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                    side: const BorderSide(
                      color: StickerlyColors.line,
                      width: 2,
                    ),
                  ),
                  child: _PackHeroThumbnail(
                    pack: pack,
                    background: backgrounds.firstOrNull,
                  ),
                ),
              ),
            ),
            const TabBar(
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorWeight: 4,
              labelColor: StickerlyColors.ink,
              unselectedLabelColor: StickerlyColors.inkSoft,
              tabs: [
                Tab(text: '배경'),
                Tab(text: '스티커'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _AssetThumbnailGrid(
                    paths: backgrounds
                        .map((item) => item.assetPath)
                        .toList(growable: false),
                    fit: BoxFit.cover,
                  ),
                  _AssetThumbnailGrid(
                    paths: pack.stickers
                        .map((item) => item.assetPath)
                        .toList(growable: false),
                    fit: BoxFit.contain,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackHeroThumbnail extends StatelessWidget {
  const _PackHeroThumbnail({required this.pack, required this.background});

  final StickerPack pack;
  final BackgroundAsset? background;

  @override
  Widget build(BuildContext context) {
    if (pack.thumbnail.isNotEmpty) {
      return AssetFileImage(path: pack.thumbnail, fit: BoxFit.cover);
    }
    final sticker = pack.stickers.firstOrNull;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (background != null)
          AssetFileImage(path: background!.assetPath, fit: BoxFit.cover)
        else
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFFEDF4), Color(0xFFEAF5FF)],
              ),
            ),
          ),
        if (sticker != null)
          Padding(
            padding: const EdgeInsets.all(28),
            child: AssetFileImage(path: sticker.assetPath, fit: BoxFit.contain),
          ),
      ],
    );
  }
}

class _AssetThumbnailGrid extends StatelessWidget {
  const _AssetThumbnailGrid({required this.paths, required this.fit});

  final List<String> paths;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 112).floor().clamp(2, 6);
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: paths.length,
          itemBuilder: (context, index) =>
              _PreviewableAssetCard(path: paths[index], fit: fit),
        );
      },
    );
  }
}

class _PreviewableAssetCard extends StatelessWidget {
  const _PreviewableAssetCard({required this.path, required this.fit});

  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: StickerlyColors.line, width: 1.5),
      ),
      child: Padding(
        padding: fit == BoxFit.contain
            ? const EdgeInsets.all(8)
            : EdgeInsets.zero,
        child: AssetFileImage(path: path, fit: fit),
      ),
    );
    return LongPressDraggable<String>(
      data: path,
      dragAnchorStrategy: (_, _, _) => const Offset(88, 190),
      feedback: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: StickerlyColors.ink.withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: SizedBox.square(
            dimension: 176,
            child: Padding(
              padding: fit == BoxFit.contain
                  ? const EdgeInsets.all(14)
                  : EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AssetFileImage(path: path, fit: fit),
              ),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.55, child: card),
      child: card,
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton(onPressed: onRetry, child: const Text('다시 시도')),
    );
  }
}
