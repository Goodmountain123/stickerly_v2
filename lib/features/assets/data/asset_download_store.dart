import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stickerly_v2/features/assets/domain/asset_catalog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AssetDownloadStore {
  AssetDownloadStore(this._client);

  final SupabaseClient _client;

  Future<AssetCatalog> resolveLocalFiles(AssetCatalog catalog) async {
    final packs = await Future.wait(
      catalog.packs.map((pack) async {
        final stickers = await Future.wait(pack.stickers.map(_resolveSticker));
        return StickerPack(
          id: pack.id,
          name: pack.name,
          folder: pack.folder,
          thumbnail: pack.thumbnail,
          stickers: stickers,
          backgroundIds: pack.backgroundIds,
        );
      }),
    );
    final backgrounds = await Future.wait(
      catalog.backgrounds.map(_resolveBackground),
    );
    return AssetCatalog(packs: packs, backgrounds: backgrounds);
  }

  Future<StickerAsset> downloadSticker(StickerAsset asset) async {
    final localPath = await _download(
      storagePath: asset.storagePath!,
      contentVersion: asset.contentVersion,
      checksumSha256: asset.checksumSha256,
    );
    return StickerAsset(
      id: asset.id,
      assetPath: localPath,
      storagePath: asset.storagePath,
      contentVersion: asset.contentVersion,
      checksumSha256: asset.checksumSha256,
      downloadState: AssetDownloadState.downloaded,
    );
  }

  Future<BackgroundAsset> downloadBackground(BackgroundAsset asset) async {
    final localPath = await _download(
      storagePath: asset.storagePath!,
      contentVersion: asset.contentVersion,
      checksumSha256: asset.checksumSha256,
    );
    return BackgroundAsset(
      id: asset.id,
      name: asset.name,
      assetPath: localPath,
      packId: asset.packId,
      storagePath: asset.storagePath,
      contentVersion: asset.contentVersion,
      checksumSha256: asset.checksumSha256,
      downloadState: AssetDownloadState.downloaded,
    );
  }

  Future<StickerAsset> _resolveSticker(StickerAsset asset) async {
    if (asset.storagePath == null) return asset;
    final localPath = await _existingPath(
      asset.storagePath!,
      asset.contentVersion,
      asset.checksumSha256,
    );
    if (localPath == null) return asset;
    return StickerAsset(
      id: asset.id,
      assetPath: localPath,
      storagePath: asset.storagePath,
      contentVersion: asset.contentVersion,
      checksumSha256: asset.checksumSha256,
      downloadState: AssetDownloadState.downloaded,
    );
  }

  Future<BackgroundAsset> _resolveBackground(BackgroundAsset asset) async {
    if (asset.storagePath == null) return asset;
    final localPath = await _existingPath(
      asset.storagePath!,
      asset.contentVersion,
      asset.checksumSha256,
    );
    if (localPath == null) return asset;
    return BackgroundAsset(
      id: asset.id,
      name: asset.name,
      assetPath: localPath,
      packId: asset.packId,
      storagePath: asset.storagePath,
      contentVersion: asset.contentVersion,
      checksumSha256: asset.checksumSha256,
      downloadState: AssetDownloadState.downloaded,
    );
  }

  Future<String> _download({
    required String storagePath,
    required int contentVersion,
    required String? checksumSha256,
  }) async {
    final target = await _targetFile(storagePath, contentVersion);
    final bytes = await _client.storage.from('assets').download(storagePath);
    _verify(bytes, checksumSha256);
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.part');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
    return target.path;
  }

  Future<String?> _existingPath(
    String storagePath,
    int contentVersion,
    String? checksumSha256,
  ) async {
    final file = await _targetFile(storagePath, contentVersion);
    if (!await file.exists()) return null;
    if (checksumSha256 == null || checksumSha256.isEmpty) return file.path;
    final bytes = await file.readAsBytes();
    try {
      _verify(bytes, checksumSha256);
      return file.path;
    } on FormatException {
      await file.delete();
      return null;
    }
  }

  Future<File> _targetFile(String storagePath, int contentVersion) async {
    final directory = await getApplicationSupportDirectory();
    final extension = storagePath.contains('.')
        ? '.${storagePath.split('.').last.toLowerCase()}'
        : '';
    final id = sha256.convert(storagePath.codeUnits);
    return File(
      '${directory.path}${Platform.pathSeparator}stickerly_assets'
      '${Platform.pathSeparator}${id}_v$contentVersion$extension',
    );
  }

  void _verify(Uint8List bytes, String? expected) {
    if (expected == null || expected.isEmpty) return;
    final actual = sha256.convert(bytes).toString().toLowerCase();
    if (actual != expected.toLowerCase()) {
      throw const FormatException('Asset checksum mismatch');
    }
  }
}
