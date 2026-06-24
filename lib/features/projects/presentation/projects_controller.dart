import 'package:flutter/foundation.dart';
import 'package:stickerly_v2/features/assets/domain/asset_catalog.dart';
import 'package:stickerly_v2/features/projects/domain/canvas_preset.dart';
import 'package:stickerly_v2/features/projects/domain/project_repository.dart';
import 'package:stickerly_v2/features/projects/domain/sticker_project.dart';
import 'package:uuid/uuid.dart';

class ProjectsController extends ChangeNotifier {
  ProjectsController(this._repository, this._assetCatalogLoader);

  final ProjectRepository _repository;
  final AssetCatalogLoader _assetCatalogLoader;

  List<StickerProject> projects = const [];
  AssetCatalog catalog = const AssetCatalog(packs: [], backgrounds: []);
  List<StickerPack> get packs => catalog.packs;
  bool isLoading = true;
  Object? error;
  final Set<String> downloadingAssetIds = {};

  Future<void> initialize() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _repository.list(),
        _assetCatalogLoader.load(),
      ]);
      projects = results[0] as List<StickerProject>;
      catalog = results[1] as AssetCatalog;
    } catch (exception) {
      error = exception;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<StickerProject> createProject({
    String? title,
    required CanvasPreset preset,
  }) async {
    final project = StickerProject.create(title: title, preset: preset);
    await _repository.save(project);
    projects = [project, ...projects];
    notifyListeners();
    return project;
  }

  Future<void> duplicateProject(StickerProject source) async {
    const uuid = Uuid();
    final now = DateTime.now();
    final copy = StickerProject(
      id: 'prj_${uuid.v4()}',
      title: '${source.title} 복사본',
      canvasWidth: source.canvasWidth,
      canvasHeight: source.canvasHeight,
      createdAt: now,
      updatedAt: now,
      thumbnailPath: source.thumbnailPath,
      background: source.background,
      stickerItems: source.stickerItems,
      textItems: source.textItems,
      lastTextColor: source.lastTextColor,
      textPalette: source.textPalette,
      lastGlowColor: source.lastGlowColor,
      glowPalette: source.glowPalette,
    );
    await _repository.save(copy);
    projects = [copy, ...projects];
    notifyListeners();
  }

  Future<void> renameProject(StickerProject source, String title) async {
    final normalized = title.trim();
    if (normalized.isEmpty || normalized == source.title) return;
    final updated = source.copyWith(
      title: normalized,
      updatedAt: DateTime.now(),
    );
    await _repository.save(updated);
    projects = [
      for (final project in projects)
        if (project.id == source.id) updated else project,
    ];
    notifyListeners();
  }

  Future<void> deleteProject(StickerProject project) async {
    await _repository.delete(project.id);
    projects = projects.where((item) => item.id != project.id).toList();
    notifyListeners();
  }

  Future<StickerAsset> downloadSticker(StickerAsset asset) async {
    final loader = _assetCatalogLoader;
    if (loader is! DownloadableAssetCatalogLoader) return asset;
    downloadingAssetIds.add(asset.id);
    notifyListeners();
    try {
      final downloaded = await loader.downloadSticker(asset);
      catalog = AssetCatalog(
        packs: [
          for (final pack in catalog.packs)
            StickerPack(
              id: pack.id,
              name: pack.name,
              folder: pack.folder,
              thumbnail: pack.thumbnail,
              stickers: [
                for (final item in pack.stickers)
                  if (item.id == asset.id) downloaded else item,
              ],
              backgroundIds: pack.backgroundIds,
            ),
        ],
        backgrounds: catalog.backgrounds,
      );
      return downloaded;
    } finally {
      downloadingAssetIds.remove(asset.id);
      notifyListeners();
    }
  }

  Future<BackgroundAsset> downloadBackground(BackgroundAsset asset) async {
    final loader = _assetCatalogLoader;
    if (loader is! DownloadableAssetCatalogLoader) return asset;
    downloadingAssetIds.add(asset.id);
    notifyListeners();
    try {
      final downloaded = await loader.downloadBackground(asset);
      catalog = AssetCatalog(
        packs: catalog.packs,
        backgrounds: [
          for (final item in catalog.backgrounds)
            if (item.id == asset.id) downloaded else item,
        ],
      );
      return downloaded;
    } finally {
      downloadingAssetIds.remove(asset.id);
      notifyListeners();
    }
  }

  Future<AssetCatalog> downloadPack(StickerPack pack) async {
    for (final sticker in pack.stickers.where((item) => !item.isUsable)) {
      await downloadSticker(sticker);
    }
    for (final background in catalog.backgrounds.where(
      (item) => pack.backgroundIds.contains(item.id) && !item.isUsable,
    )) {
      await downloadBackground(background);
    }
    return catalog;
  }
}
