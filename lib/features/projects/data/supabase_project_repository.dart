import 'dart:io';

import 'package:stickerly_v2/features/projects/domain/project_repository.dart';
import 'package:stickerly_v2/features/projects/domain/sticker_project.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseProjectRepository implements AccountScopedProjectRepository {
  SupabaseProjectRepository(this._client, this._fallback, {this.accountId});

  final SupabaseClient _client;
  final AccountScopedProjectRepository _fallback;
  final String? accountId;

  String get _userId {
    final id = accountId ?? _client.auth.currentUser?.id;
    if (id == null) throw StateError('Not signed in.');
    return id;
  }

  @override
  ProjectRepository forAccount(String accountId) =>
      SupabaseProjectRepository(_client, _fallback, accountId: accountId);

  ProjectRepository get _local => _fallback.forAccount(_userId);

  @override
  Future<List<StickerProject>> list() async {
    await _migrateLocalOnce();
    final rows = await _client
        .from('sticker_projects')
        .select('id,data,thumbnail_storage_path,updated_at')
        .eq('user_id', _userId)
        .order('updated_at', ascending: false);
    final projects = <StickerProject>[];
    for (final row in (rows as List<dynamic>).cast<Map<String, dynamic>>()) {
      final json = Map<String, dynamic>.from(row['data'] as Map);
      final thumbnailPath = row['thumbnail_storage_path'] as String?;
      if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
        json['thumbnailPath'] = await _client.storage
            .from('project-thumbnails')
            .createSignedUrl(thumbnailPath, 3600);
      }
      projects.add(StickerProject.fromJson(json));
    }
    return List.unmodifiable(projects);
  }

  @override
  Future<StickerProject?> get(String id) async {
    final row = await _client
        .from('sticker_projects')
        .select('data,thumbnail_storage_path')
        .eq('user_id', _userId)
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final json = Map<String, dynamic>.from(row['data'] as Map);
    final thumbnailPath = row['thumbnail_storage_path'] as String?;
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      json['thumbnailPath'] = await _client.storage
          .from('project-thumbnails')
          .createSignedUrl(thumbnailPath, 3600);
    }
    return StickerProject.fromJson(json);
  }

  @override
  Future<void> save(StickerProject project) async {
    final existing = await _client
        .from('sticker_projects')
        .select('thumbnail_storage_path')
        .eq('user_id', _userId)
        .eq('id', project.id)
        .maybeSingle();
    var thumbnailStoragePath = existing?['thumbnail_storage_path'] as String?;
    thumbnailStoragePath = await _uploadThumbnailIfNeeded(
      project,
      thumbnailStoragePath,
    );
    await _client.from('sticker_projects').upsert({
      'user_id': _userId,
      'id': project.id,
      'title': project.title,
      'data': _serverJson(project),
      'thumbnail_storage_path': thumbnailStoragePath,
      'created_at': project.createdAt.toIso8601String(),
      'updated_at': project.updatedAt.toIso8601String(),
    }, onConflict: 'user_id,id');
    await _local.save(project);
  }

  @override
  Future<void> delete(String id) async {
    await _client
        .from('sticker_projects')
        .delete()
        .eq('user_id', _userId)
        .eq('id', id);
    await _local.delete(id);
  }

  Future<void> _migrateLocalOnce() async {
    final localProjects = await _local.list();
    if (localProjects.isEmpty) return;
    final rows = await _client
        .from('sticker_projects')
        .select('id')
        .eq('user_id', _userId);
    final remoteIds = {
      for (final row in (rows as List<dynamic>).cast<Map<String, dynamic>>())
        row['id'] as String,
    };
    for (final project in localProjects) {
      if (!remoteIds.contains(project.id)) await save(project);
    }
  }

  Map<String, dynamic> _serverJson(StickerProject project) {
    final json = project.toJson();
    json.remove('thumbnailPath');
    return json;
  }

  Future<String?> _uploadThumbnailIfNeeded(
    StickerProject project,
    String? currentPath,
  ) async {
    final thumbnailPath = project.thumbnailPath;
    if (thumbnailPath == null ||
        thumbnailPath.isEmpty ||
        thumbnailPath.startsWith('http') ||
        thumbnailPath.startsWith('assets/')) {
      return currentPath;
    }
    final file = File(thumbnailPath);
    if (!await file.exists()) return currentPath;
    final storagePath = '$_userId/${project.id}.png';
    await _client.storage
        .from('project-thumbnails')
        .uploadBinary(
          storagePath,
          await file.readAsBytes(),
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/png',
          ),
        );
    return storagePath;
  }
}
