import 'dart:convert';

import 'package:flutter/services.dart';

class AssetCatalog {
  const AssetCatalog({required this.packs, required this.backgrounds});

  final List<StickerPack> packs;
  final List<BackgroundAsset> backgrounds;

  AssetCatalog visible({required Set<String> hiddenPackIds}) {
    if (hiddenPackIds.isEmpty) return this;
    return AssetCatalog(
      packs: packs
          .where((pack) => !hiddenPackIds.contains(pack.id))
          .toList(growable: false),
      backgrounds: backgrounds
          .where(
            (background) =>
                background.packId == null ||
                !hiddenPackIds.contains(background.packId),
          )
          .toList(growable: false),
    );
  }
}

class StickerPack {
  const StickerPack({
    required this.id,
    required this.name,
    required this.folder,
    required this.thumbnail,
    required this.stickers,
    this.backgroundIds = const [],
  });

  final String id;
  final String name;
  final String folder;
  final String thumbnail;
  final List<StickerAsset> stickers;
  final List<String> backgroundIds;
}

class StickerAsset {
  const StickerAsset({
    required this.id,
    required this.assetPath,
    this.storagePath,
    this.contentVersion = 1,
    this.checksumSha256,
    this.downloadState = AssetDownloadState.bundled,
  });

  final String id;
  final String assetPath;
  final String? storagePath;
  final int contentVersion;
  final String? checksumSha256;
  final AssetDownloadState downloadState;

  bool get isUsable =>
      downloadState == AssetDownloadState.bundled ||
      downloadState == AssetDownloadState.downloaded;
}

class BackgroundAsset {
  const BackgroundAsset({
    required this.id,
    required this.name,
    required this.assetPath,
    this.packId,
    this.storagePath,
    this.contentVersion = 1,
    this.checksumSha256,
    this.downloadState = AssetDownloadState.bundled,
  });

  final String id;
  final String name;
  final String assetPath;
  final String? packId;
  final String? storagePath;
  final int contentVersion;
  final String? checksumSha256;
  final AssetDownloadState downloadState;

  bool get isUsable =>
      downloadState == AssetDownloadState.bundled ||
      downloadState == AssetDownloadState.downloaded;
}

enum AssetDownloadState { bundled, pending, downloading, downloaded, failed }

abstract interface class AssetCatalogLoader {
  Future<AssetCatalog> load();
}

abstract interface class DownloadableAssetCatalogLoader
    implements AssetCatalogLoader {
  Future<StickerAsset> downloadSticker(StickerAsset asset);

  Future<BackgroundAsset> downloadBackground(BackgroundAsset asset);
}

class BundledAssetCatalogLoader implements AssetCatalogLoader {
  BundledAssetCatalogLoader({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  @override
  Future<AssetCatalog> load() async {
    final packFolders = await _bundle.loadStructuredData<List<String>>(
      'assets/sticker_packs/index.json',
      (value) async => (jsonDecode(value) as List<dynamic>).cast<String>(),
    );
    final backgrounds = await _bundle.loadStructuredData<List<BackgroundAsset>>(
      'assets/backgrounds/index.json',
      (value) async {
        final rows = jsonDecode(value) as List<dynamic>;
        return rows
            .map((row) {
              final json = row as Map<String, dynamic>;
              return BackgroundAsset(
                id: json['id'] as String,
                name: json['name'] as String,
                assetPath: 'assets/backgrounds/${json['file']}',
                packId: json['packId'] as String?,
              );
            })
            .toList(growable: false);
      },
    );

    final packs = await Future.wait(
      packFolders.map((folder) async {
        final base = 'assets/sticker_packs/$folder';
        return _bundle.loadStructuredData<StickerPack>('$base/pack.json', (
          value,
        ) async {
          final json = jsonDecode(value) as Map<String, dynamic>;
          return StickerPack(
            id: json['id'] as String,
            name: json['name'] as String,
            folder: folder,
            thumbnail: '$base/${json['thumbnail']}',
            backgroundIds: (json['backgrounds'] as List<dynamic>? ?? const [])
                .cast<String>(),
            stickers: (json['stickers'] as List<dynamic>)
                .cast<String>()
                .map((file) => StickerAsset(id: file, assetPath: '$base/$file'))
                .toList(growable: false),
          );
        });
      }),
    );

    return AssetCatalog(packs: packs, backgrounds: backgrounds);
  }
}
