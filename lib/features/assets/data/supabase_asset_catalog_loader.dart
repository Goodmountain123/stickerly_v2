import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:stickerly_v2/features/assets/data/asset_download_store.dart';
import 'package:stickerly_v2/features/assets/domain/asset_catalog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAssetCatalogLoader implements DownloadableAssetCatalogLoader {
  SupabaseAssetCatalogLoader(
    this._client,
    this._fallback,
    this._downloadStore, {
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  final SupabaseClient _client;
  final AssetCatalogLoader _fallback;
  final AssetDownloadStore? _downloadStore;
  final SharedPreferencesAsync _preferences;

  String get _accountCacheKey => _client.auth.currentUser?.id ?? 'anonymous';
  String get _catalogKey => 'stickerly.remote_asset_catalog.$_accountCacheKey';
  String get _versionKey =>
      'stickerly.remote_asset_catalog_version.$_accountCacheKey';
  static const _defaultAssetsInstalledKey =
      'stickerly.default_assets_installed.v1';

  @override
  Future<StickerAsset> downloadSticker(StickerAsset asset) {
    final store = _downloadStore;
    if (store == null) throw StateError('Asset downloads are not configured');
    return store.downloadSticker(asset);
  }

  @override
  Future<BackgroundAsset> downloadBackground(BackgroundAsset asset) {
    final store = _downloadStore;
    if (store == null) throw StateError('Asset downloads are not configured');
    return store.downloadBackground(asset);
  }

  @override
  Future<AssetCatalog> load() async {
    final bundled = await _fallback.load();
    try {
      final remoteVersion = await _loadRemoteVersion();
      final cachedVersion = await _preferences.getInt(_versionKey);
      final cachedCatalog = await _readCache();
      final shouldUseCache =
          _client.auth.currentUser == null &&
          cachedCatalog != null &&
          cachedVersion == remoteVersion;
      if (shouldUseCache) {
        final catalog = await _attachPreviewUrls(
          _mergeBundled(cachedCatalog, bundled),
        );
        return _prepareCatalog(catalog, installDefaults: true);
      }

      final remote = await _loadRemoteCatalog();
      await _preferences.setString(_catalogKey, jsonEncode(_toJson(remote)));
      await _preferences.setInt(_versionKey, remoteVersion);
      final catalog = await _attachPreviewUrls(_mergeBundled(remote, bundled));
      return _prepareCatalog(catalog, installDefaults: true);
    } catch (_) {
      final cached = await _readCache();
      return _prepareCatalog(
        cached == null ? bundled : _mergeBundled(cached, bundled),
        installDefaults: cached != null,
      );
    }
  }

  Future<AssetCatalog> _prepareCatalog(
    AssetCatalog catalog, {
    required bool installDefaults,
  }) async {
    var resolved = await _resolveLocalFiles(catalog);
    if (!installDefaults ||
        await _preferences.getBool(_defaultAssetsInstalledKey) == true) {
      return resolved;
    }
    final store = _downloadStore;
    if (store == null) return resolved;
    try {
      for (final pack in resolved.packs) {
        for (final sticker in pack.stickers.where((item) => !item.isUsable)) {
          if (sticker.storagePath != null) {
            await store.downloadSticker(sticker);
          }
        }
        for (final background in resolved.backgrounds.where(
          (item) => pack.backgroundIds.contains(item.id) && !item.isUsable,
        )) {
          if (background.storagePath != null) {
            await store.downloadBackground(background);
          }
        }
      }
      resolved = await _resolveLocalFiles(catalog);
      await _preferences.setBool(_defaultAssetsInstalledKey, true);
    } catch (_) {
      // Retry on the next launch if the initial download was interrupted.
    }
    return resolved;
  }

  Future<int> _loadRemoteVersion() async {
    final row = await _client
        .from('app_settings')
        .select('value')
        .eq('key', 'asset_catalog_version')
        .single();
    final value = row['value'];
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? 1;
  }

  Future<AssetCatalog> _loadRemoteCatalog() async {
    final results = await Future.wait([
      _client
          .from('sticker_packs')
          .select('id,name,legacy_id,position')
          .order('position'),
      _client
          .from('available_stickers')
          .select(
            'id,pack_id,legacy_asset_id,name,storage_path,position,content_version,checksum_sha256',
          )
          .order('position'),
      _client
          .from('available_backgrounds')
          .select(
            'id,pack_id,legacy_id,name,storage_path,position,content_version,checksum_sha256',
          )
          .order('position'),
    ]);

    final packRows = (results[0] as List<dynamic>).cast<Map<String, dynamic>>();
    final stickerRows = (results[1] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final backgroundRows = (results[2] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final publicPackIds = {
      for (final row in packRows)
        row['id'] as String:
            (row['legacy_id'] as String?) ?? row['id'] as String,
    };

    final stickersByPack = <String, List<StickerAsset>>{};
    for (final row in stickerRows) {
      final packId = row['pack_id'] as String;
      stickersByPack
          .putIfAbsent(packId, () => [])
          .add(
            StickerAsset(
              id: (row['legacy_asset_id'] as String?) ?? row['id'] as String,
              assetPath: '',
              storagePath: row['storage_path'] as String,
              contentVersion: _asInt(row['content_version']),
              checksumSha256: row['checksum_sha256'] as String?,
              downloadState: AssetDownloadState.pending,
            ),
          );
    }

    final backgrounds = backgroundRows
        .map(
          (row) => BackgroundAsset(
            id: (row['legacy_id'] as String?) ?? row['id'] as String,
            name: row['name'] as String,
            assetPath: '',
            packId: publicPackIds[row['pack_id']],
            storagePath: row['storage_path'] as String,
            contentVersion: _asInt(row['content_version']),
            checksumSha256: row['checksum_sha256'] as String?,
            downloadState: AssetDownloadState.pending,
          ),
        )
        .toList(growable: false);

    final packs = packRows
        .where((row) => stickersByPack.containsKey(row['id']))
        .map((row) {
          final id = row['id'] as String;
          final publicId = publicPackIds[id]!;
          final stickers = stickersByPack[id]!;
          return StickerPack(
            id: publicId,
            name: row['name'] as String,
            folder: '',
            thumbnail: '',
            stickers: stickers,
            backgroundIds: backgrounds
                .where((background) => background.packId == publicId)
                .map((background) => background.id)
                .toList(growable: false),
          );
        })
        .toList(growable: false);

    return AssetCatalog(packs: packs, backgrounds: backgrounds);
  }

  Future<AssetCatalog?> _readCache() async {
    final raw = await _preferences.getString(_catalogKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return _fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static int _asInt(Object? value) =>
      value is int ? value : int.tryParse(value.toString()) ?? 1;

  static Map<String, dynamic> _toJson(AssetCatalog catalog) => {
    'packs': [
      for (final pack in catalog.packs)
        {
          'id': pack.id,
          'name': pack.name,
          'stickers': [
            for (final sticker in pack.stickers)
              {
                'id': sticker.id,
                'storagePath': sticker.storagePath,
                'contentVersion': sticker.contentVersion,
                'checksumSha256': sticker.checksumSha256,
              },
          ],
        },
    ],
    'backgrounds': [
      for (final background in catalog.backgrounds)
        {
          'id': background.id,
          'name': background.name,
          'packId': background.packId,
          'storagePath': background.storagePath,
          'contentVersion': background.contentVersion,
          'checksumSha256': background.checksumSha256,
        },
    ],
  };

  static AssetCatalog _fromJson(Map<String, dynamic> json) {
    final backgrounds = (json['backgrounds'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(
          (row) => BackgroundAsset(
            id: row['id'] as String,
            name: row['name'] as String,
            assetPath: '',
            packId: row['packId'] as String?,
            storagePath: row['storagePath'] as String,
            contentVersion: _asInt(row['contentVersion']),
            checksumSha256: row['checksumSha256'] as String?,
            downloadState: AssetDownloadState.pending,
          ),
        )
        .toList(growable: false);
    final packs = (json['packs'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(
          (row) => StickerPack(
            id: row['id'] as String,
            name: row['name'] as String,
            folder: '',
            thumbnail: '',
            stickers: (row['stickers'] as List<dynamic>)
                .cast<Map<String, dynamic>>()
                .map(
                  (sticker) => StickerAsset(
                    id: sticker['id'] as String,
                    assetPath: '',
                    storagePath: sticker['storagePath'] as String,
                    contentVersion: _asInt(sticker['contentVersion']),
                    checksumSha256: sticker['checksumSha256'] as String?,
                    downloadState: AssetDownloadState.pending,
                  ),
                )
                .toList(growable: false),
            backgroundIds: backgrounds
                .where((background) => background.packId == row['id'])
                .map((background) => background.id)
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
    return AssetCatalog(packs: packs, backgrounds: backgrounds);
  }

  static AssetCatalog _mergeBundled(AssetCatalog remote, AssetCatalog bundled) {
    final bundledPacks = {for (final pack in bundled.packs) pack.id: pack};
    final bundledBackgrounds = {
      for (final background in bundled.backgrounds) background.id: background,
    };
    final packs = remote.packs
        .map((pack) {
          final bundledPack = bundledPacks[pack.id];
          final bundledStickers = {
            for (final sticker
                in bundledPack?.stickers ?? const <StickerAsset>[])
              sticker.id: sticker,
          };
          return StickerPack(
            id: pack.id,
            name: pack.name,
            folder: bundledPack?.folder ?? pack.folder,
            thumbnail: bundledPack?.thumbnail ?? pack.thumbnail,
            stickers: pack.stickers
                .map((sticker) {
                  final bundledSticker = bundledStickers[sticker.id];
                  if (bundledSticker == null ||
                      sticker.contentVersion > bundledSticker.contentVersion) {
                    return sticker;
                  }
                  return StickerAsset(
                    id: sticker.id,
                    assetPath: bundledSticker.assetPath,
                    storagePath: sticker.storagePath,
                    contentVersion: sticker.contentVersion,
                    checksumSha256: sticker.checksumSha256,
                    downloadState: AssetDownloadState.bundled,
                  );
                })
                .toList(growable: false),
            backgroundIds: pack.backgroundIds,
          );
        })
        .toList(growable: false);
    final backgrounds = remote.backgrounds
        .map((background) {
          final bundledBackground = bundledBackgrounds[background.id];
          if (bundledBackground == null ||
              background.contentVersion > bundledBackground.contentVersion) {
            return background;
          }
          return BackgroundAsset(
            id: background.id,
            name: background.name,
            assetPath: bundledBackground.assetPath,
            packId: background.packId,
            storagePath: background.storagePath,
            contentVersion: background.contentVersion,
            checksumSha256: background.checksumSha256,
            downloadState: AssetDownloadState.bundled,
          );
        })
        .toList(growable: false);
    return AssetCatalog(packs: packs, backgrounds: backgrounds);
  }

  Future<AssetCatalog> _resolveLocalFiles(AssetCatalog catalog) {
    return _downloadStore?.resolveLocalFiles(catalog) ??
        Future<AssetCatalog>.value(catalog);
  }

  Future<AssetCatalog> _attachPreviewUrls(AssetCatalog catalog) async {
    final packs = await Future.wait(
      catalog.packs.map((pack) async {
        if (pack.thumbnail.isNotEmpty) return pack;
        final first = pack.stickers.firstOrNull;
        final storagePath = first?.storagePath;
        if (storagePath == null || storagePath.isEmpty) return pack;
        try {
          final url = await _client.storage
              .from('assets')
              .createSignedUrl(storagePath, 3600);
          return StickerPack(
            id: pack.id,
            name: pack.name,
            folder: pack.folder,
            thumbnail: url,
            stickers: pack.stickers,
            backgroundIds: pack.backgroundIds,
          );
        } catch (_) {
          return pack;
        }
      }),
    );
    return AssetCatalog(packs: packs, backgrounds: catalog.backgrounds);
  }
}
