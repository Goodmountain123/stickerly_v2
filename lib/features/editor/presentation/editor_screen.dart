import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:stickerly_v2/app/assets/stickerly_assets.dart';
import 'package:stickerly_v2/app/theme/stickerly_colors.dart';
import 'package:stickerly_v2/app/widgets/asset_file_image.dart';
import 'package:stickerly_v2/app/widgets/back_chevron.dart';
import 'package:stickerly_v2/core/audio/stickerly_sfx.dart';
import 'package:stickerly_v2/features/assets/domain/asset_catalog.dart';
import 'package:stickerly_v2/features/projects/domain/project_item.dart';
import 'package:stickerly_v2/features/projects/domain/project_repository.dart';
import 'package:stickerly_v2/features/projects/domain/sticker_project.dart';
import 'package:uuid/uuid.dart';

enum _TrayTab { stickers, text, background }

class _StickerDragPayload {
  const _StickerDragPayload({
    required this.pack,
    required this.asset,
    required this.previewSize,
  });

  final StickerPack pack;
  final StickerAsset asset;
  final double previewSize;
}

class _TextDragPayload {
  const _TextDragPayload({required this.fontFamily});

  final String fontFamily;
}

String _safeFileName(String value) {
  final sanitized = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return sanitized.isEmpty ? 'stickerly' : sanitized;
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    required this.project,
    required this.repository,
    required this.catalog,
    required this.hiddenPackIds,
    required this.onDownloadPack,
    super.key,
  });

  final StickerProject project;
  final ProjectRepository repository;
  final AssetCatalog catalog;
  final Set<String> hiddenPackIds;
  final Future<AssetCatalog> Function(StickerPack) onDownloadPack;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with WidgetsBindingObserver {
  late StickerProject _project;
  late AssetCatalog _catalog;
  late final TextEditingController _titleController;
  late final List<StickerProject> _history;
  late final TransformationController _viewportController;
  final _canvasKey = GlobalKey();
  final _exportButtonKey = GlobalKey();
  Rect _canvasCaptureRect = Rect.zero;
  var _historyIndex = 0;
  var _tab = _TrayTab.stickers;
  var _uiHidden = false;
  var _saving = false;
  double? _trayExtent;
  double _trayDragStartExtent = 0;
  double _trayDragStartPosition = 0;
  var _trayDragging = false;
  var _stickerGrabActive = false;
  String? _recentlyAddedStickerId;
  Timer? _autosaveTimer;
  String? _selectedItemId;
  final _deleteZoneKey = GlobalKey();

  int get _highestZ => [
    ..._project.stickerItems.map((item) => item.zIndex),
    ..._project.textItems.map((item) => item.zIndex),
  ].fold(-1, math.max);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _project = widget.project;
    _catalog = widget.catalog;
    _history = [_project];
    _titleController = TextEditingController(text: _project.title);
    _viewportController = TransformationController();
    _titleController.addListener(_scheduleAutosave);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosaveTimer?.cancel();
    _viewportController.dispose();
    _titleController.removeListener(_scheduleAutosave);
    _titleController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _autosaveTimer?.cancel();
      unawaited(_save());
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    final title = _titleController.text.trim();
    _project = _project.copyWith(
      title: title.isEmpty ? _project.title : title,
      updatedAt: DateTime.now(),
    );
    await widget.repository.save(_project);
    _saving = false;
  }

  Future<void> _close() async {
    _autosaveTimer?.cancel();
    await _captureProjectThumbnail();
    unawaited(_save());
    if (mounted) {
      StickerlySfx.play(StickerlyAssets.soundPage);
      Navigator.pop(context, _project);
    }
  }

  Future<void> _captureProjectThumbnail() async {
    if (!mounted) return;
    final previousSelection = _selectedItemId;
    if (previousSelection != null) {
      setState(() => _selectedItemId = null);
      await WidgetsBinding.instance.endOfFrame;
    }
    try {
      final boundary =
          _canvasKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null || boundary.size.isEmpty) return;
      final canvasSize = _canvasCaptureRect.isEmpty
          ? boundary.size
          : _canvasCaptureRect.size;
      final pixelRatio = math.min(
        1.0,
        360 / math.max(canvasSize.width, canvasSize.height),
      );
      final image = await _captureCanvasImage(boundary, pixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) return;
      final root = await getApplicationDocumentsDirectory();
      final directory = Directory('${root.path}/stickerly_thumbnails');
      await directory.create(recursive: true);
      final file = File('${directory.path}/${_project.id}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      _project = _project.copyWith(thumbnailPath: file.path);
    } catch (_) {
      // The project itself must still save if thumbnail capture is unavailable.
    } finally {
      if (mounted && previousSelection != null) {
        setState(() => _selectedItemId = previousSelection);
      }
    }
  }

  Future<void> _export() async {
    final action = await _showExportMenu();
    if (action == null) return;
    await _save();
    final previousSelection = _selectedItemId;
    setState(() => _selectedItemId = null);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    try {
      final boundary =
          _canvasKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('캔버스를 찾지 못했어요.');
      final canvasWidth = _canvasCaptureRect.isEmpty
          ? boundary.size.width
          : _canvasCaptureRect.width;
      final pixelRatio = _project.canvasWidth / canvasWidth;
      final image = await _captureCanvasImage(boundary, pixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('이미지를 만들지 못했어요.');
      if (!mounted) return;
      final data = bytes.buffer.asUint8List();
      if (action == _ExportAction.gallery) {
        var hasAccess = await Gal.hasAccess();
        if (!hasAccess) {
          hasAccess = await Gal.requestAccess();
        }
        if (!hasAccess) {
          throw StateError('사진 갤러리 접근 권한이 필요해요.');
        }
        await Gal.putImageBytes(data, name: _safeFileName(_project.title));
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('갤러리에 저장했어요.')));
        }
      } else {
        final fileName = '${_safeFileName(_project.title)}.png';
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(data, name: fileName, mimeType: 'image/png'),
            ],
            fileNameOverrides: [fileName],
            title: _project.title,
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
            downloadFallbackEnabled: true,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('이미지 저장 실패: $error')));
      }
    } finally {
      if (mounted) setState(() => _selectedItemId = previousSelection);
    }
  }

  Future<_ExportAction?> _showExportMenu() async {
    final buttonBox =
        _exportButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (buttonBox == null || overlay == null) return null;
    final buttonRect =
        buttonBox.localToGlobal(Offset.zero, ancestor: overlay) &
        buttonBox.size;
    return showMenu<_ExportAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        buttonRect.left,
        buttonRect.bottom + 8,
        overlay.size.width - buttonRect.right,
        overlay.size.height - buttonRect.bottom,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: Colors.white,
      elevation: 8,
      items: const [
        PopupMenuItem(
          value: _ExportAction.gallery,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.photo_library_rounded),
            title: Text('갤러리에 저장'),
          ),
        ),
        PopupMenuItem(
          value: _ExportAction.share,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.share_rounded),
            title: Text('공유'),
          ),
        ),
      ],
    );
  }

  Future<ui.Image> _captureCanvasImage(
    RenderRepaintBoundary boundary,
    double pixelRatio,
  ) async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    if (_canvasCaptureRect.isEmpty) return image;
    final crop = Rect.fromLTWH(
      _canvasCaptureRect.left * pixelRatio,
      _canvasCaptureRect.top * pixelRatio,
      _canvasCaptureRect.width * pixelRatio,
      _canvasCaptureRect.height * pixelRatio,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      image,
      crop,
      Rect.fromLTWH(0, 0, crop.width, crop.height),
      Paint(),
    );
    final picture = recorder.endRecording();
    final cropped = await picture.toImage(
      crop.width.round(),
      crop.height.round(),
    );
    image.dispose();
    picture.dispose();
    return cropped;
  }

  void _addStickerAt(StickerPack pack, StickerAsset asset, Offset position) {
    StickerlySfx.play(StickerlyAssets.soundPunch);
    const uuid = Uuid();
    final item = StickerItem(
      id: 'stk_${uuid.v4()}',
      packId: pack.id,
      assetId: asset.id,
      x: position.dx.clamp(0, _project.canvasWidth).toDouble(),
      y: position.dy.clamp(0, _project.canvasHeight).toDouble(),
      zIndex: _highestZ + 1,
    );
    _replaceProject(
      _project.copyWith(
        stickerItems: [..._project.stickerItems, item],
        updatedAt: DateTime.now(),
      ),
      commit: true,
    );
    setState(() {
      _selectedItemId = item.id;
      _recentlyAddedStickerId = item.id;
    });
    Future<void>.delayed(const Duration(milliseconds: 360), () {
      if (mounted && _recentlyAddedStickerId == item.id) {
        setState(() => _recentlyAddedStickerId = null);
      }
    });
  }

  double _stickerDragPreviewSize() {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return 118;
    final canvasScale = box.size.width / _project.canvasWidth;
    final viewportScale = _viewportController.value.getMaxScaleOnAxis();
    return 260 * canvasScale * viewportScale;
  }

  void _addTextAt(String fontFamily, Offset position) {
    const uuid = Uuid();
    final item = TextItem(
      id: 'txt_${uuid.v4()}',
      text: '텍스트',
      fontFamily: fontFamily,
      color: _project.lastTextColor,
      x: position.dx.clamp(0, _project.canvasWidth).toDouble(),
      y: position.dy.clamp(0, _project.canvasHeight).toDouble(),
      zIndex: _highestZ + 1,
    );
    _replaceProject(
      _project.copyWith(
        textItems: [..._project.textItems, item],
        updatedAt: DateTime.now(),
      ),
      commit: true,
    );
    setState(() => _selectedItemId = item.id);
  }

  void _updateSticker(StickerItem updated, {required bool commit}) {
    final current = _project.stickerItems
        .where((item) => item.id == updated.id)
        .firstOrNull;
    final next = current == null
        ? updated
        : updated.copyWith(zIndex: current.zIndex);
    _replaceProject(
      _project.copyWith(
        stickerItems: [
          for (final item in _project.stickerItems)
            if (item.id == updated.id) next else item,
        ],
        updatedAt: DateTime.now(),
      ),
      commit: commit,
    );
  }

  void _deleteSticker(String id) {
    StickerlySfx.play(StickerlyAssets.soundTrash);
    _replaceProject(
      _project.copyWith(
        stickerItems: _project.stickerItems
            .where((item) => item.id != id)
            .toList(),
        updatedAt: DateTime.now(),
      ),
      commit: true,
    );
    setState(() => _selectedItemId = null);
  }

  void _selectSticker(String id) {
    final sticker = _project.stickerItems
        .where((item) => item.id == id)
        .firstOrNull;
    if (sticker == null) {
      setState(() => _selectedItemId = id);
      return;
    }
    final topZ = _highestZ;
    setState(() => _selectedItemId = id);
    if (sticker.zIndex >= topZ) return;
    _replaceProject(
      _project.copyWith(
        stickerItems: [
          for (final item in _project.stickerItems)
            if (item.id == id) item.copyWith(zIndex: topZ + 1) else item,
        ],
        updatedAt: DateTime.now(),
      ),
      commit: true,
    );
  }

  void _setStickerGrabActive(bool active) {
    if (_stickerGrabActive == active) return;
    setState(() => _stickerGrabActive = active);
  }

  void _finishStickerGrab(String id, Offset globalPosition) {
    _setStickerGrabActive(false);
    final box = _deleteZoneKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (rect.inflate(18).contains(globalPosition)) {
      _deleteSticker(id);
    }
  }

  void _finishTextGrab(String id, Offset globalPosition) {
    _setStickerGrabActive(false);
    final box = _deleteZoneKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (rect.inflate(18).contains(globalPosition)) {
      StickerlySfx.play(StickerlyAssets.soundTrash);
      _deleteText(id);
    }
  }

  void _updateText(TextItem updated, {required bool commit}) {
    _replaceProject(
      _project.copyWith(
        textItems: [
          for (final item in _project.textItems)
            if (item.id == updated.id) updated else item,
        ],
        updatedAt: DateTime.now(),
      ),
      commit: commit,
    );
  }

  void _deleteText(String id) {
    _replaceProject(
      _project.copyWith(
        textItems: _project.textItems.where((item) => item.id != id).toList(),
        updatedAt: DateTime.now(),
      ),
      commit: true,
    );
    setState(() => _selectedItemId = null);
  }

  Future<void> _setBackground(BackgroundAsset background) async {
    if (!background.isUsable) return;
    final imageSize = await _readImageSize(background.assetPath);
    if (!mounted) return;
    var canvasWidth = _project.canvasWidth;
    var canvasHeight = _project.canvasHeight;
    if (imageSize != null && imageSize.width > 0 && imageSize.height > 0) {
      const base = 1080.0;
      if (imageSize.width >= imageSize.height) {
        canvasWidth = base.round();
        canvasHeight = (base * imageSize.height / imageSize.width).round();
      } else {
        canvasHeight = base.round();
        canvasWidth = (base * imageSize.width / imageSize.height).round();
      }
    }
    final xScale = canvasWidth / _project.canvasWidth;
    final yScale = canvasHeight / _project.canvasHeight;
    final itemScale = math.min(xScale, yScale);
    _replaceProject(
      _project.copyWith(
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
        background: ProjectBackground(type: 'asset', id: background.id),
        stickerItems: [
          for (final item in _project.stickerItems)
            item.copyWith(
              x: item.x * xScale,
              y: item.y * yScale,
              scale: item.scale * itemScale,
            ),
        ],
        textItems: [
          for (final item in _project.textItems)
            item.copyWith(
              x: item.x * xScale,
              y: item.y * yScale,
              scale: item.scale * itemScale,
            ),
        ],
        updatedAt: DateTime.now(),
      ),
      commit: true,
    );
    _viewportController.value = Matrix4.identity();
  }

  Future<Size?> _readImageSize(String path) async {
    if (path.isEmpty) return null;
    try {
      final bytes = path.startsWith('assets/')
          ? (await rootBundle.load(path)).buffer.asUint8List()
          : await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  Future<void> _downloadPack(StickerPack pack) async {
    final catalog = await widget.onDownloadPack(pack);
    if (!mounted) return;
    setState(() => _catalog = catalog);
  }

  void _flipSticker(String id, {required bool horizontal}) {
    final item = _project.stickerItems
        .where((item) => item.id == id)
        .firstOrNull;
    if (item == null) return;
    _updateSticker(
      item.copyWith(
        flipX: horizontal ? !item.flipX : item.flipX,
        flipY: horizontal ? item.flipY : !item.flipY,
      ),
      commit: true,
    );
  }

  void _replaceProject(StickerProject project, {required bool commit}) {
    setState(() => _project = project);
    if (!commit) return;
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(project);
    _historyIndex = _history.length - 1;
    _scheduleAutosave();
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 700), _save);
  }

  void _undo() {
    if (_historyIndex == 0) return;
    setState(() {
      _historyIndex -= 1;
      _project = _history[_historyIndex];
      _selectedItemId = null;
    });
    _scheduleAutosave();
  }

  void _redo() {
    if (_historyIndex >= _history.length - 1) return;
    setState(() {
      _historyIndex += 1;
      _project = _history[_historyIndex];
      _selectedItemId = null;
    });
    _scheduleAutosave();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _close();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final visibleCatalog = _catalog.visible(
                hiddenPackIds: widget.hiddenPackIds,
              );
              final bottomTray =
                  constraints.maxWidth <= 760 &&
                  constraints.maxHeight > constraints.maxWidth;
              final minTrayExtent = bottomTray ? 46.0 : 58.0;
              final defaultTrayExtent = bottomTray ? 302.0 : 300.0;
              final closeThreshold = bottomTray ? 138.0 : 116.0;
              final maxTrayExtent = bottomTray
                  ? constraints.maxHeight * 0.62
                  : constraints.maxWidth * 0.58;
              final trayExtent = (_trayExtent ?? defaultTrayExtent).clamp(
                minTrayExtent,
                maxTrayExtent,
              );
              final canvas = _CanvasViewport(
                project: _project,
                catalog: _catalog,
                repaintKey: _canvasKey,
                transformationController: _viewportController,
                selectedItemId: _selectedItemId,
                recentlyAddedStickerId: _recentlyAddedStickerId,
                onSelect: (id) => setState(() => _selectedItemId = id),
                onDropSticker: _addStickerAt,
                onDropText: _addTextAt,
                onUpdateSticker: _updateSticker,
                onUpdateText: _updateText,
                onSelectSticker: _selectSticker,
                onStickerGrabStart: () => _setStickerGrabActive(true),
                onStickerGrabEnd: _finishStickerGrab,
                onTextGrabEnd: _finishTextGrab,
                onFlipSticker: _flipSticker,
                onCanvasRectChanged: (rect) {
                  if (_canvasCaptureRect == rect) return;
                  _canvasCaptureRect = rect;
                },
              );
              final tray = _EditorTray(
                selected: _tab,
                catalog: visibleCatalog,
                horizontal: bottomTray,
                extent: trayExtent,
                minExtent: minTrayExtent,
                maxExtent: maxTrayExtent,
                onSelected: (tab) {
                  if (_tab != tab) {
                    StickerlySfx.play(StickerlyAssets.soundFlip);
                  }
                  setState(() => _tab = tab);
                },
                onResizeStart: (position) {
                  _trayDragStartExtent = trayExtent;
                  _trayDragStartPosition = position;
                  setState(() => _trayDragging = true);
                },
                onResizeUpdate: (position) {
                  final movement = _trayDragStartPosition - position;
                  setState(() {
                    _trayExtent = (_trayDragStartExtent + movement).clamp(
                      minTrayExtent,
                      maxTrayExtent,
                    );
                  });
                },
                onResizeEnd: () {
                  setState(() {
                    _trayDragging = false;
                    if (trayExtent <= closeThreshold) {
                      _trayExtent = minTrayExtent;
                    } else {
                      final rowExtent = bottomTray ? 104.0 : 116.0;
                      final headerExtent = bottomTray ? 96.0 : 70.0;
                      final snaps = [
                        for (var rows = 1; rows <= 3; rows++)
                          (headerExtent + rowExtent * rows).clamp(
                            minTrayExtent,
                            maxTrayExtent,
                          ),
                      ];
                      _trayExtent = snaps.reduce(
                        (best, snap) =>
                            (snap - trayExtent).abs() <
                                (best - trayExtent).abs()
                            ? snap
                            : best,
                      );
                    }
                  });
                },
                onOpen: () {
                  if (trayExtent > minTrayExtent + 8) return;
                  setState(() => _trayExtent = defaultTrayExtent);
                },
                onSetBackground: _setBackground,
                selectedBackgroundId: _project.background?.id,
                onDownloadPack: _downloadPack,
                stickerPreviewSize: _stickerDragPreviewSize,
              );

              return Column(
                children: [
                  if (!_uiHidden)
                    _EditorToolbar(
                      titleController: _titleController,
                      exportButtonKey: _exportButtonKey,
                      onBack: _close,
                      onExport: _export,
                      onUndo: _historyIndex > 0 ? _undo : null,
                      onRedo: _historyIndex < _history.length - 1
                          ? _redo
                          : null,
                    ),
                  Expanded(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (bottomTray)
                          AnimatedPositioned(
                            duration: _trayDragging
                                ? Duration.zero
                                : const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            left: 0,
                            top: 0,
                            right: 0,
                            bottom: _uiHidden ? 0 : trayExtent,
                            child: canvas,
                          )
                        else
                          Row(
                            children: [
                              Expanded(child: canvas),
                              if (!_uiHidden)
                                AnimatedContainer(
                                  duration: _trayDragging
                                      ? Duration.zero
                                      : const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  width: trayExtent,
                                  child: tray,
                                ),
                            ],
                          ),
                        if (bottomTray && !_uiHidden)
                          AnimatedPositioned(
                            duration: _trayDragging
                                ? Duration.zero
                                : const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: trayExtent,
                            child: tray,
                          ),
                        Positioned(
                          left: 0,
                          top: 0,
                          child: _CanvasControlTabs(
                            uiHidden: _uiHidden,
                            onFit: () {
                              _viewportController.value = Matrix4.identity();
                              setState(() => _selectedItemId = null);
                            },
                            onToggleUi: () =>
                                setState(() => _uiHidden = !_uiHidden),
                          ),
                        ),
                        AnimatedPositioned(
                          key: _deleteZoneKey,
                          duration: const Duration(milliseconds: 210),
                          curve: Curves.easeOutBack,
                          left: bottomTray
                              ? constraints.maxWidth * 0.1
                              : math.max(
                                  110,
                                  (constraints.maxWidth - trayExtent - 208) / 2,
                                ),
                          right: bottomTray
                              ? constraints.maxWidth * 0.1
                              : math.max(
                                  trayExtent + 110,
                                  (constraints.maxWidth - trayExtent - 208) /
                                          2 +
                                      trayExtent,
                                ),
                          top: _stickerGrabActive && !_uiHidden ? -192 : -326,
                          height: 192,
                          child: IgnorePointer(
                            ignoring: !_stickerGrabActive,
                            child: _StickerDeleteZone(
                              active: _stickerGrabActive && !_uiHidden,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _ExportAction { gallery, share }

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.titleController,
    required this.exportButtonKey,
    required this.onBack,
    required this.onExport,
    required this.onUndo,
    required this.onRedo,
  });

  final TextEditingController titleController;
  final GlobalKey exportButtonKey;
  final VoidCallback onBack;
  final VoidCallback onExport;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final landscape = screenSize.width > screenSize.height;
    final mobile = screenSize.width <= 760;
    final scale = landscape ? 0.6 : 1.0;
    final buttonSize = (mobile ? 38.0 : 54.0) * scale;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: (mobile ? 10 : 18) * scale,
        vertical: (mobile ? 8 : 12) * scale,
      ),
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
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: '목록으로',
            padding: EdgeInsets.zero,
            constraints:
                BoxConstraints.tightFor(width: buttonSize, height: buttonSize),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(buttonSize * 0.3),
                side: const BorderSide(color: StickerlyColors.line, width: 1.5),
              ),
            ),
            icon: Opacity(
              opacity: onBack == null ? 0.38 : 1,
              child: BackChevronGraphic(width: buttonSize * 0.68, height: buttonSize * 0.68),
            ),
          ),
          SizedBox(width: 7 * scale),
          Expanded(
            child: TextField(
              controller: titleController,
              maxLength: 40,
              style: TextStyle(
                fontSize: (mobile ? 18 : 26) * scale,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                counterText: '',
                isDense: true,
                filled: false,
                border: InputBorder.none,
              ),
            ),
          ),
          SizedBox(width: 5 * scale),
          _EditorIconButton(
            asset: StickerlyAssets.undo,
            label: '실행 취소',
            onPressed: onUndo,
            size: buttonSize,
          ),
          SizedBox(width: 4 * scale),
          _EditorIconButton(
            asset: StickerlyAssets.redo,
            label: '다시 실행',
            onPressed: onRedo,
            size: buttonSize,
          ),
          SizedBox(width: 6 * scale),
          SizedBox(
            key: exportButtonKey,
            width: buttonSize,
            height: buttonSize,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [StickerlyColors.pink, Color(0xFFFF91C5)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: StickerlyColors.pinkPressed,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: onExport,
                tooltip: '완성',
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: (mobile ? 22 : 30) * scale,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorIconButton extends StatelessWidget {
  const _EditorIconButton({
    required this.asset,
    required this.label,
    required this.onPressed,
    required this.size,
  });

  final String asset;
  final String label;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: label,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.58),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(size * 0.3),
          side: const BorderSide(color: StickerlyColors.line, width: 1.5),
        ),
      ),
      icon: Opacity(
        opacity: onPressed == null ? 0.38 : 1,
        child: Image.asset(asset, width: size * 0.68, height: size * 0.68),
      ),
    );
  }
}

class _CanvasControlTabs extends StatelessWidget {
  const _CanvasControlTabs({
    required this.uiHidden,
    required this.onFit,
    required this.onToggleUi,
  });

  final bool uiHidden;
  final VoidCallback onFit;
  final VoidCallback onToggleUi;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFEEE3),
      elevation: 2,
      shadowColor: StickerlyColors.ink.withValues(alpha: 0.2),
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: StickerlyColors.line),
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(10),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CanvasTabButton(
              tooltip: '캔버스를 화면에 맞추기',
              icon: Icons.fit_screen_rounded,
              onPressed: onFit,
            ),
            Container(width: 1, height: 22, color: StickerlyColors.line),
            _CanvasTabButton(
              tooltip: uiHidden ? 'UI 보이기' : 'UI 숨기기',
              asset: uiHidden ? StickerlyAssets.up : StickerlyAssets.down,
              onPressed: onToggleUi,
            ),
          ],
        ),
      ),
    );
  }
}

class _CanvasTabButton extends StatelessWidget {
  const _CanvasTabButton({
    required this.tooltip,
    required this.onPressed,
    this.icon,
    this.asset,
  });

  final String tooltip;
  final IconData? icon;
  final String? asset;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 44, height: 30),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        foregroundColor: StickerlyColors.ink,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      icon: asset == null
          ? Icon(icon, size: 18)
          : Image.asset(asset!, width: 18, height: 18),
    );
  }
}

class _CanvasViewport extends StatelessWidget {
  const _CanvasViewport({
    required this.project,
    required this.catalog,
    required this.repaintKey,
    required this.transformationController,
    required this.selectedItemId,
    required this.recentlyAddedStickerId,
    required this.onSelect,
    required this.onDropSticker,
    required this.onDropText,
    required this.onUpdateSticker,
    required this.onUpdateText,
    required this.onSelectSticker,
    required this.onStickerGrabStart,
    required this.onStickerGrabEnd,
    required this.onTextGrabEnd,
    required this.onFlipSticker,
    required this.onCanvasRectChanged,
  });

  final StickerProject project;
  final AssetCatalog catalog;
  final GlobalKey repaintKey;
  final TransformationController transformationController;
  final String? selectedItemId;
  final String? recentlyAddedStickerId;
  final ValueChanged<String?> onSelect;
  final void Function(StickerPack pack, StickerAsset asset, Offset position)
  onDropSticker;
  final void Function(String fontFamily, Offset position) onDropText;
  final void Function(StickerItem item, {required bool commit}) onUpdateSticker;
  final void Function(TextItem item, {required bool commit}) onUpdateText;
  final ValueChanged<String> onSelectSticker;
  final VoidCallback onStickerGrabStart;
  final void Function(String id, Offset globalPosition) onStickerGrabEnd;
  final void Function(String id, Offset globalPosition) onTextGrabEnd;
  final void Function(String id, {required bool horizontal}) onFlipSticker;
  final ValueChanged<Rect> onCanvasRectChanged;

  @override
  Widget build(BuildContext context) {
    final background = project.background;
    final backgroundPath = background?.id == null
        ? null
        : catalog.backgrounds
              .where((item) => item.id == background!.id)
              .firstOrNull
              ?.assetPath;

    return CustomPaint(
      painter: _EditorMatPainter(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const padding = 28.0;
          final availableWidth = math.max(
            1.0,
            constraints.maxWidth - padding * 2,
          );
          final availableHeight = math.max(
            1.0,
            constraints.maxHeight - padding * 2,
          );
          final ratio = project.canvasWidth / project.canvasHeight;
          var width = availableWidth;
          var height = width / ratio;
          if (height > availableHeight) {
            height = availableHeight;
            width = height * ratio;
          }
          final canvasScale = width / project.canvasWidth;

          void keepSmallCanvasCentered() {
            final scale = transformationController.value.getMaxScaleOnAxis();
            if (scale > 1) return;
            transformationController.value = Matrix4.identity()
              ..setEntry(0, 0, scale)
              ..setEntry(1, 1, scale)
              ..setEntry(0, 3, constraints.maxWidth * (1 - scale) / 2)
              ..setEntry(1, 3, constraints.maxHeight * (1 - scale) / 2);
          }

          Offset dropPosition(Offset global, double previewSize) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return Offset.zero;
            final local = box.globalToLocal(
              global + Offset(previewSize / 2, previewSize / 2),
            );
            final canvasOrigin = Offset(
              (constraints.maxWidth - width) / 2,
              (constraints.maxHeight - height) / 2,
            );
            return (local - canvasOrigin) / canvasScale;
          }

          final canvasOrigin = Offset(
            (constraints.maxWidth - width) / 2,
            (constraints.maxHeight - height) / 2,
          );
          final canvasRect = canvasOrigin & Size(width, height);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onCanvasRectChanged(canvasRect);
          });

          return DragTarget<Object>(
            onAcceptWithDetails: (details) {
              final data = details.data;
              if (data is _StickerDragPayload) {
                onDropSticker(
                  data.pack,
                  data.asset,
                  dropPosition(details.offset, data.previewSize),
                );
              } else if (data is _TextDragPayload) {
                onDropText(data.fontFamily, dropPosition(details.offset, 180));
              }
            },
            builder: (context, _, _) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(null),
              child: InteractiveViewer(
                transformationController: transformationController,
                minScale: 0.5,
                maxScale: 4,
                boundaryMargin: const EdgeInsets.all(240),
                panEnabled: true,
                scaleEnabled: true,
                onInteractionUpdate: (_) => keepSmallCanvasCentered(),
                onInteractionEnd: (_) => keepSmallCanvasCentered(),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(null),
                    child: RepaintBoundary(
                      key: repaintKey,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fromRect(
                            rect: canvasRect,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: StickerlyColors.ink.withValues(
                                      alpha: 0.16,
                                    ),
                                    blurRadius: 28,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: backgroundPath == null
                                  ? null
                                  : AssetFileImage(
                                      path: backgroundPath,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                          ),
                          for (final item in <ProjectItem>[
                            ...project.stickerItems,
                            ...project.textItems,
                          ]..sort((a, b) => a.zIndex.compareTo(b.zIndex)))
                            if (item is StickerItem)
                              _StickerNode(
                                key: ValueKey(item.id),
                                item: item,
                                assetPath: _assetPath(item),
                                canvasScale: canvasScale,
                                canvasOffset: canvasOrigin,
                                viewportScale: () => transformationController
                                    .value
                                    .getMaxScaleOnAxis(),
                                selected: selectedItemId == item.id,
                                animateIn: recentlyAddedStickerId == item.id,
                                onSelect: () => onSelectSticker(item.id),
                                onGrabStart: onStickerGrabStart,
                                onGrabEnd: (globalPosition) =>
                                    onStickerGrabEnd(item.id, globalPosition),
                                onFlipHorizontal: () =>
                                    onFlipSticker(item.id, horizontal: true),
                                onFlipVertical: () =>
                                    onFlipSticker(item.id, horizontal: false),
                                onChanged: onUpdateSticker,
                              )
                            else if (item is TextItem)
                              _TextNode(
                                key: ValueKey(item.id),
                                item: item,
                                canvasScale: canvasScale,
                                canvasOffset: canvasOrigin,
                                selected: selectedItemId == item.id,
                                onSelect: () => onSelect(item.id),
                                onGrabStart: onStickerGrabStart,
                                onGrabEnd: (globalPosition) =>
                                    onTextGrabEnd(item.id, globalPosition),
                                onChanged: onUpdateText,
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _assetPath(StickerItem item) {
    final pack = catalog.packs
        .where((pack) => pack.id == item.packId)
        .firstOrNull;
    return pack?.stickers
            .where((asset) => asset.id == item.assetId)
            .firstOrNull
            ?.assetPath ??
        '';
  }
}

class _EditorMatPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFF5E9), Color(0xFFF1EAF4)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);
    final dot = Paint()
      ..color = const Color(0xFF615478).withValues(alpha: 0.08);
    for (double y = 1; y < size.height; y += 22) {
      for (double x = 1; x < size.width; x += 22) {
        canvas.drawCircle(Offset(x, y), 1.3, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StickerNode extends StatefulWidget {
  const _StickerNode({
    required this.item,
    required this.assetPath,
    required this.canvasScale,
    required this.canvasOffset,
    required this.viewportScale,
    required this.selected,
    required this.animateIn,
    required this.onSelect,
    required this.onGrabStart,
    required this.onGrabEnd,
    required this.onFlipHorizontal,
    required this.onFlipVertical,
    required this.onChanged,
    super.key,
  });

  final StickerItem item;
  final String assetPath;
  final double canvasScale;
  final Offset canvasOffset;
  final double Function() viewportScale;
  final bool selected;
  final bool animateIn;
  final VoidCallback onSelect;
  final VoidCallback onGrabStart;
  final ValueChanged<Offset> onGrabEnd;
  final VoidCallback onFlipHorizontal;
  final VoidCallback onFlipVertical;
  final void Function(StickerItem item, {required bool commit}) onChanged;

  @override
  State<_StickerNode> createState() => _StickerNodeState();
}

class _StickerNodeState extends State<_StickerNode> {
  static const _baseSize = 260.0;
  static final Map<String, Future<_AlphaMask?>> _maskCache = {};
  late StickerItem _gestureStart;
  late StickerItem _latest;
  _AlphaMask? _alphaMask;
  Offset _focalStart = Offset.zero;
  Offset _latestGlobalPosition = Offset.zero;
  Offset _handleCenter = Offset.zero;
  Offset _handleStartVector = Offset.zero;
  double _motionScale = 1;
  int _popSequence = 0;

  void _playGrabPop() {
    final sequence = ++_popSequence;
    setState(() => _motionScale = 1.18);
    Future<void>.delayed(const Duration(milliseconds: 110), () {
      if (!mounted || sequence != _popSequence) return;
      setState(() => _motionScale = 1);
    });
  }

  void _playDropPop() {
    final sequence = ++_popSequence;
    setState(() => _motionScale = 1.22);
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      if (!mounted || sequence != _popSequence) return;
      setState(() => _motionScale = 0.94);
    });
    Future<void>.delayed(const Duration(milliseconds: 210), () {
      if (!mounted || sequence != _popSequence) return;
      setState(() => _motionScale = 1);
    });
  }

  @override
  void initState() {
    super.initState();
    _latest = widget.item;
    if (widget.animateIn) {
      _motionScale = 1.26;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _motionScale = 1);
      });
    }
    _loadAlphaMask();
  }

  @override
  void didUpdateWidget(covariant _StickerNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    _latest = widget.item;
    if (oldWidget.assetPath != widget.assetPath) _loadAlphaMask();
  }

  Future<void> _loadAlphaMask() async {
    final path = widget.assetPath;
    if (path.isEmpty) return;
    final mask = await _maskCache.putIfAbsent(path, () => _decodeMask(path));
    if (mounted && widget.assetPath == path) {
      setState(() => _alphaMask = mask);
    }
  }

  static Future<_AlphaMask?> _decodeMask(String path) async {
    try {
      final bytes = path.startsWith('assets/')
          ? (await rootBundle.load(path)).buffer.asUint8List()
          : await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final rgbaData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final mask = rgbaData == null
          ? null
          : _AlphaMask(
              width: image.width,
              height: image.height,
              rgba: rgbaData.buffer.asUint8List(),
            );
      image.dispose();
      codec.dispose();
      return mask;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseSize = _baseSize * widget.canvasScale * widget.item.scale;
    final aspect = _alphaMask == null || _alphaMask!.height == 0
        ? 1.0
        : _alphaMask!.width / _alphaMask!.height;
    final width = aspect >= 1 ? baseSize : baseSize * aspect;
    final height = aspect >= 1 ? baseSize / aspect : baseSize;
    final shortSide = math.min(width, height);
    final handleSize = (shortSide * 0.32).clamp(24.0, 68.0);
    final handleHitSize = handleSize;
    final controlPad = widget.selected ? handleHitSize : 0.0;
    final selectionWidth = (shortSide * 0.012).clamp(0.8, 2.0);
    final left =
        widget.canvasOffset.dx +
        widget.item.x * widget.canvasScale -
        width / 2 -
        controlPad;
    final top =
        widget.canvasOffset.dy +
        widget.item.y * widget.canvasScale -
        height / 2 -
        controlPad;

    return Positioned(
      left: left,
      top: top,
      width: width + controlPad * 2,
      height: height + controlPad * 2,
      child: AnimatedScale(
        scale: _motionScale,
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutBack,
        child: Transform.rotate(
          angle: widget.item.rotation * math.pi / 180,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: controlPad,
                top: controlPad,
                width: width,
                height: height,
                child: _AlphaHitTest(
                  enabled: !widget.selected,
                  mask: _alphaMask,
                  flipX: widget.item.flipX,
                  flipY: widget.item.flipY,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onSelect,
                    onPanStart: (details) {
                      StickerlySfx.play(StickerlyAssets.soundPop);
                      _playGrabPop();
                      widget.onSelect();
                      widget.onGrabStart();
                      _gestureStart = widget.item;
                      _latest = widget.item;
                      _focalStart = details.globalPosition;
                      _latestGlobalPosition = details.globalPosition;
                    },
                    onPanUpdate: (details) {
                      _latestGlobalPosition = details.globalPosition;
                      final delta =
                          (details.globalPosition - _focalStart) /
                          (widget.canvasScale *
                              math.max(0.01, widget.viewportScale()));
                      _latest = _gestureStart.copyWith(
                        x: _gestureStart.x + delta.dx,
                        y: _gestureStart.y + delta.dy,
                      );
                      widget.onChanged(_latest, commit: false);
                    },
                    onPanEnd: (_) {
                      StickerlySfx.play(StickerlyAssets.soundPunch);
                      _playDropPop();
                      widget.onChanged(_latest, commit: true);
                      widget.onGrabEnd(_latestGlobalPosition);
                    },
                    onPanCancel: () {
                      setState(() => _motionScale = 1);
                      widget.onChanged(_latest, commit: true);
                      widget.onGrabEnd(_latestGlobalPosition);
                    },
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _StickerArtwork(
                            item: widget.item,
                            assetPath: widget.assetPath,
                          ),
                        ),
                        if (widget.selected)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: StickerlyColors.pink,
                                    width: selectionWidth,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (widget.selected)
                Positioned(
                  left: controlPad + width - handleHitSize / 2,
                  top: controlPad - handleHitSize / 2,
                  child: _StickerCornerHandle(
                    visualSize: handleSize,
                    hitSize: handleHitSize,
                    onPanStart: (details) {
                      StickerlySfx.play(StickerlyAssets.soundPop);
                      _playGrabPop();
                      widget.onSelect();
                      widget.onGrabStart();
                      _gestureStart = widget.item;
                      _latest = widget.item;
                      final box = context.findRenderObject() as RenderBox?;
                      _handleCenter = box == null
                          ? details.globalPosition
                          : box.localToGlobal(
                              Offset(
                                controlPad + width / 2,
                                controlPad + height / 2,
                              ),
                            );
                      _handleStartVector =
                          details.globalPosition - _handleCenter;
                      _latestGlobalPosition = details.globalPosition;
                    },
                    onPanUpdate: (details) {
                      _latestGlobalPosition = details.globalPosition;
                      final current = details.globalPosition - _handleCenter;
                      final startDistance = math.max(
                        1.0,
                        _handleStartVector.distance,
                      );
                      final scaleFactor = current.distance / startDistance;
                      final startAngle = math.atan2(
                        _handleStartVector.dy,
                        _handleStartVector.dx,
                      );
                      final currentAngle = math.atan2(current.dy, current.dx);
                      _latest = _gestureStart.copyWith(
                        scale: (_gestureStart.scale * scaleFactor).clamp(
                          0.2,
                          5,
                        ),
                        rotation:
                            _gestureStart.rotation +
                            (currentAngle - startAngle) * 180 / math.pi,
                      );
                      widget.onChanged(_latest, commit: false);
                    },
                    onPanEnd: () {
                      StickerlySfx.play(StickerlyAssets.soundPunch);
                      setState(() => _motionScale = 1);
                      widget.onChanged(_latest, commit: true);
                      widget.onGrabEnd(_latestGlobalPosition);
                    },
                  ),
                ),
              if (widget.selected)
                Positioned(
                  left: controlPad - handleHitSize / 2,
                  top: controlPad + height / 2 - handleHitSize / 2,
                  child: _StickerFlipButton(
                    visualSize: handleSize,
                    hitSize: handleHitSize,
                    asset: StickerlyAssets.flipHorizontal,
                    onPressed: widget.onFlipHorizontal,
                  ),
                ),
              if (widget.selected)
                Positioned(
                  left: controlPad + width / 2 - handleHitSize / 2,
                  top: controlPad + height - handleHitSize / 2,
                  child: _StickerFlipButton(
                    visualSize: handleSize,
                    hitSize: handleHitSize,
                    asset: StickerlyAssets.flipVertical,
                    onPressed: widget.onFlipVertical,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlphaMask {
  const _AlphaMask({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;
  final Uint8List rgba;

  bool contains(Offset position, Size targetSize, bool flipX, bool flipY) {
    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(width.toDouble(), height.toDouble()),
      targetSize,
    );
    final rect = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & targetSize,
    );
    const logicalHitPadding = 10.0;
    if (!rect.inflate(logicalHitPadding).contains(position)) return false;
    var x = ((position.dx - rect.left) / rect.width * width).floor();
    var y = ((position.dy - rect.top) / rect.height * height).floor();
    x = x.clamp(0, width - 1);
    y = y.clamp(0, height - 1);
    if (flipX) x = width - 1 - x;
    if (flipY) y = height - 1 - y;
    final sampleRadius = math.max(
      1,
      (logicalHitPadding / math.max(1, rect.width) * width).ceil(),
    );
    for (var dy = -sampleRadius; dy <= sampleRadius; dy++) {
      for (var dx = -sampleRadius; dx <= sampleRadius; dx++) {
        final sampleX = (x + dx).clamp(0, width - 1);
        final sampleY = (y + dy).clamp(0, height - 1);
        if (rgba[(sampleY * width + sampleX) * 4 + 3] > 20) {
          return true;
        }
      }
    }
    return false;
  }
}

class _AlphaHitTest extends SingleChildRenderObjectWidget {
  const _AlphaHitTest({
    required this.enabled,
    required this.mask,
    required this.flipX,
    required this.flipY,
    required super.child,
  });

  final bool enabled;
  final _AlphaMask? mask;
  final bool flipX;
  final bool flipY;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAlphaHitTest(enabled, mask, flipX, flipY);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderAlphaHitTest renderObject,
  ) {
    renderObject
      ..enabled = enabled
      ..mask = mask
      ..flipX = flipX
      ..flipY = flipY;
  }
}

class _RenderAlphaHitTest extends RenderProxyBox {
  _RenderAlphaHitTest(this._enabled, this._mask, this._flipX, this._flipY);

  bool _enabled;
  _AlphaMask? _mask;
  bool _flipX;
  bool _flipY;

  set enabled(bool value) => _enabled = value;
  set mask(_AlphaMask? value) => _mask = value;
  set flipX(bool value) => _flipX = value;
  set flipY(bool value) => _flipY = value;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    final mask = _mask;
    if (_enabled &&
        mask != null &&
        !mask.contains(position, size, _flipX, _flipY)) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}

class _StickerCornerHandle extends StatelessWidget {
  const _StickerCornerHandle({
    required this.visualSize,
    required this.hitSize,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final double visualSize;
  final double hitSize;
  final ValueChanged<DragStartDetails> onPanStart;
  final ValueChanged<DragUpdateDetails> onPanUpdate;
  final VoidCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      onPanEnd: (_) => onPanEnd(),
      onPanCancel: onPanEnd,
      child: SizedBox.square(
        dimension: hitSize,
        child: Center(
          child: Container(
            width: visualSize,
            height: visualSize,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: StickerlyColors.pink,
                width: (visualSize * 0.06).clamp(1.0, 2.0),
              ),
              boxShadow: [
                BoxShadow(
                  color: StickerlyColors.ink.withValues(alpha: 0.18),
                  blurRadius: visualSize * 0.3,
                  offset: Offset(0, visualSize * 0.12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StickerFlipButton extends StatelessWidget {
  const _StickerFlipButton({
    required this.visualSize,
    required this.hitSize,
    required this.asset,
    required this.onPressed,
  });

  final double visualSize;
  final double hitSize;
  final String asset;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: SizedBox(
        width: hitSize,
        height: hitSize,
        child: Center(
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Material(
              color: Colors.white,
              elevation: 4,
              shadowColor: StickerlyColors.ink.withValues(alpha: 0.18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(3),
                side: BorderSide(
                  color: StickerlyColors.pink,
                  width: (visualSize * 0.06).clamp(1.0, 2.0),
                ),
              ),
              child: IgnorePointer(
                child: SizedBox(
                  width: visualSize * 0.82,
                  height: visualSize * 0.82,
                  child: Transform.rotate(
                    angle: -math.pi / 4,
                    child: Padding(
                      padding: EdgeInsets.all(visualSize * 0.18),
                      child: Image.asset(asset, fit: BoxFit.contain),
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

class _StickerDeleteZone extends StatelessWidget {
  const _StickerDeleteZone({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    if (!active) return const SizedBox.shrink();
    return Material(
      elevation: 10,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(48),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFEEF3),
          borderRadius: BorderRadius.circular(48),
          border: Border.all(color: StickerlyColors.pink, width: 2),
          boxShadow: [
            BoxShadow(
              color: StickerlyColors.pink.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform.translate(
              offset: const Offset(0, 54),
              child: Image.asset(StickerlyAssets.trash, width: 54, height: 54),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextNode extends StatefulWidget {
  const _TextNode({
    required this.item,
    required this.canvasScale,
    required this.canvasOffset,
    required this.selected,
    required this.onSelect,
    required this.onGrabStart,
    required this.onGrabEnd,
    required this.onChanged,
    super.key,
  });

  final TextItem item;
  final double canvasScale;
  final Offset canvasOffset;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onGrabStart;
  final ValueChanged<Offset> onGrabEnd;
  final void Function(TextItem item, {required bool commit}) onChanged;

  @override
  State<_TextNode> createState() => _TextNodeState();
}

class _TextNodeState extends State<_TextNode> {
  late TextItem _gestureStart;
  late TextItem _latest;
  Offset _focalStart = Offset.zero;
  Offset _latestGlobalPosition = Offset.zero;
  Offset _handleCenter = Offset.zero;
  Offset _handleStartVector = Offset.zero;
  var _showPalette = false;
  var _motionScale = 1.0;

  @override
  void initState() {
    super.initState();
    _latest = widget.item;
  }

  @override
  void didUpdateWidget(covariant _TextNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    _latest = widget.item;
  }

  Future<void> _editText() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TextEditSheet(initialValue: widget.item.text),
    );
    if (!mounted) return;
    if (value != null && value.trim().isNotEmpty) {
      widget.onChanged(widget.item.copyWith(text: value.trim()), commit: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = 360 * widget.canvasScale * widget.item.scale;
    final height = 150 * widget.canvasScale * widget.item.scale;
    final handleSize = (height * 0.36).clamp(36.0, 64.0);
    final hitSize = handleSize;
    final controlPad = widget.selected ? hitSize : 0.0;
    return Positioned(
      left:
          widget.canvasOffset.dx +
          widget.item.x * widget.canvasScale -
          width / 2 -
          controlPad,
      top:
          widget.canvasOffset.dy +
          widget.item.y * widget.canvasScale -
          height / 2 -
          controlPad,
      width: width + controlPad * 2,
      height: height + controlPad * 2,
      child: AnimatedScale(
        scale: _motionScale,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutBack,
        child: Transform.rotate(
          angle: widget.item.rotation * math.pi / 180,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: controlPad,
                top: controlPad,
                width: width,
                height: height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onSelect,
                  onPanStart: (details) {
                    StickerlySfx.play(StickerlyAssets.soundPop);
                    setState(() => _motionScale = 1.14);
                    widget.onSelect();
                    widget.onGrabStart();
                    _gestureStart = widget.item;
                    _latest = widget.item;
                    _focalStart = details.globalPosition;
                    _latestGlobalPosition = details.globalPosition;
                  },
                  onPanUpdate: (details) {
                    _latestGlobalPosition = details.globalPosition;
                    final delta =
                        (details.globalPosition - _focalStart) /
                        widget.canvasScale;
                    _latest = _gestureStart.copyWith(
                      x: _gestureStart.x + delta.dx,
                      y: _gestureStart.y + delta.dy,
                    );
                    widget.onChanged(_latest, commit: false);
                  },
                  onPanEnd: (_) {
                    StickerlySfx.play(StickerlyAssets.soundPunch);
                    setState(() => _motionScale = 1);
                    widget.onChanged(_latest, commit: true);
                    widget.onGrabEnd(_latestGlobalPosition);
                  },
                  child: LayoutBuilder(
                    builder: (context, constraints) => Padding(
                      padding: EdgeInsets.all(
                        math.max(4, constraints.maxHeight * 0.08),
                      ),
                      child: _AutoFitText(
                        text: widget.item.text,
                        fontFamily: widget.item.fontFamily,
                        color: _effectColor(widget.item.color),
                        maxFontSize: constraints.maxHeight * 0.58,
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.selected)
                Positioned(
                  left: controlPad,
                  top: controlPad,
                  width: width,
                  height: height,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: StickerlyColors.purple,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.selected)
                Positioned(
                  left: controlPad,
                  top: controlPad,
                  width: width,
                  height: height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: widget.onSelect,
                    onPanStart: (details) {
                      StickerlySfx.play(StickerlyAssets.soundPop);
                      setState(() => _motionScale = 1.14);
                      widget.onSelect();
                      widget.onGrabStart();
                      _gestureStart = widget.item;
                      _latest = widget.item;
                      _focalStart = details.globalPosition;
                      _latestGlobalPosition = details.globalPosition;
                    },
                    onPanUpdate: (details) {
                      _latestGlobalPosition = details.globalPosition;
                      final delta =
                          (details.globalPosition - _focalStart) /
                          widget.canvasScale;
                      _latest = _gestureStart.copyWith(
                        x: _gestureStart.x + delta.dx,
                        y: _gestureStart.y + delta.dy,
                      );
                      widget.onChanged(_latest, commit: false);
                    },
                    onPanEnd: (_) {
                      StickerlySfx.play(StickerlyAssets.soundPunch);
                      setState(() => _motionScale = 1);
                      widget.onChanged(_latest, commit: true);
                      widget.onGrabEnd(_latestGlobalPosition);
                    },
                  ),
                ),
              if (widget.selected)
                Positioned(
                  left: controlPad + width - hitSize / 2,
                  top: controlPad - hitSize / 2,
                  child: _StickerCornerHandle(
                    visualSize: handleSize,
                    hitSize: hitSize,
                    onPanStart: (details) {
                      _gestureStart = widget.item;
                      _latest = widget.item;
                      final box = context.findRenderObject() as RenderBox?;
                      _handleCenter = box == null
                          ? details.globalPosition
                          : box.localToGlobal(box.size.center(Offset.zero));
                      _handleStartVector =
                          details.globalPosition - _handleCenter;
                    },
                    onPanUpdate: (details) {
                      final current = details.globalPosition - _handleCenter;
                      final startDistance = math.max(
                        1.0,
                        _handleStartVector.distance,
                      );
                      final scaleFactor = current.distance / startDistance;
                      final startAngle = math.atan2(
                        _handleStartVector.dy,
                        _handleStartVector.dx,
                      );
                      final currentAngle = math.atan2(current.dy, current.dx);
                      _latest = _gestureStart.copyWith(
                        scale: (_gestureStart.scale * scaleFactor).clamp(
                          0.2,
                          5,
                        ),
                        rotation:
                            _gestureStart.rotation +
                            (currentAngle - startAngle) * 180 / math.pi,
                      );
                      widget.onChanged(_latest, commit: false);
                    },
                    onPanEnd: () => widget.onChanged(_latest, commit: true),
                  ),
                ),
              if (widget.selected)
                Positioned(
                  left: controlPad - hitSize / 2,
                  top: controlPad + height - hitSize / 2,
                  child: _TextSideButton(
                    visualSize: handleSize,
                    hitSize: hitSize,
                    color: _effectColor(widget.item.color),
                    icon: Icons.palette_rounded,
                    onPressed: () =>
                        setState(() => _showPalette = !_showPalette),
                  ),
                ),
              if (widget.selected)
                Positioned(
                  left: controlPad + width - hitSize / 2,
                  top: controlPad + height - hitSize / 2,
                  child: _TextSideButton(
                    visualSize: handleSize,
                    hitSize: hitSize,
                    icon: Icons.edit_rounded,
                    onPressed: _editText,
                  ),
                ),
              if (widget.selected && _showPalette)
                Positioned(
                  left: controlPad,
                  right: controlPad,
                  top: controlPad + height + 10,
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    child: _TextColorPalette(
                      selected: widget.item.color,
                      onSelected: (color) {
                        widget.onChanged(
                          widget.item.copyWith(color: color),
                          commit: true,
                        );
                      },
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

class _TextEditSheet extends StatefulWidget {
  const _TextEditSheet({required this.initialValue});

  final String initialValue;

  @override
  State<_TextEditSheet> createState() => _TextEditSheetState();
}

class _TextEditSheetState extends State<_TextEditSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 8,
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 80,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: '글씨를 입력하세요',
              counterText: '',
              border: InputBorder.none,
            ),
            onSubmitted: _submit,
          ),
        ),
      ),
    );
  }
}

class _AutoFitText extends StatelessWidget {
  const _AutoFitText({
    required this.text,
    required this.fontFamily,
    required this.color,
    required this.maxFontSize,
  });

  final String text;
  final String fontFamily;
  final Color color;
  final double maxFontSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var low = 1.0;
        var high = math.max(1.0, maxFontSize);
        for (var i = 0; i < 12; i++) {
          final candidate = (low + high) / 2;
          final painter = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: candidate,
                fontWeight: FontWeight.w700,
              ),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: constraints.maxWidth);
          if (!painter.didExceedMaxLines &&
              painter.width <= constraints.maxWidth &&
              painter.height <= constraints.maxHeight) {
            low = candidate;
          } else {
            high = candidate;
          }
        }
        return Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: TextStyle(
              fontFamily: fontFamily,
              color: color,
              fontSize: low,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }
}

class _TextSideButton extends StatelessWidget {
  const _TextSideButton({
    required this.visualSize,
    required this.hitSize,
    required this.icon,
    required this.onPressed,
    this.color = Colors.white,
  });

  final double visualSize;
  final double hitSize;
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox.square(
          dimension: hitSize,
          child: Center(
            child: IgnorePointer(
              child: Material(
                color: color,
                elevation: 4,
                shape: CircleBorder(
                  side: BorderSide(color: StickerlyColors.pink, width: 1.5),
                ),
                child: SizedBox.square(
                  dimension: visualSize,
                  child: Icon(
                    icon,
                    size: visualSize * 0.5,
                    color: color.computeLuminance() < 0.45
                        ? Colors.white
                        : StickerlyColors.ink,
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

class _TextColorPalette extends StatelessWidget {
  const _TextColorPalette({required this.selected, required this.onSelected});

  static const colors = [
    'hsl(340 82% 62%)',
    'hsl(205 100% 55%)',
    'hsl(156 60% 42%)',
    'hsl(45 100% 52%)',
    'hsl(270 70% 58%)',
    'hsl(0 0% 20%)',
  ];

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 6,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final color in colors)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onSelected(color),
                child: Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _effectColor(color),
                    border: Border.all(
                      color: selected == color
                          ? StickerlyColors.ink
                          : Colors.white,
                      width: selected == color ? 3 : 1,
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

class _StickerArtwork extends StatelessWidget {
  const _StickerArtwork({required this.item, required this.assetPath});

  final StickerItem item;
  final String assetPath;

  @override
  Widget build(BuildContext context) {
    if (assetPath.isEmpty) return const SizedBox.shrink();
    final effects = item.effects;
    final blur = effects.blur.enabled ? effects.blur.intensity * 10 : 0.0;
    final brightness = effects.brightness.enabled
        ? effects.brightness.intensity
        : 0.0;
    final glow = effects.outglow;
    final shadow = effects.floorShadow;

    Widget artwork = AssetFileImage(path: assetPath, fit: BoxFit.contain);
    if (brightness.abs() > 0.001) {
      final offset = brightness * 0.75;
      artwork = ColorFiltered(
        colorFilter: ColorFilter.matrix([
          1,
          0,
          0,
          0,
          offset * 255,
          0,
          1,
          0,
          0,
          offset * 255,
          0,
          0,
          1,
          0,
          offset * 255,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: artwork,
      );
    }
    if (blur > 0) {
      artwork = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: artwork,
      );
    }

    artwork = Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(
        item.flipX ? -1 : 1,
        item.flipY ? -1 : 1,
        1,
      ),
      child: artwork,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (shadow.enabled)
          Positioned(
            left: 18 + shadow.x,
            right: 18 - shadow.x,
            bottom: -4 - shadow.y,
            height: 24 * shadow.scale,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: 3 + shadow.blur * 12,
                sigmaY: 3 + shadow.blur * 12,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: StickerlyColors.ink.withValues(
                    alpha: 0.12 + shadow.intensity * 0.38,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        if (glow.enabled)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: 5 + glow.intensity * 14,
                sigmaY: 5 + glow.intensity * 14,
              ),
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(
                  _effectColor(
                    glow.color,
                  ).withValues(alpha: 0.35 + glow.intensity * 0.4),
                  BlendMode.srcIn,
                ),
                child: Transform.rotate(
                  angle: 0,
                  child: AssetFileImage(path: assetPath, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        Positioned.fill(child: artwork),
      ],
    );
  }
}

Color _effectColor(String value) {
  final match = RegExp(
    r'hsl\(\s*([\d.]+)\s+([\d.]+)%\s+([\d.]+)%\s*\)',
  ).firstMatch(value);
  if (match == null) return const Color(0xFF74C7FF);
  return HSLColor.fromAHSL(
    1,
    double.parse(match.group(1)!),
    double.parse(match.group(2)!) / 100,
    double.parse(match.group(3)!) / 100,
  ).toColor();
}

class _EditorTray extends StatefulWidget {
  const _EditorTray({
    required this.selected,
    required this.catalog,
    required this.horizontal,
    required this.extent,
    required this.minExtent,
    required this.maxExtent,
    required this.onSelected,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
    required this.onOpen,
    required this.onSetBackground,
    required this.selectedBackgroundId,
    required this.onDownloadPack,
    required this.stickerPreviewSize,
  });

  final _TrayTab selected;
  final AssetCatalog catalog;
  final bool horizontal;
  final double extent;
  final double minExtent;
  final double maxExtent;
  final ValueChanged<_TrayTab> onSelected;
  final ValueChanged<double> onResizeStart;
  final ValueChanged<double> onResizeUpdate;
  final VoidCallback onResizeEnd;
  final VoidCallback onOpen;
  final ValueChanged<BackgroundAsset> onSetBackground;
  final String? selectedBackgroundId;
  final Future<void> Function(StickerPack) onDownloadPack;
  final double Function() stickerPreviewSize;

  @override
  State<_EditorTray> createState() => _EditorTrayState();
}

class _EditorTrayState extends State<_EditorTray> {
  StickerPack? _activePack;
  var _packQuery = '';
  var _backgroundQuery = '';

  @override
  void didUpdateWidget(covariant _EditorTray oldWidget) {
    super.didUpdateWidget(oldWidget);
    final activePack = _activePack;
    if (activePack != null) {
      _activePack = widget.catalog.packs
          .where((pack) => pack.id == activePack.id)
          .firstOrNull;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.horizontal
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final tab in _TrayTab.values) _tabButton(tab)],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [for (final tab in _TrayTab.values) _tabButton(tab)],
          );
    final content = ColoredBox(
      color: const Color(0xFFFFF1E3),
      child: Padding(
        padding: EdgeInsets.all(widget.horizontal ? 8 : 6),
        child: switch (widget.selected) {
          _TrayTab.stickers => _StickerBrowser(
            packs: widget.catalog.packs,
            horizontal: widget.horizontal,
            activePack: _activePack,
            query: _packQuery,
            onQueryChanged: (value) => setState(() => _packQuery = value),
            onOpenPack: (pack) async {
              StickerlySfx.play(StickerlyAssets.soundButton);
              final needsDownload =
                  pack.stickers.any((asset) => !asset.isUsable) ||
                  widget.catalog.backgrounds.any(
                    (background) =>
                        pack.backgroundIds.contains(background.id) &&
                        !background.isUsable,
                  );
              if (needsDownload) await widget.onDownloadPack(pack);
              if (!mounted) return;
              final updated = widget.catalog.packs
                  .where((item) => item.id == pack.id)
                  .firstOrNull;
              setState(() => _activePack = updated ?? pack);
            },
            onClosePack: () {
              StickerlySfx.play(StickerlyAssets.soundClick);
              setState(() => _activePack = null);
            },
            stickerPreviewSize: widget.stickerPreviewSize,
          ),
          _TrayTab.text => _TextStyleList(horizontal: widget.horizontal),
          _TrayTab.background => _BackgroundList(
            packs: widget.catalog.packs,
            backgrounds: widget.catalog.backgrounds,
            horizontal: widget.horizontal,
            query: _backgroundQuery,
            onQueryChanged: (value) => setState(() => _backgroundQuery = value),
            selectedId: widget.selectedBackgroundId,
            onSelected: widget.onSetBackground,
            onDownloadPack: widget.onDownloadPack,
          ),
        },
      ),
    );
    final collapsed = widget.extent < 150;

    if (widget.horizontal) {
      return Column(
        children: [
          SizedBox(
            height: 38,
            child: Stack(
              children: [
                Align(alignment: Alignment.topLeft, child: tabs),
                Align(
                  alignment: Alignment.topRight,
                  child: _TrayHandle(
                    horizontal: true,
                    onDragStart: (position) =>
                        widget.onResizeStart(position.dy),
                    onDragUpdate: (position) =>
                        widget.onResizeUpdate(position.dy),
                    onDragEnd: widget.onResizeEnd,
                    onTap: widget.onOpen,
                  ),
                ),
              ],
            ),
          ),
          if (!collapsed) Expanded(child: content),
        ],
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Align(alignment: Alignment.topLeft, child: tabs),
              ),
              const Spacer(),
              _TrayHandle(
                horizontal: false,
                onDragStart: (position) => widget.onResizeStart(position.dx),
                onDragUpdate: (position) => widget.onResizeUpdate(position.dx),
                onDragEnd: widget.onResizeEnd,
                onTap: widget.onOpen,
              ),
            ],
          ),
        ),
        if (!collapsed) Expanded(child: content),
      ],
    );
  }

  Widget _tabButton(_TrayTab tab) {
    final selected = widget.selected == tab;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: SizedBox(
        width: widget.horizontal ? 58 : 58,
        height: widget.horizontal ? 38 : 46,
        child: TextButton(
          onPressed: () {
            widget.onOpen();
            widget.onSelected(tab);
            if (tab != _TrayTab.stickers) {
              setState(() => _activePack = null);
            }
          },
          style: TextButton.styleFrom(
            backgroundColor: selected
                ? null
                : switch (tab) {
                    _TrayTab.stickers => const Color(0xFFFFE7DB),
                    _TrayTab.text => const Color(0xFFF0E8F7),
                    _TrayTab.background => const Color(0xFFE7EFE7),
                  },
            foregroundColor: selected ? Colors.white : StickerlyColors.ink,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: widget.horizontal
                  ? const BorderRadius.vertical(top: Radius.circular(12))
                  : const BorderRadius.horizontal(left: Radius.circular(14)),
              side: BorderSide(
                color: selected ? Colors.transparent : StickerlyColors.line,
              ),
            ),
          ),
          child: Ink(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: selected
                  ? const LinearGradient(
                      colors: [StickerlyColors.pink, StickerlyColors.purple],
                    )
                  : null,
              borderRadius: widget.horizontal
                  ? const BorderRadius.vertical(top: Radius.circular(12))
                  : const BorderRadius.horizontal(left: Radius.circular(14)),
            ),
            child: Center(
              child: Text(
                switch (tab) {
                  _TrayTab.stickers => '스티커',
                  _TrayTab.text => '글씨',
                  _TrayTab.background => '배경',
                },
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrayHandle extends StatelessWidget {
  const _TrayHandle({
    required this.horizontal,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onTap,
  });

  final bool horizontal;
  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onTap: onTap,
      onVerticalDragStart: horizontal
          ? (details) => onDragStart(details.globalPosition)
          : null,
      onVerticalDragUpdate: horizontal
          ? (details) => onDragUpdate(details.globalPosition)
          : null,
      onVerticalDragEnd: horizontal ? (_) => onDragEnd() : null,
      onHorizontalDragStart: horizontal
          ? null
          : (details) => onDragStart(details.globalPosition),
      onHorizontalDragUpdate: horizontal
          ? null
          : (details) => onDragUpdate(details.globalPosition),
      onHorizontalDragEnd: horizontal ? null : (_) => onDragEnd(),
      child: SizedBox(
        width: horizontal ? 116 : 58,
        height: horizontal ? 38 : 92,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Center(
            child: Container(
              width: horizontal ? 48 : 4,
              height: horizontal ? 4 : 48,
              decoration: BoxDecoration(
                color: StickerlyColors.ink.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StickerBrowser extends StatelessWidget {
  const _StickerBrowser({
    required this.packs,
    required this.horizontal,
    required this.activePack,
    required this.query,
    required this.onQueryChanged,
    required this.onOpenPack,
    required this.onClosePack,
    required this.stickerPreviewSize,
  });

  final List<StickerPack> packs;
  final bool horizontal;
  final StickerPack? activePack;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final Future<void> Function(StickerPack) onOpenPack;
  final VoidCallback onClosePack;
  final double Function() stickerPreviewSize;

  @override
  Widget build(BuildContext context) {
    final pack = activePack;
    if (pack != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TrayHeaderButton(label: pack.name, onPressed: onClosePack),
          Expanded(
            child: _AlwaysVisibleScrollbar(
              builder: (controller) => LayoutBuilder(
                builder: (context, constraints) => GridView.builder(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(4, 2, 12, 14),
                  gridDelegate: _FixedTrayGridDelegate(
                    forceCrossAxisCount: horizontal ? 4 : null,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: pack.stickers.length,
                  itemBuilder: (context, index) {
                    final asset = pack.stickers[index];
                    return _DraggableStickerCard(
                      pack: pack,
                      asset: asset,
                      previewSize: stickerPreviewSize,
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      );
    }

    final filtered = packs
        .where(
          (pack) =>
              query.isEmpty ||
              pack.name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return Column(
      children: [
        _TraySearchField(hint: '스티커팩 검색', onChanged: onQueryChanged),
        Expanded(
          child: filtered.isEmpty
              ? const _TrayEmptyState(message: '보이는 스티커팩이 없어요')
              : _AlwaysVisibleScrollbar(
                  builder: (controller) => LayoutBuilder(
                    builder: (context, constraints) => GridView.builder(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(8, 4, 12, 28),
                      gridDelegate: _FixedTrayGridDelegate(
                        forceCrossAxisCount: horizontal ? 4 : null,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final pack = filtered[index];
                        return _StickerPackCard(
                          pack: pack,
                          onPressed: onOpenPack,
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _StickerPackCard extends StatefulWidget {
  const _StickerPackCard({required this.pack, required this.onPressed});

  final StickerPack pack;
  final Future<void> Function(StickerPack) onPressed;

  @override
  State<_StickerPackCard> createState() => _StickerPackCardState();
}

class _StickerPackCardState extends State<_StickerPackCard> {
  var _loading = false;

  @override
  Widget build(BuildContext context) {
    final pack = widget.pack;
    final needsDownload = pack.stickers.any((asset) => !asset.isUsable);
    final thumbnail = pack.thumbnail.isNotEmpty
        ? pack.thumbnail
        : (pack.stickers.firstOrNull?.assetPath ?? '');
    return Material(
      color: const Color(0xFFFFF7EE),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: const BorderSide(color: StickerlyColors.line, width: 2),
      ),
      child: InkWell(
        onTap: _loading
            ? null
            : () async {
                setState(() => _loading = true);
                try {
                  await widget.onPressed(pack);
                } finally {
                  if (mounted) setState(() => _loading = false);
                }
              },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(7, 7, 7, 24),
              child: AssetFileImage(path: thumbnail, fit: BoxFit.contain),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.only(bottom: 5),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF5F536D),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  pack.name,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (needsDownload && !_loading)
              const Positioned(
                right: 6,
                top: 6,
                child: Icon(Icons.download_rounded, size: 20),
              ),
            if (_loading)
              const ColoredBox(
                color: Color(0x88FFF8EE),
                child: Center(child: CircularProgressIndicator(strokeWidth: 3)),
              ),
          ],
        ),
      ),
    );
  }
}

class _AlwaysVisibleScrollbar extends StatefulWidget {
  const _AlwaysVisibleScrollbar({required this.builder});

  final Widget Function(ScrollController controller) builder;

  @override
  State<_AlwaysVisibleScrollbar> createState() =>
      _AlwaysVisibleScrollbarState();
}

class _AlwaysVisibleScrollbarState extends State<_AlwaysVisibleScrollbar> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      scrollbarOrientation: ScrollbarOrientation.right,
      child: widget.builder(_controller),
    );
  }
}

class _FixedTrayGridDelegate extends SliverGridDelegate {
  const _FixedTrayGridDelegate({
    this.crossAxisSpacing = 8,
    this.mainAxisSpacing = 8,
    this.forceCrossAxisCount,
  });

  static const itemExtent = 96.0;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final int? forceCrossAxisCount;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final count =
        forceCrossAxisCount ??
        math.max(
          1,
          ((constraints.crossAxisExtent + crossAxisSpacing) /
                  (itemExtent + crossAxisSpacing))
              .floor(),
        );
    final childCrossAxisExtent =
        (constraints.crossAxisExtent - crossAxisSpacing * (count - 1)) / count;
    final childMainAxisExtent = forceCrossAxisCount == null
        ? itemExtent
        : childCrossAxisExtent;
    return SliverGridRegularTileLayout(
      crossAxisCount: count,
      mainAxisStride: childMainAxisExtent + mainAxisSpacing,
      crossAxisStride: childCrossAxisExtent + crossAxisSpacing,
      childMainAxisExtent: childMainAxisExtent,
      childCrossAxisExtent: childCrossAxisExtent,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(covariant _FixedTrayGridDelegate oldDelegate) {
    return oldDelegate.crossAxisSpacing != crossAxisSpacing ||
        oldDelegate.mainAxisSpacing != mainAxisSpacing ||
        oldDelegate.forceCrossAxisCount != forceCrossAxisCount;
  }
}

class _DraggableStickerCard extends StatefulWidget {
  const _DraggableStickerCard({
    required this.pack,
    required this.asset,
    required this.previewSize,
  });

  final StickerPack pack;
  final StickerAsset asset;
  final double Function() previewSize;

  @override
  State<_DraggableStickerCard> createState() => _DraggableStickerCardState();
}

class _DraggableStickerCardState extends State<_DraggableStickerCard> {
  var _cardScale = 1.0;

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    final previewSize = widget.previewSize();
    final card = AnimatedScale(
      scale: _cardScale,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: AssetFileImage(path: asset.assetPath),
        ),
      ),
    );
    if (!asset.isUsable) {
      return Card(
        child: Center(
          child: IconButton.filledTonal(
            tooltip: '다운로드',
            onPressed: null,
            icon: const Icon(Icons.cloud_download_outlined),
          ),
        ),
      );
    }
    return LongPressDraggable<_StickerDragPayload>(
      data: _StickerDragPayload(
        pack: widget.pack,
        asset: asset,
        previewSize: previewSize,
      ),
      delay: const Duration(milliseconds: 90),
      dragAnchorStrategy: (_, _, _) =>
          Offset(previewSize * 0.78, previewSize * 0.78),
      onDragStarted: () {
        StickerlySfx.play(StickerlyAssets.soundPop);
        setState(() => _cardScale = 1.18);
      },
      onDragEnd: (_) => setState(() => _cardScale = 1),
      onDraggableCanceled: (_, _) => setState(() => _cardScale = 1),
      feedback: _DragStickerFeedback(
        assetPath: asset.assetPath,
        size: previewSize,
      ),
      maxSimultaneousDrags: 1,
      childWhenDragging: Opacity(opacity: 0.42, child: card),
      child: card,
    );
  }
}

class _DragStickerFeedback extends StatefulWidget {
  const _DragStickerFeedback({required this.assetPath, required this.size});

  final String assetPath;
  final double size;

  @override
  State<_DragStickerFeedback> createState() => _DragStickerFeedbackState();
}

class _DragStickerFeedbackState extends State<_DragStickerFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wiggleController;

  @override
  void initState() {
    super.initState();
    _wiggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )..repeat();
  }

  @override
  void dispose() {
    _wiggleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final popScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.52,
          end: 1.16,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 72,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.16,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 28,
      ),
    ]);
    return Material(
      color: Colors.transparent,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 520),
        builder: (context, progress, child) {
          return AnimatedBuilder(
            animation: _wiggleController,
            builder: (context, child) {
              final wave = math.sin(_wiggleController.value * math.pi * 2);
              final settle = Curves.easeOutCubic.transform(progress);
              final wiggleScale = 1 + wave.abs() * 0.045 * settle;
              final wiggleAngle = wave * 0.075 * settle;
              return Transform.rotate(
                angle: wiggleAngle,
                child: Transform.scale(
                  scale: popScale.transform(progress) * wiggleScale,
                  child: child,
                ),
              );
            },
            child: child,
          );
        },
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            children: [
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(size * 0.07, size * 0.1),
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: size * 0.085,
                      sigmaY: size * 0.085,
                    ),
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        Colors.black.withValues(alpha: 0.48),
                        BlendMode.srcIn,
                      ),
                      child: AssetFileImage(
                        path: widget.assetPath,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: AssetFileImage(
                  path: widget.assetPath,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrayEmptyState extends StatelessWidget {
  const _TrayEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF8B8194),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _TextStyleList extends StatelessWidget {
  const _TextStyleList({required this.horizontal});

  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    const styles = [('Jua', '말랑'), ('Gaegu', '꼬물'), ('Dongle', '동글')];
    return _AlwaysVisibleScrollbar(
      builder: (controller) => LayoutBuilder(
        builder: (context, constraints) => GridView.builder(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(8, 4, 12, 28),
          gridDelegate: _FixedTrayGridDelegate(
            forceCrossAxisCount: horizontal ? 4 : null,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: styles.length,
          itemBuilder: (context, index) {
            final style = styles[index];
            final card = Card(
              child: Center(
                child: Text(
                  style.$2,
                  style: TextStyle(
                    fontFamily: style.$1,
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
            return LongPressDraggable<Object>(
              data: _TextDragPayload(fontFamily: style.$1),
              delay: const Duration(milliseconds: 90),
              onDragStarted: () => StickerlySfx.play(StickerlyAssets.soundPop),
              feedback: Material(
                color: Colors.transparent,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.55, end: 1),
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.elasticOut,
                  builder: (_, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Container(
                    width: 180,
                    height: 75,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 18,
                          offset: Offset(8, 12),
                        ),
                      ],
                    ),
                    child: Text(
                      style.$2,
                      style: TextStyle(
                        fontFamily: style.$1,
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.42, child: card),
              child: card,
            );
          },
        ),
      ),
    );
  }
}

class _TraySearchField extends StatelessWidget {
  const _TraySearchField({required this.hint, required this.onChanged});

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: StickerlyColors.line, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: StickerlyColors.ink.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search_rounded, size: 19),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}

class _TrayHeaderButton extends StatelessWidget {
  const _TrayHeaderButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: StickerlyColors.line, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: StickerlyColors.ink.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: StickerlyColors.pink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        icon: const BackChevronGraphic(width: 20, height: 20),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ),
    );
  }
}

class _PackDownloadButton extends StatefulWidget {
  const _PackDownloadButton({required this.pack, required this.onDownload});

  final StickerPack pack;
  final Future<void> Function(StickerPack) onDownload;

  @override
  State<_PackDownloadButton> createState() => _PackDownloadButtonState();
}

class _PackDownloadButtonState extends State<_PackDownloadButton> {
  var _downloading = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 5),
      child: FilledButton.tonalIcon(
        onPressed: _downloading
            ? null
            : () async {
                setState(() => _downloading = true);
                try {
                  await widget.onDownload(widget.pack);
                } finally {
                  if (mounted) setState(() => _downloading = false);
                }
              },
        icon: _downloading
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.download_rounded, size: 18),
        label: const Text('팩 다운로드'),
      ),
    );
  }
}

class _BackgroundList extends StatelessWidget {
  const _BackgroundList({
    required this.packs,
    required this.backgrounds,
    required this.horizontal,
    required this.query,
    required this.onQueryChanged,
    required this.selectedId,
    required this.onSelected,
    required this.onDownloadPack,
  });

  final List<StickerPack> packs;
  final List<BackgroundAsset> backgrounds;
  final bool horizontal;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final String? selectedId;
  final ValueChanged<BackgroundAsset> onSelected;
  final Future<void> Function(StickerPack) onDownloadPack;

  @override
  Widget build(BuildContext context) {
    final filtered = backgrounds
        .where(
          (background) =>
              query.isEmpty ||
              background.name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return Column(
      children: [
        _TraySearchField(hint: '배경 검색', onChanged: onQueryChanged),
        Expanded(
          child: filtered.isEmpty
              ? const _TrayEmptyState(message: '보이는 배경이 없어요')
              : _AlwaysVisibleScrollbar(
                  builder: (controller) => LayoutBuilder(
                    builder: (context, constraints) => GridView.builder(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(8, 4, 12, 28),
                      gridDelegate: _FixedTrayGridDelegate(
                        forceCrossAxisCount: horizontal ? 4 : null,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final background = filtered[index];
                        final pack = packs
                            .where((item) => item.id == background.packId)
                            .firstOrNull;
                        final active = selectedId == background.id;
                        return Material(
                          color: const Color(0xFFFFF7EE),
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                            side: BorderSide(
                              color: active
                                  ? StickerlyColors.pink
                                  : StickerlyColors.line,
                              width: active ? 3 : 2,
                            ),
                          ),
                          child: InkWell(
                            onTap: background.isUsable
                                ? () => onSelected(background)
                                : null,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(7),
                                  child: AssetFileImage(
                                    path: background.assetPath,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                if (!background.isUsable)
                                  Center(
                                    child: IconButton.filledTonal(
                                      tooltip: '다운로드',
                                      onPressed: pack == null
                                          ? null
                                          : () =>
                                                unawaited(onDownloadPack(pack)),
                                      icon: const Icon(Icons.download_rounded),
                                    ),
                                  ),
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 5),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF5F536D),
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    child: Text(
                                      background.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
