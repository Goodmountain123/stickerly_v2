import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stickerly_v2/app/assets/stickerly_assets.dart';
import 'package:stickerly_v2/app/theme/stickerly_colors.dart';
import 'package:stickerly_v2/app/widgets/asset_file_image.dart';
import 'package:stickerly_v2/app/widgets/back_chevron.dart';
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
    required this.onAccountRefresh,
    required this.onLogout,
    super.key,
  });

  final ProjectRepository repository;
  final AssetCatalogLoader assetCatalogLoader;
  final AccountProfile? account;
  final Future<AccountProfile> Function(String displayName) onAccountUpdated;
  final Future<AccountProfile> Function(String imagePath) onAvatarUpdated;
  final Future<AccountProfile> Function() onAccountRefresh;
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
  final _stickerBookPageController = PageController();
  Timer? _welcomeTimer;
  var _welcomeIndex = 0;
  var _tab = _HomeTab.menu;
  var _packQuery = '';
  var _drawerSort = _StoreSort.latest;
  var _drawerPage = 0;
  var _stickerBookPage = 0;
  var _hiddenPackIds = <String>{};
  var _tabTransitioning = false;
  var _projectOpening = false;

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

  Future<void> _openSettings() async {
    final account = widget.account;
    if (account == null) return;
    StickerlySfx.play(StickerlyAssets.soundPage);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SettingsScreen(
          account: account,
          onLogout: widget.onLogout,
        ),
      ),
    );
  }

  Future<void> _openMyPage() async {
    var account = widget.account;
    if (account == null) return;
    try {
      account = await widget.onAccountRefresh();
    } catch (_) {}
    if (!mounted) return;
    StickerlySfx.play(StickerlyAssets.soundPage);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _MyPage(
          account: account!,
          onAccountUpdated: widget.onAccountUpdated,
          onAvatarUpdated: widget.onAvatarUpdated,
          onAccountRefresh: widget.onAccountRefresh,
        ),
      ),
    );
  }

  Future<void> _openStore() async {
    StickerlySfx.play(StickerlyAssets.soundPage);
    final account = await Navigator.of(context).push<AccountProfile>(
      MaterialPageRoute<AccountProfile>(
        builder: (_) => _StoreScreen(
          account: widget.account,
          catalog: _controller.catalog,
          onAccountRefresh: widget.onAccountRefresh,
          onCatalogRefresh: () => _controller.refreshCatalog(),
        ),
      ),
    );
    if (account != null) unawaited(widget.onAccountRefresh());
  }

  Future<void> _setHomeTab(_HomeTab tab) async {
    if (_tab == tab || _tabTransitioning) return;
    if (_tab != tab) StickerlySfx.play(StickerlyAssets.soundPage);
    final shouldShowTransition =
        _tab == _HomeTab.stickerBook || tab == _HomeTab.stickerBook;
    if (shouldShowTransition) {
      setState(() => _tabTransitioning = true);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    setState(() => _tab = tab);
    if (tab == _HomeTab.drawer) {
      unawaited(_controller.refreshCatalog());
    }
    if (shouldShowTransition) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
      setState(() => _tabTransitioning = false);
    }
  }

  @override
  void dispose() {
    _welcomeTimer?.cancel();
    _stickerBookPageController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StickerlyColors.paper,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            Column(
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
                      unawaited(_openMyPage());
                      return;
                    }
                    if (action == _ProfileAction.settings) {
                      unawaited(_openSettings());
                      return;
                    }
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
                      if (_tabTransitioning) {
                        return const _StickerBookTransitionLoader();
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
            if (_projectOpening) const _ProjectTransitionLoader(),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeMenu() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        if (!landscape) {
          final scale = constraints.maxWidth / 390;
          return CustomPaint(
            painter: const _HomeDotPainter(),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned(
                        left: 16 * scale,
                        top: 120 * scale,
                        width: 357 * scale,
                        height: 167 * scale,
                        child: _HomeMenuCard(
                          title: '스티커북',
                          subtitle: '스티커북 꾸미기',
                          color: const Color(0xFFF6D4CF),
                          borderColor: const Color(0xFFC47165),
                          onTap: () => _setHomeTab(_HomeTab.stickerBook),
                        ),
                      ),
                      Positioned(
                        left: 16 * scale,
                        top: 304 * scale,
                        width: 172 * scale,
                        height: 167 * scale,
                        child: _HomeMenuCard(
                          title: '내 스티커',
                          subtitle: '내가 가진 스티커팩',
                          color: const Color(0xFFFFEDD8),
                          borderColor: const Color(0xFFCD9351),
                          onTap: () => _setHomeTab(_HomeTab.drawer),
                        ),
                      ),
                      Positioned(
                        left: 201 * scale,
                        top: 304 * scale,
                        width: 172 * scale,
                        height: 167 * scale,
                        child: _HomeMenuCard(
                          title: '상점',
                          subtitle: '새 팩 둘러보기',
                          color: const Color(0xFFEEDFFF),
                          borderColor: const Color(0xFF8E7AA3),
                          onTap: () => _openStore(),
                        ),
                      ),
                    ],
                  ),
                ),
                const _HomeAdPlaceholder(),
              ],
            ),
          );
        }
        final cards = [
          _HomeMenuCard(
            title: '스티커북',
            subtitle: '스티커북 꾸미기',
            color: const Color(0xFFF6D4CF),
            borderColor: const Color(0xFFD8695F),
            onTap: () => _setHomeTab(_HomeTab.stickerBook),
          ),
          _HomeMenuCard(
            title: '내 스티커',
            subtitle: '내가 가진 스티커팩',
            color: const Color(0xFFFFEDD8),
            borderColor: const Color(0xFFE09432),
            onTap: () => _setHomeTab(_HomeTab.drawer),
          ),
          _HomeMenuCard(
            title: '상점',
            subtitle: '새 팩 둘러보기',
            color: const Color(0xFFEEDFFF),
            borderColor: const Color(0xFF9F83CF),
            onTap: () => _openStore(),
          ),
        ];
        if (landscape) {
          final gap = (constraints.maxWidth * 0.017).clamp(10.0, 14.0);
          final sidePadding = (constraints.maxWidth * 0.012).clamp(6.0, 10.0);
          final topPadding = (constraints.maxHeight * 0.035).clamp(8.0, 12.0);
          final bottomPadding = topPadding;
          final availableWidth = constraints.maxWidth - sidePadding * 2 - gap;
          final leftWidth = (availableWidth * 0.53).clamp(
            260.0,
            availableWidth - 230.0,
          );
          final rightWidth = availableWidth - leftWidth - gap;
          return CustomPaint(
            painter: const _HomeDotPainter(),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                sidePadding,
                topPadding,
                sidePadding,
                bottomPadding,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: leftWidth, child: cards[0]),
                  SizedBox(width: gap),
                  SizedBox(
                    width: rightWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: cards[1]),
                              SizedBox(width: gap),
                              Expanded(child: cards[2]),
                            ],
                          ),
                        ),
                        SizedBox(height: gap),
                        const _HomeAdPlaceholder(banner: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          children: [
            Expanded(
              child: CustomPaint(
                painter: const _HomeDotPainter(),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    landscape ? 16 : 18,
                    landscape ? 8 : 88,
                    landscape ? 16 : 16,
                    landscape ? 4 : 18,
                  ),
                  child: landscape
                      ? Row(
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 14),
                            Expanded(child: cards[1]),
                            const SizedBox(width: 14),
                            Expanded(child: cards[2]),
                          ],
                        )
                      : Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 145,
                              child: cards[0],
                            ),
                            const SizedBox(height: 14),
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(child: cards[1]),
                                  const SizedBox(width: 14),
                                  Expanded(child: cards[2]),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            const _HomeAdPlaceholder(),
          ],
        );
      },
    );
  }

  Widget _buildStickerBook() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        // 태블릿: 짧은 변이 600 초과
        final shortSide =
            landscape ? constraints.maxHeight : constraints.maxWidth;
        final isTablet = shortSide > 600;
        // 태블릿 가로: 8장, 폰 가로: 4장, 세로: 6장
        final pageSize = landscape ? (isTablet ? 8 : 4) : 6;
        final itemCount = _controller.projects.length + 1;
        final pageCount = ((itemCount / pageSize).ceil()).clamp(1, 9999);
        final page = _stickerBookPage.clamp(0, pageCount - 1);

        if (page != _stickerBookPage) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _stickerBookPage = page);
            if (_stickerBookPageController.hasClients) {
              _stickerBookPageController.jumpToPage(page);
            }
          });
        }

        Widget cardFor(int index) {
          if (index == 0) {
            return _StickerBookNewTile(
              onTap: () => _showNewProjectDialog(context),
            );
          }
          final project = _controller.projects[index - 1];
          return _StickerBookGridTile(
            project: project,
            catalog: _controller.catalog,
            onOpen: () => _openProject(project),
            onDelete: () => _confirmDeleteProject(project),
            onDuplicate: () => _controller.duplicateProject(project),
            onRename: () => _showRenameDialog(context, project),
          );
        }

        return CustomPaint(
          painter: const _HomeDotPainter(),
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _stickerBookPageController,
                  itemCount: pageCount,
                  onPageChanged: (v) => setState(() => _stickerBookPage = v),
                  itemBuilder: (context, pageIndex) {
                    final start = pageIndex * pageSize;
                    final end = (start + pageSize).clamp(0, itemCount);
                    final pageItemCount = end - start;

                    if (landscape && isTablet) {
                      // 태블릿 가로: 4열 2행 그리드 (8장)
                      // 내부 LayoutBuilder로 실제 높이(PageDots 제외) 사용
                      return LayoutBuilder(
                        builder: (context, innerConstraints) {
                          const hPad = 16.0;
                          const vPad = 14.0;
                          const spacing = 12.0;
                          final cardW = (innerConstraints.maxWidth -
                                  hPad * 2 -
                                  spacing * 3) /
                              4;
                          final cardH = (innerConstraints.maxHeight -
                                  vPad -
                                  8.0 -
                                  spacing) /
                              2;
                          return GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            padding:
                                const EdgeInsets.fromLTRB(hPad, vPad, hPad, 8),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              crossAxisSpacing: spacing,
                              mainAxisSpacing: spacing,
                              childAspectRatio:
                                  (cardW / cardH).clamp(0.5, 2.0),
                            ),
                            itemCount: pageItemCount,
                            itemBuilder: (context, index) =>
                                cardFor(start + index),
                          );
                        },
                      );
                    }

                    if (landscape) {
                      // 폰 가로: 4개를 한 줄 Row로 — 전체 높이 채움
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (int i = 0; i < 4; i++) ...[
                              if (i > 0) const SizedBox(width: 12),
                              Expanded(
                                child: (start + i) < itemCount
                                    ? cardFor(start + i)
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        ),
                      );
                    }

                    // 세로: 2×3 그리드
                    // 태블릿: 동적 비율로 6장이 화면에 딱 맞게
                    // 폰: 원래 고정 비율 유지
                    if (isTablet) {
                      // 내부 LayoutBuilder로 PageView 아이템의 실제 높이를 직접 받음
                      // → _PageDots 높이 추정 불필요
                      return LayoutBuilder(
                        builder: (context, innerConstraints) {
                          const hPad = 13.0;
                          const vPad = 17.0;
                          const spacing = 11.0;
                          final cardW = (innerConstraints.maxWidth -
                                  hPad * 2 -
                                  spacing) /
                              2;
                          final cardH = (innerConstraints.maxHeight -
                                  vPad -
                                  8.0 -
                                  spacing * 2) /
                              3;
                          return GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            padding:
                                const EdgeInsets.fromLTRB(hPad, vPad, hPad, 8),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: spacing,
                              mainAxisSpacing: spacing,
                              childAspectRatio:
                                  (cardW / cardH).clamp(0.5, 1.5),
                            ),
                            itemCount: pageItemCount,
                            itemBuilder: (context, index) =>
                                cardFor(start + index),
                          );
                        },
                      );
                    }
                    // 폰 세로: 원래 고정 비율
                    return GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(13, 17, 13, 8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 11,
                        mainAxisSpacing: 11,
                        childAspectRatio: 177.73 / 196.79,
                      ),
                      itemCount: pageItemCount,
                      itemBuilder: (context, index) => cardFor(start + index),
                    );
                  },
                ),
              ),
              if (pageCount > 1)
                _PageDots(
                  page: page,
                  pageCount: pageCount,
                  onChanged: _animateStickerBookPage,
                ),
            ],
          ),
        );
      },
    );
  }

  void _animateStickerBookPage(int page) {
    setState(() => _stickerBookPage = page);
    if (!_stickerBookPageController.hasClients) return;
    _stickerBookPageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildDrawer() {
    final query = _packQuery.trim().toLowerCase();
    final packs = _controller.packs
        .where((pack) => pack.name.toLowerCase().contains(query))
        .toList();
    _sortDrawerPacks(packs);
    final hiddenCount = _hiddenPackIds.length;
    final compact = MediaQuery.sizeOf(context).height < 760;
    final landscape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    final storeButton = SizedBox(
      width: double.infinity,
      height: landscape ? 86 : (compact ? 92 : 118),
      child: FilledButton.tonalIcon(
        onPressed: () {
          StickerlySfx.play(StickerlyAssets.soundPage);
          Navigator.of(context)
              .push(
                MaterialPageRoute<AccountProfile>(
                  builder: (_) => _StoreScreen(
                    account: widget.account,
                    catalog: _controller.catalog,
                    onAccountRefresh: widget.onAccountRefresh,
                    onCatalogRefresh: () => _controller.refreshCatalog(),
                  ),
                ),
              )
              .then((account) {
                if (account != null) widget.onAccountRefresh();
              });
        },
        icon: Icon(
          Icons.storefront_rounded,
          size: landscape ? 26 : (compact ? 28 : 34),
        ),
        label: const Text('스토어'),
        style: FilledButton.styleFrom(
          foregroundColor: StickerlyColors.ink,
          backgroundColor: Colors.white,
          side: const BorderSide(color: StickerlyColors.line, width: 2),
          padding: EdgeInsets.symmetric(
            vertical: landscape ? 18 : (compact ? 22 : 34),
          ),
          textStyle: TextStyle(
            fontSize: landscape ? 20 : (compact ? 21 : 24),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
    final searchField = TextField(
      onChanged: (value) => setState(() {
        _packQuery = value;
        _drawerPage = 0;
      }),
      decoration: InputDecoration(
        hintText: '팩 이름 검색',
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(
          vertical: landscape ? 7 : (compact ? 8 : 12),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: StickerlyColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: StickerlyColors.line, width: 1.5),
        ),
      ),
    );
    final sortButtons = SegmentedButton<_StoreSort>(
      segments: const [
        ButtonSegment(value: _StoreSort.latest, label: Text('최신순')),
        ButtonSegment(value: _StoreSort.price, label: Text('가격순')),
        ButtonSegment(value: _StoreSort.name, label: Text('이름순')),
      ],
      selected: {_drawerSort},
      onSelectionChanged: (value) => setState(() {
        _drawerSort = value.first;
        _drawerPage = 0;
      }),
    );
    final hiddenNotice = AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: hiddenCount == 0
          ? const SizedBox(height: 4)
          : Padding(
              key: ValueKey(hiddenCount),
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$hiddenCount개 숨김',
                style: const TextStyle(
                  color: Color(0xFF8B8194),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
    if (landscape) {
      return LayoutBuilder(
        builder: (context, lc) {
          final isTablet = MediaQuery.sizeOf(context).shortestSide > 600;

          // ── 공통 좌측 패널 빌더 ────────────────────────────────────────
          Widget buildLeft(double width, {bool expanded = false}) => SizedBox(
                width: width,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 44,
                        child: Row(
                          children: [
                            Expanded(
                              child: _DrawerSearchField(
                                iconSize: expanded ? 26 : 21,
                                onChanged: (value) => setState(() {
                                  _packQuery = value;
                                  _drawerPage = 0;
                                }),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 82,
                              height: 44,
                              child: _DrawerSortButton(
                                sort: _drawerSort,
                                onChanged: (value) => setState(() {
                                  _drawerSort = value;
                                  _drawerPage = 0;
                                }),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (expanded)
                        Expanded(child: _DrawerStoreButton(onTap: _openStore))
                      else ...[
                        SizedBox(
                          height: 105,
                          child: _DrawerStoreButton(onTap: _openStore),
                        ),
                      ],
                    ],
                  ),
                ),
              );

          // ── 태블릿 가로: 3×3 페이지 슬라이드 ─────────────────────────
          if (isTablet) {
            final leftWidth = (lc.maxWidth * 0.38).clamp(280.0, 420.0);
            return CustomPaint(
              painter: const _HomeDotPainter(),
              child: Row(
                children: [
                  buildLeft(leftWidth, expanded: true),
                  Container(
                    width: 2,
                    margin: const EdgeInsets.fromLTRB(0, 16, 26, 18),
                    color: const Color(0xFFE8DDD4),
                  ),
                  Expanded(
                    child: packs.isEmpty
                        ? const Center(child: Text('찾는 팩이 없어요'))
                        : _buildDrawerPackPages(
                            packs,
                            overridePageSize: 9,
                            overrideCrossAxisCount: 3,
                          ),
                  ),
                ],
              ),
            );
          }

          // ── 폰 가로: 기존 레이아웃 ────────────────────────────────────
          return CustomPaint(
            painter: const _HomeDotPainter(),
            child: Row(
              children: [
                buildLeft(315),
                Container(
                  width: 2,
                  margin: const EdgeInsets.fromLTRB(0, 16, 26, 18),
                  color: const Color(0xFFE8DDD4),
                ),
                Expanded(
                  child: packs.isEmpty
                      ? const Center(child: Text('찾는 팩이 없어요'))
                      : _buildDrawerPackPages(packs),
                ),
              ],
            ),
          );
        },
      );
    }
    if (landscape) {
      return Row(
        children: [
          SizedBox(
            width: 270,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  storeButton,
                  const SizedBox(height: 8),
                  searchField,
                  const SizedBox(height: 8),
                  sortButtons,
                  hiddenNotice,
                ],
              ),
            ),
          ),
          Expanded(
            child: packs.isEmpty
                ? const Center(child: Text('찾는 팩이 없어요'))
                : _buildDrawerPackPages(packs),
          ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = constraints.maxWidth / 390;
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: const _HomeDotPainter()),
            ),
            Positioned(
              left: 9 * scale,
              top: 11 * scale,
              width: 373 * scale,
              height: 145 * scale,
              child: _DrawerStoreButton(onTap: _openStore),
            ),
            Positioned(
              left: 9 * scale,
              top: 167 * scale,
              width: 277 * scale,
              height: 44 * scale,
              child: _DrawerSearchField(
                iconSize: 42,
                onChanged: (value) => setState(() {
                  _packQuery = value;
                  _drawerPage = 0;
                }),
              ),
            ),
            Positioned(
              left: 294 * scale,
              top: 167 * scale,
              width: 82 * scale,
              height: 44 * scale,
              child: _DrawerSortButton(
                sort: _drawerSort,
                onChanged: (value) => setState(() {
                  _drawerSort = value;
                  _drawerPage = 0;
                }),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 222 * scale,
              bottom: 0,
              child: packs.isEmpty
                  ? const Center(child: Text('찾는 팩이 없어요'))
                  : _buildDrawerPackPages(packs),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDrawerPackPages(
    List<StickerPack> packs, {
    int? overridePageSize,
    int? overrideCrossAxisCount,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        const spacing = 10.0;
        final pageSize = overridePageSize ?? (landscape ? 8 : 6);
        final crossAxisCount = overrideCrossAxisCount ?? (landscape ? 4 : 3);
        const horizontalPadding = 14.0;
        const verticalPadding = 7.0;
        final cardWidth =
            ((constraints.maxWidth -
                        horizontalPadding * 2 -
                        spacing * (crossAxisCount - 1)) /
                    crossAxisCount)
                .clamp(1.0, double.infinity);
        final cardHeight = cardWidth * 120 / 114;
        final pageCount = (packs.length / pageSize).ceil();
        final page = _drawerPage.clamp(0, pageCount - 1);
        if (page != _drawerPage) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _drawerPage = page);
          });
        }
        final pagePacks = packs
            .skip(page * pageSize)
            .take(pageSize)
            .toList(growable: false);
        return Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  horizontalPadding,
                  verticalPadding,
                  horizontalPadding,
                  4,
                ),
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: pagePacks.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                    childAspectRatio: cardWidth / cardHeight,
                  ),
                  itemBuilder: (context, index) {
                    final pack = pagePacks[index];
                    return _DrawerPackCard(
                      pack: pack,
                      catalog: _controller.catalog,
                      enabled: !_hiddenPackIds.contains(pack.id),
                      downloading: pack.stickers.any(
                        (item) =>
                            _controller.downloadingAssetIds.contains(item.id),
                      ),
                      onChanged: (value) =>
                          unawaited(_setPackEnabled(pack.id, value)),
                      onDownload: () =>
                          unawaited(_controller.downloadPack(pack)),
                      onOpen: () => _openPackDetails(pack),
                    );
                  },
                ),
              ),
            ),
            if (pageCount > 1)
              _PageDots(
                page: page,
                pageCount: pageCount,
                onChanged: (value) => setState(() => _drawerPage = value),
              ),
          ],
        );
      },
    );
  }

  void _sortDrawerPacks(List<StickerPack> packs) {
    switch (_drawerSort) {
      case _StoreSort.latest:
        return;
      case _StoreSort.price:
        packs.sort((a, b) {
          final priceCompare = _packPriceWeight(
            a,
          ).compareTo(_packPriceWeight(b));
          if (priceCompare != 0) return priceCompare;
          return a.name.compareTo(b.name);
        });
      case _StoreSort.name:
        packs.sort((a, b) => a.name.compareTo(b.name));
    }
  }

  int _packPriceWeight(StickerPack pack) {
    final packBackgrounds = _controller.catalog.backgrounds.where(
      (background) => pack.backgroundIds.contains(background.id),
    );
    final usableStates = [
      ...pack.stickers.map((asset) => asset.isUsable),
      ...packBackgrounds.map((asset) => asset.isUsable),
    ];
    return usableStates.contains(false) ? 1 : 0;
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
    setState(() => _projectOpening = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      await _controller.refreshCatalog();
      if (!mounted) return;
      final updated = await Navigator.of(context).push<StickerProject>(
        MaterialPageRoute<StickerProject>(
          builder: (context) => EditorScreen(
            project: project,
            repository: widget.repository,
            catalog: _controller.catalog,
            hiddenPackIds: _hiddenPackIds,
            onDownloadPack: _controller.downloadPack,
          ),
        ),
      );
      if (updated != null) _controller.upsertProject(updated);
    } finally {
      if (mounted) setState(() => _projectOpening = false);
    }
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
          icon: const BackChevronGraphic(width: 24, height: 24),
        ),
        title: Text(widget.title, style: const TextStyle(fontSize: 20)),
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

// BackChevronGraphic is imported from lib/app/widgets/back_chevron.dart

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
    final topPad = MediaQuery.of(context).padding.top;
    if (landscape) {
      return SizedBox(
        height: 60 + topPad,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFFFFDAAE), Color(0xFFFFB5A6), Color(0xFFDEC0FF)],
            ),
            boxShadow: [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.09),
                blurRadius: 13,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              SizedBox(height: topPad),
              Expanded(
                child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              InkWell(
                onTap: showBack ? onBack : null,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: StickerlyWordmark(scale: 0.6),
                ),
              ),
              if (showBack)
                InkWell(
                  onTap: onBack,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BackChevronGraphic(width: 20, height: 20),
                        const SizedBox(width: 3),
                        Text(
                          message,
                          style: const TextStyle(
                            fontFamily: 'MemomentKkukkukk',
                            fontSize: 18,
                            fontWeight: FontWeight.normal,
                            letterSpacing: -0.72,
                            color: Color(0xFF2A2828),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (showWelcome)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(44),
                        boxShadow: const [
                          BoxShadow(
                            color: Color.fromRGBO(0, 0, 0, 0.25),
                            blurRadius: 3.4,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(44),
                        child: _SlotMachineWelcomeText(message: message),
                      ),
                    ),
                  ),
                )
              else
                const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _HomeProfileButton(
                  avatarUrl: avatarUrl,
                  onSelected: onProfileAction,
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
    if (showWelcome && !landscape) {
      return Column(
        children: [
          SizedBox(
            height: 60 + topPad,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFFFC2A7),
                    Color(0xFFF5B4C8),
                    Color(0xFFD9B5FF),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 10.7,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 12,
                    top: topPad,
                    bottom: 0,
                    child: Center(child: StickerlyWordmark(scale: 0.78)),
                  ),
                  Positioned(
                    right: 8,
                    top: topPad + 7,
                    child: _HomeProfileButton(
                      avatarUrl: avatarUrl,
                      onSelected: onProfileAction,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 9),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Container(
              width: double.infinity,
              height: 49,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(44),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 3.4,
                    spreadRadius: -1,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(44),
                child: _SlotMachineWelcomeText(message: message),
              ),
            ),
          ),
        ],
      );
    }
    if (showBack && !landscape) {
      return SizedBox(
        height: 60 + topPad,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFC2A7), Color(0xFFF5B4C8), Color(0xFFD9B5FF)],
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10.7,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 12,
                top: topPad,
                bottom: 0,
                child: Center(
                  child: InkWell(
                    onTap: onBack,
                    child: const StickerlyWordmark(scale: 0.78),
                  ),
                ),
              ),
              Positioned(
                left: 124,
                top: topPad,
                bottom: 0,
                child: InkWell(
                  onTap: onBack,
                  child: Row(
                    children: [
                      const BackChevronGraphic(width: 19, height: 19),
                      const SizedBox(width: 5),
                      Text(
                        message,
                        style: const TextStyle(
                          color: Color(0xFF2A2828),
                          fontSize: 20,
                          fontWeight: FontWeight.normal,
                          letterSpacing: -0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: topPad + 7,
                child: _HomeProfileButton(
                  avatarUrl: avatarUrl,
                  onSelected: onProfileAction,
                ),
              ),
            ],
          ),
        ),
      );
    }
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
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 10.7,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              landscape ? 6 : 12,
              topPad + (landscape ? 2.4 : (mobile ? 9 : 16)),
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
                          BackChevronGraphic(
                            width: landscape ? 18 : 30,
                            height: landscape ? 18 : 30,
                          ),
                          Text(
                            message,
                            style: const TextStyle(
                              color: StickerlyColors.inkSoft,
                              fontSize: 20,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (landscape && showWelcome) ...[
                  const Spacer(),
                  Container(
                    width: 373,
                    height: 49,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: _SlotMachineWelcomeText(message: message),
                    ),
                  ),
                  const Spacer(),
                ] else if (!mobile) ...[
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
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Container(
                width: double.infinity,
                height: 43,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF008CFF), width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: _SlotMachineWelcomeText(message: message),
                ),
              ),
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
    required this.onAccountRefresh,
  });

  final AccountProfile account;
  final Future<AccountProfile> Function(String displayName) onAccountUpdated;
  final Future<AccountProfile> Function(String imagePath) onAvatarUpdated;
  final Future<AccountProfile> Function() onAccountRefresh;

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

  Future<void> _showPointPlaceholder() async {
    StickerlySfx.play(StickerlyAssets.soundPage);
    final account = await Navigator.of(context).push<AccountProfile>(
      MaterialPageRoute<AccountProfile>(
        builder: (_) =>
            _PointStoreScreen(onAccountRefresh: widget.onAccountRefresh),
      ),
    );
    if (account != null && mounted) setState(() => _account = account);
  }

  @override
  Widget build(BuildContext context) {
    final profile = _MyPageProfileBlock(
      account: _account,
      savingName: _savingName,
      savingAvatar: _savingAvatar,
      onEditName: _editName,
      onEditAvatar: _editAvatar,
    );
    final info = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
    );
    return Scaffold(
      backgroundColor: StickerlyColors.paper,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const BackChevronGraphic(width: 24, height: 24),
        ),
        title: const Text('마이페이지', style: TextStyle(fontSize: 20)),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape = constraints.maxWidth > constraints.maxHeight;
            if (isLandscape) {
              return Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Expanded(child: Center(child: profile)),
                    const SizedBox(width: 18),
                    Expanded(child: Center(child: info)),
                  ],
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [profile, const SizedBox(height: 28), info],
            );
          },
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

class _MyPageProfileBlock extends StatelessWidget {
  const _MyPageProfileBlock({
    required this.account,
    required this.savingName,
    required this.savingAvatar,
    required this.onEditName,
    required this.onEditAvatar,
  });

  final AccountProfile account;
  final bool savingName;
  final bool savingAvatar;
  final VoidCallback onEditName;
  final VoidCallback onEditAvatar;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: Colors.white,
                backgroundImage: account.avatarUrl == null
                    ? null
                    : NetworkImage(account.avatarUrl!),
                child: account.avatarUrl == null
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
                    onTap: savingAvatar ? null : onEditAvatar,
                    child: SizedBox.square(
                      dimension: 42,
                      child: Center(
                        child: savingAvatar
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
            onTap: savingName ? null : onEditName,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      account.displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  savingName
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
          account.email,
          textAlign: TextAlign.center,
          style: const TextStyle(color: StickerlyColors.inkSoft),
        ),
      ],
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
  const _StoreScreen({
    required this.account,
    required this.catalog,
    required this.onAccountRefresh,
    required this.onCatalogRefresh,
  });

  final AccountProfile? account;
  final AssetCatalog catalog;
  final Future<AccountProfile> Function() onAccountRefresh;
  final Future<void> Function() onCatalogRefresh;

  @override
  State<_StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<_StoreScreen> {
  final _searchController = TextEditingController();
  var _sort = _StoreSort.latest;
  var _loading = true;
  var _buyingProductId = '';
  String? _error;
  String? _storeBannerUrl;
  var _products = <_StoreProduct>[];
  late int _points = widget.account?.points ?? 0;
  late Set<String> _ownedPackIds = {...?widget.account?.packIds};
  var _storeLandscapePage = 0;
  late final _storeLandscapePageController = PageController();
  var _storePortraitPage = 0;
  late final _storePortraitPageController = PageController();

  @override
  void initState() {
    super.initState();
    unawaited(_loadProducts());
    _searchController.addListener(() {
      setState(() {
        _storeLandscapePage = 0;
        _storePortraitPage = 0;
      });
      if (_storeLandscapePageController.hasClients) {
        _storeLandscapePageController.jumpToPage(0);
      }
      if (_storePortraitPageController.hasClients) {
        _storePortraitPageController.jumpToPage(0);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _storeLandscapePageController.dispose();
    _storePortraitPageController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      String? storeBannerUrl;
      try {
        final setting = await client
            .from('app_settings')
            .select('value')
            .eq('key', 'store_banner_storage_path')
            .maybeSingle();
        final bannerPath = setting?['value']?.toString();
        if (bannerPath != null && bannerPath.isNotEmpty) {
          storeBannerUrl = await client.storage
              .from('assets')
              .createSignedUrl(bannerPath, 3600);
        }
      } catch (_) {}
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
      setState(() {
        _products = products;
        _storeBannerUrl = storeBannerUrl;
      });
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
    final account = await Navigator.of(context).push<AccountProfile>(
      MaterialPageRoute<AccountProfile>(
        builder: (_) =>
            _PointStoreScreen(onAccountRefresh: widget.onAccountRefresh),
      ),
    );
    if (account != null && mounted) {
      setState(() {
        _points = account.points;
        _ownedPackIds = {...account.packIds};
      });
    }
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
    if (_ownsProduct(product)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이미 보유한 상품이에요.')));
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
      final account = await widget.onAccountRefresh();
      if (!mounted) return;
      setState(() {
        _points = account.points;
        _ownedPackIds = {...account.packIds};
      });
      await widget.onCatalogRefresh();
      if (!mounted) return;
      _showPurchaseCompletePop(product);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      if (error.message.contains('INSUFFICIENT_POINTS')) {
        if (await _confirmCharge() && mounted) await _goToPointStore();
      } else if (error.message.contains('ALREADY_OWNED')) {
        final account = await widget.onAccountRefresh();
        if (!mounted) return;
        setState(() {
          _points = account.points;
          _ownedPackIds = {...account.packIds};
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('이미 보유한 상품이에요.')));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('구매에 실패했어요.')));
      }
    } finally {
      if (mounted) setState(() => _buyingProductId = '');
    }
  }

  bool _ownsProduct(_StoreProduct product) =>
      product.packIds.isNotEmpty &&
      product.packIds.every(_ownedPackIds.contains);

  void _showPurchaseCompletePop(_StoreProduct product) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) =>
          _PurchaseCompletePop(product: product, onDone: () => entry.remove()),
    );
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    final products = _visibleProducts;
    final landscape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    return Scaffold(
      backgroundColor: StickerlyColors.paper,
      body: SafeArea(
        top: false,
        bottom: false,
        child: CustomPaint(
          painter: const _HomeDotPainter(),
          child: Column(
            children: [
              _StoreHeader(
                points: _points,
                onBack: () => Navigator.pop(context),
                onPointsTap: _goToPointStore,
              ),
              if (landscape)
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isTablet =
                          MediaQuery.sizeOf(context).shortestSide > 600;

                      // ── 좌측 패널 공통 빌더 ──────────────────────────────
                      Widget buildLeft(double width, {bool tall = false}) =>
                          SizedBox(
                            width: width,
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(10, 10, 10, 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: DecoratedBox(
                                          decoration: const BoxDecoration(
                                            boxShadow: [
                                              BoxShadow(
                                                color: Color.fromRGBO(
                                                    0, 0, 0, 0.06),
                                                blurRadius: 6,
                                                offset: Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: SizedBox(
                                            height: tall ? 44 : 39,
                                            child: TextField(
                                              controller: _searchController,
                                              decoration: InputDecoration(
                                                hintText: '상품 검색',
                                                prefixIcon: Icon(
                                                  Icons.search_rounded,
                                                  color:
                                                      const Color(0xFF2A2828),
                                                  size: tall ? 26 : null,
                                                ),
                                                prefixIconConstraints: tall
                                                    ? const BoxConstraints(
                                                        minWidth: 44,
                                                        minHeight: 44)
                                                    : null,
                                                filled: true,
                                                fillColor: Colors.white,
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(9),
                                                  borderSide: const BorderSide(
                                                    color: Color(0xFFE8DDD4),
                                                    width: 2,
                                                  ),
                                                ),
                                                enabledBorder:
                                                    OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(9),
                                                  borderSide: const BorderSide(
                                                    color: Color(0xFFE8DDD4),
                                                    width: 2,
                                                  ),
                                                ),
                                                contentPadding: tall
                                                    ? EdgeInsets.zero
                                                    : const EdgeInsets
                                                        .symmetric(
                                                        vertical: 8),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 7),
                                      SizedBox(
                                        width: 79,
                                        height: tall ? 44 : 39,
                                        child: _DrawerSortButton(
                                          sort: _sort,
                                          onChanged: (value) {
                                            StickerlySfx.play(
                                                StickerlyAssets.soundFlip);
                                            setState(() {
                                              _sort = value;
                                              _storeLandscapePage = 0;
                                            });
                                            if (_storeLandscapePageController
                                                .hasClients) {
                                              _storeLandscapePageController
                                                  .jumpToPage(0);
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: _StoreHeroBanner(
                                          imageUrl: _storeBannerUrl,
                                          fit: BoxFit.fitWidth),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );

                      // ── 태블릿 가로: 3×3 페이지 슬라이드 ─────────────────
                      if (isTablet) {
                        final leftWidth = (constraints.maxWidth * 0.38)
                            .clamp(280.0, 420.0);
                        const hPad = 12.0;
                        const vPad = 10.0;
                        const spacing = 10.0;
                        final rightWidth =
                            constraints.maxWidth - leftWidth - 2;
                        final cardW =
                            (rightWidth - hPad * 2 - spacing * 2) / 3;
                        final cardH =
                            (constraints.maxHeight - vPad * 2 - spacing * 2 -
                                28) /
                            3;
                        final pageCount =
                            products.isEmpty ? 1 : (products.length + 8) ~/ 9;

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            buildLeft(leftWidth, tall: true),
                            Container(
                              width: 2,
                              margin:
                                  const EdgeInsets.fromLTRB(0, 14, 0, 14),
                              color: const Color(0xFFE8DDD4),
                            ),
                            SizedBox(
                              width: rightWidth,
                              child: Column(
                                children: [
                                  Expanded(
                                    child: _loading
                                        ? const Center(
                                            child:
                                                CircularProgressIndicator())
                                        : _error != null
                                            ? _ErrorState(
                                                onRetry: _loadProducts)
                                            : products.isEmpty
                                                ? const Center(
                                                    child:
                                                        Text('상품이 없어요.'))
                                                : PageView.builder(
                                                    controller:
                                                        _storeLandscapePageController,
                                                    onPageChanged: (p) =>
                                                        setState(() =>
                                                            _storeLandscapePage =
                                                                p),
                                                    itemCount: pageCount,
                                                    itemBuilder:
                                                        (context, pageIdx) {
                                                      final start =
                                                          pageIdx * 9;
                                                      final end = (start + 9)
                                                          .clamp(0,
                                                              products.length);
                                                      return GridView.builder(
                                                        physics:
                                                            const NeverScrollableScrollPhysics(),
                                                        padding: const EdgeInsets
                                                            .fromLTRB(hPad,
                                                            vPad, hPad, vPad),
                                                        gridDelegate:
                                                            SliverGridDelegateWithFixedCrossAxisCount(
                                                          crossAxisCount: 3,
                                                          crossAxisSpacing:
                                                              spacing,
                                                          mainAxisSpacing:
                                                              spacing,
                                                          childAspectRatio:
                                                              (cardW / cardH)
                                                                  .clamp(
                                                                      0.4,
                                                                      2.5),
                                                        ),
                                                        itemCount: end - start,
                                                        itemBuilder: (context,
                                                            index) {
                                                          final i =
                                                              start + index;
                                                          return _StoreProductCard(
                                                            product:
                                                                products[i],
                                                            buying: _buyingProductId ==
                                                                products[i].id,
                                                            owned: _ownsProduct(
                                                                products[i]),
                                                            onOpen: () {
                                                              Navigator.of(
                                                                      context)
                                                                  .push(
                                                                MaterialPageRoute<
                                                                    void>(
                                                                  builder: (_) =>
                                                                      _ProductDetailsScreen(
                                                                    product:
                                                                        products[i],
                                                                    catalog: widget
                                                                        .catalog,
                                                                    owned: _ownsProduct(
                                                                        products[
                                                                            i]),
                                                                    buying: _buyingProductId ==
                                                                        products[i]
                                                                            .id,
                                                                    onBuy: () =>
                                                                        _buyProduct(
                                                                            products[i]),
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                            onOwnedNotice: () {
                                                              ScaffoldMessenger
                                                                      .of(context)
                                                                  .showSnackBar(
                                                                const SnackBar(
                                                                    content: Text(
                                                                        '이미 보유중입니다.')),
                                                              );
                                                            },
                                                            onBuy: () =>
                                                                _buyProduct(
                                                                    products[
                                                                        i]),
                                                          );
                                                        },
                                                      );
                                                    },
                                                  ),
                                  ),
                                  if (!_loading &&
                                      _error == null &&
                                      products.isNotEmpty &&
                                      pageCount > 1)
                                    _PageDots(
                                      page: _storeLandscapePage,
                                      pageCount: pageCount,
                                      onChanged: (i) =>
                                          _storeLandscapePageController
                                              .animateToPage(
                                        i,
                                        duration:
                                            const Duration(milliseconds: 300),
                                        curve: Curves.easeInOut,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }

                      // ── 폰 가로: 기존 레이아웃 ────────────────────────────
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          buildLeft(290),
                          Container(
                            width: 2,
                            margin:
                                const EdgeInsets.fromLTRB(0, 14, 0, 14),
                            color: const Color(0xFFE8DDD4),
                          ),
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                if (_loading) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }
                                if (_error != null) {
                                  return _ErrorState(onRetry: _loadProducts);
                                }
                                if (products.isEmpty) {
                                  return const Center(
                                      child: Text('상품이 없어요.'));
                                }
                                return GridView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      10, 10, 10, 20),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                    childAspectRatio: 1.2,
                                  ),
                                  itemCount: products.length,
                                  itemBuilder: (context, index) =>
                                      _StoreProductCard(
                                    product: products[index],
                                    buying: _buyingProductId ==
                                        products[index].id,
                                    owned: _ownsProduct(products[index]),
                                    onOpen: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              _ProductDetailsScreen(
                                            product: products[index],
                                            catalog: widget.catalog,
                                            owned:
                                                _ownsProduct(products[index]),
                                            buying: _buyingProductId ==
                                                products[index].id,
                                            onBuy: () =>
                                                _buyProduct(products[index]),
                                          ),
                                        ),
                                      );
                                    },
                                    onOwnedNotice: () {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('이미 보유중입니다.')),
                                      );
                                    },
                                    onBuy: () => _buyProduct(products[index]),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: AspectRatio(
                    aspectRatio: 390 / 156,
                    child: _StoreHeroBanner(imageUrl: _storeBannerUrl),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(7, 6, 7, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Color.fromRGBO(0, 0, 0, 0.06),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: SizedBox(
                            height: 44,
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: '상품 검색',
                                prefixIcon: const Icon(
                                  Icons.search_rounded,
                                  color: Color(0xFF2A2828),
                                  size: 26,
                                ),
                                prefixIconConstraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(9),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFE8DDD4),
                                    width: 2,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(9),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFE8DDD4),
                                    width: 2,
                                  ),
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      SizedBox(
                        width: 79,
                        height: 44,
                        child: _DrawerSortButton(
                          sort: _sort,
                          onChanged: (value) {
                            StickerlySfx.play(StickerlyAssets.soundFlip);
                            setState(() {
                              _sort = value;
                              _storePortraitPage = 0;
                            });
                            if (_storePortraitPageController.hasClients) {
                              _storePortraitPageController.jumpToPage(0);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (_loading) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (_error != null) {
                        return _ErrorState(onRetry: _loadProducts);
                      }
                      if (products.isEmpty) {
                        return const Center(child: Text('상품이 없어요.'));
                      }
                      final isTablet =
                          MediaQuery.sizeOf(context).shortestSide > 600;
                      // 태블릿: 2열2행(4개/페이지), 모바일: 1열2행(2개/페이지)
                      final cols = isTablet ? 2 : 1;
                      const rows = 2;
                      const hPad = 10.0;
                      const vPad = 6.0;
                      const spacing = 8.0;
                      final cardW = cols == 1
                          ? constraints.maxWidth - hPad * 2
                          : (constraints.maxWidth - hPad * 2 - spacing) / 2;
                      final cardH =
                          (constraints.maxHeight - vPad - spacing - 28) /
                              rows;
                      final perPage = cols * rows;
                      final pageCount = products.isEmpty
                          ? 1
                          : (products.length + perPage - 1) ~/ perPage;

                      return Column(
                        children: [
                          Expanded(
                            child: PageView.builder(
                              controller: _storePortraitPageController,
                              onPageChanged: (p) =>
                                  setState(() => _storePortraitPage = p),
                              itemCount: pageCount,
                              itemBuilder: (context, pageIdx) {
                                final start = pageIdx * perPage;
                                final end = (start + perPage)
                                    .clamp(0, products.length);
                                return GridView.builder(
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(
                                      hPad, vPad, hPad, vPad),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: cols,
                                    crossAxisSpacing: spacing,
                                    mainAxisSpacing: spacing,
                                    childAspectRatio:
                                        (cardW / cardH).clamp(0.3, 3.0),
                                  ),
                                  itemCount: end - start,
                                  itemBuilder: (context, index) {
                                    final i = start + index;
                                    return _StoreProductCard(
                                      product: products[i],
                                      buying:
                                          _buyingProductId == products[i].id,
                                      owned: _ownsProduct(products[i]),
                                      onOpen: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                _ProductDetailsScreen(
                                              product: products[i],
                                              catalog: widget.catalog,
                                              owned:
                                                  _ownsProduct(products[i]),
                                              buying: _buyingProductId ==
                                                  products[i].id,
                                              onBuy: () =>
                                                  _buyProduct(products[i]),
                                            ),
                                          ),
                                        );
                                      },
                                      onOwnedNotice: () {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content:
                                                  Text('이미 보유중입니다.')),
                                        );
                                      },
                                      onBuy: () => _buyProduct(products[i]),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          if (pageCount > 1)
                            _PageDots(
                              page: _storePortraitPage,
                              pageCount: pageCount,
                              onChanged: (i) =>
                                  _storePortraitPageController.animateToPage(
                                i,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StoreHeader extends StatelessWidget {
  const _StoreHeader({required this.points, required this.onBack, required this.onPointsTap, super.key});

  final int points;
  final VoidCallback onBack;
  final VoidCallback onPointsTap;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final pointsText = points.toString().replaceAllMapped(
      RegExp(r'(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFFFDAAE), Color(0xFFFFB5A6), Color(0xFFDEC0FF)],
        ),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.09),
            blurRadius: 13,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SizedBox(
        height: 60 + topPad,
        child: Stack(
          children: [
            Positioned(
              left: 12,
              top: topPad,
              bottom: 0,
              child: InkWell(
                onTap: onBack,
                child: const Center(child: StickerlyWordmark(scale: 0.78)),
              ),
            ),
            Positioned(
              left: 124,
              top: topPad,
              bottom: 0,
              child: InkWell(
                onTap: onBack,
                child: Row(
                  children: [
                    const BackChevronGraphic(width: 19, height: 19),
                    const SizedBox(width: 5),
                    const Text(
                      '상점',
                      style: TextStyle(
                        color: Color(0xFF2A2828),
                        fontSize: 20,
                        fontWeight: FontWeight.normal,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: topPad + 15,
              child: InkWell(
                onTap: onPointsTap,
                borderRadius: BorderRadius.circular(18),
                child: IntrinsicWidth(
                  child: Container(
                    height: 29,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F0F0),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: const Color(0xFFE8DDD4)),
                    ),
                    child: Text(
                      '$pointsText P',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'MemomentKkukkukk',
                        color: Color(0xFF000000),
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                      ),
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
}

class _StoreHeroBanner extends StatelessWidget {
  const _StoreHeroBanner({this.imageUrl, this.fit = BoxFit.cover});

  final String? imageUrl;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final image = imageUrl == null
        ? Image.asset(
            StickerlyAssets.storeBanner,
            fit: fit,
            width: double.infinity,
            alignment: Alignment.topCenter,
          )
        : Image.network(
            imageUrl!,
            fit: fit,
            width: double.infinity,
            alignment: Alignment.topCenter,
            errorBuilder: (_, _, _) => Image.asset(
              StickerlyAssets.storeBanner,
              fit: fit,
              width: double.infinity,
              alignment: Alignment.topCenter,
            ),
          );

    return ClipRect(child: image);
  }
}

class _PurchaseCompletePop extends StatefulWidget {
  const _PurchaseCompletePop({required this.product, required this.onDone});

  final _StoreProduct product;
  final VoidCallback onDone;

  @override
  State<_PurchaseCompletePop> createState() => _PurchaseCompletePopState();
}

class _PurchaseCompletePopState extends State<_PurchaseCompletePop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.72, end: 1.12), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0), weight: 45),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
    Future<void>.delayed(const Duration(milliseconds: 1850), () async {
      if (!mounted) return;
      await _controller.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 26;
    return Positioned(
      top: top,
      left: 18,
      right: 18,
      child: IgnorePointer(
        child: SlideTransition(
          position: _slide,
          child: ScaleTransition(
            scale: _scale,
            child: Material(
              color: Colors.transparent,
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8ED),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: StickerlyColors.pink.withValues(alpha: 0.65),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: StickerlyColors.ink.withValues(alpha: 0.22),
                        blurRadius: 26,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PurchasePopThumbnail(path: widget.product.thumbnailUrl),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '구매 완료!',
                              style: TextStyle(
                                color: StickerlyColors.pink,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              '${widget.product.name} 구매 완료!',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: StickerlyColors.ink,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                height: 1.08,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text('🎉', style: TextStyle(fontSize: 28)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PurchasePopThumbnail extends StatelessWidget {
  const _PurchasePopThumbnail({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: StickerlyColors.line, width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox.square(
          dimension: 70,
          child: path == null || path!.isEmpty
              ? const Icon(Icons.card_giftcard_rounded, size: 34)
              : AssetFileImage(path: path!, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _PointChargeCompletePop extends StatefulWidget {
  const _PointChargeCompletePop({required this.points, required this.onDone});

  final int points;
  final VoidCallback onDone;

  @override
  State<_PointChargeCompletePop> createState() =>
      _PointChargeCompletePopState();
}

class _PointChargeCompletePopState extends State<_PointChargeCompletePop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.72, end: 1.12), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0), weight: 45),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
    Future<void>.delayed(const Duration(milliseconds: 1700), () async {
      if (!mounted) return;
      await _controller.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 26;
    final pointsText = widget.points.toString().replaceAllMapped(
      RegExp(r'(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return Positioned(
      top: top,
      left: 18,
      right: 18,
      child: IgnorePointer(
        child: SlideTransition(
          position: _slide,
          child: ScaleTransition(
            scale: _scale,
            child: Material(
              color: Colors.transparent,
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8ED),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: StickerlyColors.purple.withValues(alpha: 0.55),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: StickerlyColors.ink.withValues(alpha: 0.22),
                        blurRadius: 26,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4F9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: StickerlyColors.line,
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.toll_rounded,
                          color: StickerlyColors.purple,
                          size: 36,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          '$pointsText P 충전 완료!',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: StickerlyColors.ink,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            height: 1.08,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('✨', style: TextStyle(fontSize: 28)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StoreProductCard extends StatelessWidget {
  const _StoreProductCard({
    required this.product,
    required this.buying,
    required this.owned,
    required this.onOpen,
    required this.onBuy,
    required this.onOwnedNotice,
  });

  final _StoreProduct product;
  final bool buying;
  final bool owned;
  final VoidCallback onOpen;
  final VoidCallback onBuy;
  final VoidCallback onOwnedNotice;

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    final priceText =
        '${product.priceAmount.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',')} P';
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8FA),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE8DDD4), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.17),
                  blurRadius: 10.7,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: product.thumbnailUrl == null
                ? const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFFEEF5), Color(0xFFEAF6FF)],
                      ),
                    ),
                  )
                : AssetFileImage(
                    path: product.thumbnailUrl!,
                    fit: BoxFit.cover,
                  ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 8,
            right: 12,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onOpen,
                  borderRadius: BorderRadius.circular(999),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width - 48,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(0xFFE8DDD4),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: landscape ? 12 : 14,
                          vertical: landscape ? 5 : 6,
                        ),
                        child: Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: StickerlyColors.ink,
                            fontSize: landscape ? 20 : 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.8,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onOpen,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                product.description.isEmpty
                                    ? '상품 설명이 없어요.'
                                    : product.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF5B4C71),
                                  fontSize: 15,
                                  fontWeight: FontWeight.normal,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              priceText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: StickerlyColors.purple,
                                fontSize: 23,
                                fontWeight: FontWeight.w700,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 79,
                  height: 40,
                  child: FilledButton(
                    onPressed: buying
                        ? null
                        : owned
                        ? onOwnedNotice
                        : onBuy,
                    style: FilledButton.styleFrom(
                      backgroundColor: owned || buying
                          ? const Color(0xFFE8DDD4)
                          : StickerlyColors.pink,
                      foregroundColor: owned || buying
                          ? StickerlyColors.inkSoft
                          : Colors.white,
                      disabledBackgroundColor: const Color(0xFFE8DDD4),
                      disabledForegroundColor: StickerlyColors.inkSoft,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    child: buying
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(owned ? '보유' : '구매'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductDetailsScreen extends StatefulWidget {
  const _ProductDetailsScreen({
    required this.product,
    required this.catalog,
    required this.owned,
    required this.buying,
    required this.onBuy,
  });

  final _StoreProduct product;
  final AssetCatalog catalog;
  final bool owned;
  final bool buying;
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
                                    '${product.priceAmount.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',')} P',
                                    style: const TextStyle(
                                      color: StickerlyColors.purple,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                FilledButton(
                                  onPressed: widget.owned || widget.buying
                                      ? null
                                      : widget.onBuy,
                                  child: widget.buying
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(widget.owned ? '보유중' : '구매'),
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
  const _PointStoreScreen({required this.onAccountRefresh});

  final Future<AccountProfile> Function() onAccountRefresh;

  @override
  State<_PointStoreScreen> createState() => _PointStoreScreenState();
}

class _PointStoreScreenState extends State<_PointStoreScreen> {
  static const _presets = [
    (price: 1000, base: 1000, bonus: 0),
    (price: 3000, base: 3000, bonus: 0),
    (price: 5000, base: 5000, bonus: 1000),
    (price: 10000, base: 10000, bonus: 2000),
  ];
  var _selected = 1000;

  ({int price, int base, int bonus}) get _selectedPreset =>
      _presets.firstWhere((preset) => preset.price == _selected);

  int get _points => _selectedPreset.base + _selectedPreset.bonus;

  Future<void> _buyPlaceholder() async {
    try {
      await Supabase.instance.client.rpc(
        'test_charge_points',
        params: {'points_to_add': _points},
      );
      final account = await widget.onAccountRefresh();
      if (!mounted) return;
      _showPointChargePop(_points);
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted) Navigator.pop(context, account);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('충전 실패. SQL을 다시 실행해주세요.')));
    }
  }

  void _showPointChargePop(int points) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) =>
          _PointChargeCompletePop(points: points, onDone: () => entry.remove()),
    );
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StickerlyColors.paper,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const BackChevronGraphic(width: 24, height: 24),
        ),
        title: const Text('포인트 충전', style: TextStyle(fontSize: 20)),
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
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final landscape =
                        constraints.maxWidth > constraints.maxHeight;
                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: landscape ? 4 : 1,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: landscape ? 1.55 : 3.2,
                      ),
                      itemCount: _presets.length,
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
                              horizontal: 14,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? StickerlyColors.pink
                                  : Colors.white,
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
                                  width: 42,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? Colors.white.withValues(alpha: 0.18)
                                        : const Color(0xFFFFF4F9),
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                  child: Icon(
                                    Icons.toll_rounded,
                                    size: 25,
                                    color: selected
                                        ? Colors.white
                                        : StickerlyColors.purple,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        preset.bonus > 0
                                            ? '${preset.base.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',')} + ${preset.bonus.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',')} P'
                                            : '${points.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',')} P',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 21,
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
                                            fontSize: 13,
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
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: selected
                                              ? Colors.white.withValues(
                                                  alpha: 0.88,
                                                )
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
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _buyPlaceholder,
                icon: const Icon(Icons.shopping_bag_rounded),
                label: Text(
                  '${_points.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',')} P 충전',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 18,
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
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF7F6B86).withValues(alpha: 0.48),
              width: 1.7,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(2.5),
            child: ClipOval(
              child: Container(
                width: compact ? 40 : 46,
                height: compact ? 40 : 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.86),
                  shape: BoxShape.circle,
                ),
                child: avatarUrl == null || avatarUrl!.isEmpty
                    ? Icon(Icons.person_rounded, size: compact ? 14.4 : 24)
                    : Image.network(
                        avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.person_rounded,
                          size: compact ? 14.4 : 24,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeProfileButton extends StatelessWidget {
  const _HomeProfileButton({required this.onSelected, this.avatarUrl});

  final ValueChanged<_ProfileAction> onSelected;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ProfileAction>(
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 4,
              offset: const Offset(1, 2),
            ),
          ],
        ),
        child: ClipOval(
          child: SizedBox.square(
            dimension: 45,
            child: avatarUrl == null || avatarUrl!.isEmpty
                ? const SizedBox.shrink()
                : Image.network(
                    avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
          ),
        ),
      ),
    );
  }
}

class _HomeAdPlaceholder extends StatelessWidget {
  const _HomeAdPlaceholder({this.banner = false});

  /// banner=true: landscape 우하단용 (둥근 테두리)
  final bool banner;

  // 폰 기준 비율: 390 × 108
  static const _phoneRatio = 390.0 / 108.0;

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.sizeOf(context).shortestSide > 600;

    if (banner) {
      // 태블릿 가로 우측 패널 — 폰 비율 유지
      return AspectRatio(
        aspectRatio: _phoneRatio,
        child: Container(
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFEDEDED),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.08),
            ),
          ),
          child: const Text(
            '배너 광고',
            style: TextStyle(
              color: Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      );
    }

    if (isTablet) {
      // 태블릿 세로 하단 — 폰 비율 유지
      return AspectRatio(
        aspectRatio: _phoneRatio,
        child: Container(
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFEDEDED),
            border: Border(
              top: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
            ),
          ),
          child: const Text(
            '배너 광고',
            style: TextStyle(
              color: Colors.black,
              fontSize: 24,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      );
    }

    // 폰 — 기존 고정 높이 108px
    return Container(
      height: 108,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFEDEDED),
        border: Border(
          top: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
      ),
      child: const Text(
        '배너 광고',
        style: TextStyle(
          color: Colors.black,
          fontSize: 24,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _HomeDotPainter extends CustomPainter {
  const _HomeDotPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF0D9CD).withValues(alpha: 0.38);
    const gap = 27.0;
    for (var y = 10.0; y < size.height; y += gap) {
      for (var x = 18.0; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), 4.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HomeMenuCard extends StatefulWidget {
  const _HomeMenuCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.borderColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color color;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  State<_HomeMenuCard> createState() => _HomeMenuCardState();
}

class _HomeMenuCardState extends State<_HomeMenuCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 190),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 0.94,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 42,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.94,
          end: 1.035,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 34,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.035,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 24,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _playTap() {
    _controller.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 18,
              spreadRadius: 1,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _playTap,
            child: Container(
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: widget.borderColor, width: 2),
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.2),
                    Colors.white.withValues(alpha: 0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    style: const TextStyle(
                      color: StickerlyColors.ink,
                      fontSize: 32,
                      fontWeight: FontWeight.normal,
                      letterSpacing: -2.24,
                      height: 1,
                    ),
                  ),
                ),
              ),
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

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: StickerlyColors.ink, width: 2),
      ),
      child: Material(
        color: const Color(0xFFF2EDF4),
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
                      _DottedPreviewBackground(
                        assetPath: background?.assetPath,
                      ),
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
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                          visualDensity: VisualDensity.compact,
                          icon: Image.asset(
                            _expanded
                                ? StickerlyAssets.up
                                : StickerlyAssets.down,
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
      ),
    );
  }
}

class _StickerBookGridTile extends StatelessWidget {
  const _StickerBookGridTile({
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
  Widget build(BuildContext context) {
    final background = catalog.backgrounds
        .where((item) => item.id == project.background?.id)
        .firstOrNull;
    final topSticker = [...project.stickerItems]
      ..sort((a, b) => b.zIndex.compareTo(a.zIndex));
    final stickerPath = topSticker.isEmpty
        ? null
        : catalog.packs
              .where((pack) => pack.id == topSticker.first.packId)
              .firstOrNull
              ?.stickers
              .where((asset) => asset.id == topSticker.first.assetId)
              .firstOrNull
              ?.assetPath;
    return _StickerBookTileShell(
      onTap: onOpen,
      menu: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.arrow_drop_down_rounded, size: 32),
        onSelected: (value) {
          switch (value) {
            case 'rename':
              onRename();
            case 'duplicate':
              onDuplicate();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'rename', child: Text('이름 변경')),
          PopupMenuItem(value: 'duplicate', child: Text('복제')),
          PopupMenuItem(value: 'delete', child: Text('삭제')),
        ],
      ),
      preview: Stack(
        fit: StackFit.expand,
        children: [
          if (project.thumbnailPath?.isNotEmpty == true)
            AssetFileImage(path: project.thumbnailPath!, fit: BoxFit.cover)
          else ...[
            _DottedPreviewBackground(assetPath: background?.assetPath),
            if (stickerPath != null)
              Padding(
                padding: const EdgeInsets.all(18),
                child: AssetFileImage(path: stickerPath, fit: BoxFit.contain),
              ),
          ],
        ],
      ),
      title: project.title,
    );
  }
}

class _StickerBookNewTile extends StatelessWidget {
  const _StickerBookNewTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _StickerBookTileShell(
      onTap: onTap,
      title: '',
      showFooter: false,
      preview: const _StickerBookNewPreview(),
    );
  }
}

class _StickerBookNewPreview extends StatelessWidget {
  const _StickerBookNewPreview();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _HomeDotPainter(),
      child: Center(
        child: Container(
          width: 53,
          height: 53,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFE95F8B),
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 34),
        ),
      ),
    );
  }
}

class _StickerBookTileShell extends StatelessWidget {
  const _StickerBookTileShell({
    required this.onTap,
    required this.preview,
    required this.title,
    this.menu,
    this.showFooter = true,
  });

  final VoidCallback onTap;
  final Widget preview;
  final String title;
  final Widget? menu;
  final bool showFooter;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.17),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: const BorderSide(color: Color(0xFFE8DDD4), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Expanded(child: preview),
            if (showFooter)
              Container(
                height: 50,
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(10, 0, 4, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF2A2929),
                          fontSize: 18,
                          fontWeight: FontWeight.normal,
                          letterSpacing: -0.72,
                        ),
                      ),
                    ),
                    if (menu != null) menu!,
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.page,
    required this.pageCount,
    required this.onChanged,
  });

  final int page;
  final int pageCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        height: 28,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < pageCount; index++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: index == page ? null : () => onChanged(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: index == page ? 18 : 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: index == page
                        ? StickerlyColors.pink
                        : StickerlyColors.ink.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(99),
                  ),
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

// ignore: unused_element
class _NewProjectCard extends StatelessWidget {
  const _NewProjectCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: StickerlyColors.ink, width: 2),
      ),
      child: Material(
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

class _DrawerStoreButton extends StatelessWidget {
  const _DrawerStoreButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFF8E7AA3), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 10.7,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Image.asset(StickerlyAssets.storeBanner, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _DrawerSearchField extends StatelessWidget {
  const _DrawerSearchField({required this.onChanged, this.iconSize = 21});

  final ValueChanged<String> onChanged;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final centered = iconSize > 21;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFEFEFE),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFE8DDD4), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 10.7,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.search_rounded, size: iconSize),
          prefixIconConstraints: centered
              ? BoxConstraints(minWidth: iconSize + 16, minHeight: iconSize)
              : null,
          border: InputBorder.none,
          contentPadding: centered
              ? EdgeInsets.zero
              : const EdgeInsets.only(top: 8),
        ),
      ),
    );
  }
}

class _DrawerSortButton extends StatelessWidget {
  const _DrawerSortButton({required this.sort, required this.onChanged});

  final _StoreSort sort;
  final ValueChanged<_StoreSort> onChanged;

  String get _label => switch (sort) {
    _StoreSort.latest => '최신순',
    _StoreSort.price => '가격순',
    _StoreSort.name => '이름순',
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_StoreSort>(
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => const [
        PopupMenuItem(value: _StoreSort.latest, child: Text('최신순')),
        PopupMenuItem(value: _StoreSort.price, child: Text('가격순')),
        PopupMenuItem(value: _StoreSort.name, child: Text('이름순')),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFEFEFE),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFFE8DDD4), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 10.7,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.arrow_drop_down_rounded,
                  color: Color(0xFF9B928F),
                  size: 24,
                ),
                Text(
                  _label,
                  style: const TextStyle(
                    color: Color(0xFF2A2828),
                    fontSize: 18,
                    fontWeight: FontWeight.normal,
                    letterSpacing: -0.9,
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
    final compact = MediaQuery.sizeOf(context).shortestSide < 430;
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
          borderRadius: BorderRadius.circular(9),
          side: const BorderSide(color: Color(0xFFE8DDD4), width: 2),
        ),
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.17),
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
                        // 첫 배경 (없으면 그라데이션 폴백)
                        if (background != null && background.isUsable)
                          AssetFileImage(
                            path: background.assetPath,
                            fit: BoxFit.cover,
                          )
                        else
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFFFEEF5), Color(0xFFEAF6FF)],
                              ),
                            ),
                          ),
                        // 첫 스티커 (잘리지 않게 패딩 충분히)
                        if (firstSticker != null && firstSticker.isUsable)
                          Padding(
                            padding: EdgeInsets.all(compact ? 18 : 24),
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
                    padding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: compact ? 4 : 6,
                    ),
                    color: Colors.white,
                    child: Text(
                      pack.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFF2A2828),
                        fontWeight: FontWeight.normal,
                        fontSize: compact ? 10.5 : 12,
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                right: 2,
                top: 2,
                child: Transform.scale(
                  scale: compact ? 0.48 : 0.52,
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

class _AssetThumbnailGrid extends StatefulWidget {
  const _AssetThumbnailGrid({required this.paths, required this.fit});

  final List<String> paths;
  final BoxFit fit;

  @override
  State<_AssetThumbnailGrid> createState() => _AssetThumbnailGridState();
}

class _AssetThumbnailGridState extends State<_AssetThumbnailGrid> {
  String? _previewPath;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 112).floor().clamp(2, 6);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _previewPath == null
                    ? null
                    : () => setState(() => _previewPath = null),
              ),
            ),
            GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: widget.paths.length,
              itemBuilder: (context, index) => _PreviewableAssetCard(
                path: widget.paths[index],
                fit: widget.fit,
                selected: _previewPath == widget.paths[index],
                onTap: () {
                  setState(() {
                    _previewPath = _previewPath == widget.paths[index]
                        ? null
                        : widget.paths[index];
                  });
                },
              ),
            ),
            if (_previewPath != null)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => setState(() => _previewPath = null),
                  child: IgnorePointer(
                    child: Center(
                      child: _LargeAssetPreview(
                        path: _previewPath!,
                        fit: widget.fit,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LargeAssetPreview extends StatelessWidget {
  const _LargeAssetPreview({required this.path, required this.fit});

  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final size = (MediaQuery.sizeOf(context).shortestSide * 0.62).clamp(
      220.0,
      320.0,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: StickerlyColors.ink.withValues(alpha: 0.32),
            blurRadius: 34,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: SizedBox.square(
        dimension: size,
        child: Padding(
          padding: fit == BoxFit.contain
              ? const EdgeInsets.all(18)
              : EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: AssetFileImage(path: path, fit: fit),
          ),
        ),
      ),
    );
  }
}

class _PreviewableAssetCard extends StatelessWidget {
  const _PreviewableAssetCard({
    required this.path,
    required this.fit,
    required this.selected,
    required this.onTap,
  });

  final String path;
  final BoxFit fit;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? StickerlyColors.pink : StickerlyColors.line,
          width: selected ? 2.2 : 1.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: fit == BoxFit.contain
              ? const EdgeInsets.all(8)
              : EdgeInsets.zero,
          child: AssetFileImage(path: path, fit: fit),
        ),
      ),
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

class _StickerBookTransitionLoader extends StatelessWidget {
  const _StickerBookTransitionLoader();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 14),
          Text('잠시만요'),
        ],
      ),
    );
  }
}

class _ProjectTransitionLoader extends StatelessWidget {
  const _ProjectTransitionLoader();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: StickerlyColors.paper.withValues(alpha: 0.86),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text('캔버스 준비 중'),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// 설정 화면
// ══════════════════════════════════════════════════

class _SettingsScreen extends StatefulWidget {
  const _SettingsScreen({required this.account, required this.onLogout});

  final AccountProfile account;
  final VoidCallback onLogout;

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  bool _soundEnabled = !StickerlySfx.muted;

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 4),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF9B8FA0),
            letterSpacing: 0.4,
          ),
        ),
      );

  Widget _tile({
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? titleColor,
  }) =>
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: titleColor ?? const Color(0xFF2A2828),
          ),
        ),
        subtitle: subtitle != null
            ? Text(subtitle,
                style: const TextStyle(fontSize: 13, color: Color(0xFF9B8FA0)))
            : null,
        trailing: trailing ??
            (onTap != null
                ? const Icon(Icons.chevron_right_rounded,
                    color: Color(0xFFBBAFBF))
                : null),
        onTap: onTap,
      );

  Divider get _divider => const Divider(
      height: 1, indent: 18, endIndent: 18, color: Color(0xFFEDE5E9));

  Future<void> _toggleSound(bool value) async {
    setState(() => _soundEnabled = value);
    await StickerlySfx.setMuted(!value);
  }

  Future<void> _changePassword() async {
    final newPw = await showDialog<String>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (newPw == null || !mounted) return;
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: newPw));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비밀번호가 변경됐어요.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('변경 실패: $e')));
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('정말 탈퇴할까요?'),
        content: const Text('모든 스티커북과 포인트가 사라지고\n복구할 수 없어요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('탈퇴')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await Supabase.instance.client.rpc('delete_account');
    } catch (_) {}
    if (!mounted) return;
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    widget.onLogout();
  }

  void _openPointHistory() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _PointHistoryScreen(account: widget.account),
        ),
      );

  void _openPurchaseHistory() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _PurchaseHistoryScreen(account: widget.account),
        ),
      );

  void _copyEmail() {
    Clipboard.setData(const ClipboardData(text: 'support@stickerly.app'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('이메일 복사됨: support@stickerly.app')),
    );
  }

  void _openPolicy(String title, String body) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _PolicyScreen(title: title, body: body),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: StickerlyColors.paper,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            // 헤더
            DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFFFC2A7),
                    Color(0xFFF5B4C8),
                    Color(0xFFD9B5FF)
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 10.7,
                      offset: Offset(0, 4)),
                ],
              ),
              child: SizedBox(
                height: 60 + topPad,
                child: Stack(
                  children: [
                    Positioned(
                      left: 12,
                      top: topPad,
                      bottom: 0,
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        child:
                            const Center(child: StickerlyWordmark(scale: 0.78)),
                      ),
                    ),
                    Positioned(
                      left: 124,
                      top: topPad,
                      bottom: 0,
                      child: Row(
                        children: [
                          InkWell(
                            onTap: () => Navigator.pop(context),
                            child: const Row(children: [
                              BackChevronGraphic(width: 19, height: 19),
                              SizedBox(width: 5),
                            ]),
                          ),
                          const Text(
                            '설정',
                            style: TextStyle(
                              color: Color(0xFF2A2828),
                              fontSize: 20,
                              fontWeight: FontWeight.normal,
                              letterSpacing: -0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 바디
            Expanded(
              child: ListView(
                padding: EdgeInsets.only(bottom: bottomPad + 20),
                children: [
                  // 소리
                  _section('소리'),
                  _card(child: SwitchListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 18),
                    title: const Text('효과음',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w500)),
                    value: _soundEnabled,
                    activeColor: StickerlyColors.pink,
                    onChanged: _toggleSound,
                  )),
                  // 포인트 & 구매
                  _section('포인트 & 구매'),
                  _card(
                    child: Column(children: [
                      _tile(title: '포인트 내역', onTap: _openPointHistory),
                      _divider,
                      _tile(title: '구매한 스티커팩', onTap: _openPurchaseHistory),
                    ]),
                  ),
                  // 계정
                  _section('계정'),
                  _card(
                    child: Column(children: [
                      _tile(
                          title: '이메일',
                          subtitle: widget.account.email,
                          trailing: const SizedBox.shrink()),
                      _divider,
                      _tile(title: '비밀번호 변경', onTap: _changePassword),
                      _divider,
                      _tile(
                          title: '회원 탈퇴',
                          titleColor: Colors.red,
                          onTap: _deleteAccount),
                    ]),
                  ),
                  // 앱 정보
                  _section('앱 정보'),
                  _card(
                    child: Column(children: [
                      _tile(
                          title: '버전',
                          trailing: const Text('1.0.0',
                              style: TextStyle(
                                  color: Color(0xFF9B8FA0), fontSize: 15))),
                      _divider,
                      _tile(
                          title: '이용약관',
                          onTap: () => _openPolicy('이용약관', _kTermsText)),
                      _divider,
                      _tile(
                          title: '개인정보처리방침',
                          onTap: () =>
                              _openPolicy('개인정보처리방침', _kPrivacyText)),
                      _divider,
                      _tile(
                          title: '문의하기',
                          subtitle: 'support@stickerly.app',
                          onTap: _copyEmail),
                    ]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: child,
        ),
      );
}

// ── 비밀번호 변경 다이얼로그 ──────────────────────────

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _pw = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (_pw.text.length < 8) {
      setState(() => _error = '비밀번호는 8자 이상이어야 해요.');
      return;
    }
    if (_pw.text != _confirm.text) {
      setState(() => _error = '비밀번호가 일치하지 않아요.');
      return;
    }
    Navigator.pop(context, _pw.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('비밀번호 변경'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pw,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: '새 비밀번호',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: _obscure,
            decoration: const InputDecoration(labelText: '비밀번호 확인'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('취소')),
        FilledButton(onPressed: _submit, child: const Text('변경')),
      ],
    );
  }
}

// ── 포인트 내역 화면 ──────────────────────────────────

class _PointHistoryScreen extends StatefulWidget {
  const _PointHistoryScreen({required this.account});
  final AccountProfile account;

  @override
  State<_PointHistoryScreen> createState() => _PointHistoryScreenState();
}

class _PointHistoryScreenState extends State<_PointHistoryScreen> {
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('point_transactions')
          .select('points,type,description,created_at')
          .eq('user_id', widget.account.userId)
          .order('created_at', ascending: false)
          .limit(100) as List<dynamic>;
      if (mounted) {
        setState(() => _rows = rows.cast<Map<String, dynamic>>());
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String _fmt(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StickerlyColors.paper,
      appBar: AppBar(
        backgroundColor: StickerlyColors.paper,
        elevation: 0,
        leading: IconButton(
          icon: const BackChevronGraphic(width: 22, height: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('포인트 내역',
            style: TextStyle(fontFamily: 'MemomentKkukkukk', fontSize: 22)),
      ),
      body: Builder(builder: (context) {
        if (_rows == null && _error == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_error != null) {
          return Center(
              child:
                  Text('불러오기 실패\n$_error', textAlign: TextAlign.center));
        }
        final rows = _rows!;
        if (rows.isEmpty) {
          return const Center(child: Text('포인트 내역이 없어요.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final row = rows[i];
            final pts = (row['points'] as num?)?.toInt() ?? 0;
            final isCredit = (row['type'] as String?) == 'credit' || pts > 0;
            final desc = (row['description'] as String?) ?? '';
            final date = _fmt((row['created_at'] as String?) ?? '');
            return ListTile(
              title: Text(desc.isEmpty
                  ? (isCredit ? '포인트 충전' : '포인트 사용')
                  : desc),
              subtitle: Text(date),
              trailing: Text(
                '${isCredit ? '+' : ''}${pts.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',')} P',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color:
                      isCredit ? const Color(0xFF5B8FD4) : StickerlyColors.pink,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

// ── 구매 내역 화면 ────────────────────────────────────

class _PurchaseHistoryScreen extends StatefulWidget {
  const _PurchaseHistoryScreen({required this.account});
  final AccountProfile account;

  @override
  State<_PurchaseHistoryScreen> createState() => _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends State<_PurchaseHistoryScreen> {
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('user_pack_entitlements')
          .select('pack_id,created_at,products(name,price_amount)')
          .eq('user_id', widget.account.userId)
          .isFilter('revoked_at', null)
          .order('created_at', ascending: false) as List<dynamic>;
      if (mounted) setState(() => _items = rows.cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String _fmt(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StickerlyColors.paper,
      appBar: AppBar(
        backgroundColor: StickerlyColors.paper,
        elevation: 0,
        leading: IconButton(
          icon: const BackChevronGraphic(width: 22, height: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('구매한 스티커팩',
            style: TextStyle(fontFamily: 'MemomentKkukkukk', fontSize: 22)),
      ),
      body: Builder(builder: (context) {
        if (_items == null && _error == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_error != null) {
          return Center(
              child:
                  Text('불러오기 실패\n$_error', textAlign: TextAlign.center));
        }
        final items = _items!;
        if (items.isEmpty) {
          return const Center(child: Text('구매한 스티커팩이 없어요.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final item = items[i];
            final product = item['products'] as Map<String, dynamic>?;
            final name = (product?['name'] as String?) ??
                (item['pack_id'] as String?) ??
                '-';
            final price = (product?['price_amount'] as num?)?.toInt();
            final date = _fmt((item['created_at'] as String?) ?? '');
            return ListTile(
              leading: const Icon(Icons.auto_awesome_rounded,
                  color: Color(0xFFD48FBF)),
              title: Text(name),
              subtitle: Text(date),
              trailing: price != null
                  ? Text(
                      '${price.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => ',')} P',
                      style: const TextStyle(
                          color: Color(0xFF9B8FA0), fontSize: 14),
                    )
                  : null,
            );
          },
        );
      }),
    );
  }
}

// ── 약관 화면 ─────────────────────────────────────────

class _PolicyScreen extends StatelessWidget {
  const _PolicyScreen({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StickerlyColors.paper,
      appBar: AppBar(
        backgroundColor: StickerlyColors.paper,
        elevation: 0,
        leading: IconButton(
          icon: const BackChevronGraphic(width: 22, height: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(title,
            style: const TextStyle(
                fontFamily: 'MemomentKkukkukk', fontSize: 22)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text(body,
            style: const TextStyle(fontSize: 14, height: 1.8)),
      ),
    );
  }
}

const _kTermsText = '''
Stickerly 이용약관

제1조 (목적)
본 약관은 Stickerly(이하 "서비스")의 이용과 관련하여 필요한 사항을 규정합니다.

제2조 (서비스 이용)
이용자는 본 약관에 동의하고 서비스를 이용할 수 있습니다. 서비스는 스티커북 제작 및
스티커 관련 콘텐츠를 제공하며, 이용자는 서비스를 개인적·비상업적 목적으로만 이용할
수 있습니다.

제3조 (계정)
이용자는 정확한 정보로 계정을 생성해야 하며, 계정의 보안 유지에 대한 책임을 집니다.
타인의 계정을 무단으로 사용하거나 계정 정보를 타인에게 제공해서는 안 됩니다.

제4조 (콘텐츠)
서비스 내 모든 콘텐츠(스티커, 배경, 디자인 등)의 저작권은 Stickerly 또는 해당
콘텐츠 제공자에게 있습니다. 이용자는 서비스 이용 목적 외에 콘텐츠를 복제, 배포,
수정하거나 상업적으로 이용할 수 없습니다.

제5조 (금지 행위)
이용자는 다음 행위를 해서는 안 됩니다.
- 서비스의 정상적인 운영을 방해하는 행위
- 타인의 개인정보를 무단으로 수집·이용하는 행위
- 불법적이거나 타인에게 해를 끼치는 콘텐츠를 생성·공유하는 행위
- 서비스를 역공학, 해킹, 변조하려는 행위

제6조 (서비스 변경 및 중단)
Stickerly는 사전 통지 없이 서비스의 일부 또는 전부를 변경, 중단할 수 있습니다.

제7조 (면책)
Stickerly는 이용자의 귀책사유로 발생한 손해에 대해 책임을 지지 않습니다.

제8조 (준거법)
본 약관은 대한민국 법률에 따라 해석·적용됩니다.

최종 수정일: 2026년 1월 1일
''';

const _kPrivacyText = '''
개인정보처리방침

Stickerly(이하 "회사")는 이용자의 개인정보를 소중히 여기며, 관련 법률을 준수합니다.

1. 수집하는 개인정보 항목
- 이메일 주소, 닉네임, 프로필 이미지 (선택)
- 서비스 이용 기록, 접속 로그

2. 개인정보 수집 및 이용 목적
- 회원 가입 및 서비스 제공
- 콘텐츠 구매 및 포인트 관리
- 고객 지원 및 공지사항 전달

3. 개인정보 보유 및 이용 기간
회원 탈퇴 시까지 보유하며, 탈퇴 후 지체 없이 파기합니다.
단, 관련 법령에 따라 일정 기간 보관이 필요한 경우 해당 기간 동안 보관합니다.

4. 개인정보 제3자 제공
회사는 이용자의 동의 없이 개인정보를 제3자에게 제공하지 않습니다.
법령에 따른 요청이 있는 경우 예외로 합니다.

5. 개인정보 보호 조치
이용자의 개인정보는 암호화되어 안전하게 저장·관리됩니다.

6. 이용자의 권리
이용자는 언제든지 자신의 개인정보를 조회, 수정, 삭제를 요청할 수 있습니다.
계정 관리 화면 또는 이메일(support@stickerly.app)을 통해 요청해 주세요.

7. 문의
개인정보 관련 문의는 support@stickerly.app으로 연락해 주세요.

최종 수정일: 2026년 1월 1일
''';
