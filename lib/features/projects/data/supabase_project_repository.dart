import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:stickerly_v2/features/projects/domain/project_repository.dart';
import 'package:stickerly_v2/features/projects/domain/sticker_project.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseProjectRepository implements AccountScopedProjectRepository {
  SupabaseProjectRepository(
    this._client,
    this._fallback, {
    this.accountId,
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  final SupabaseClient _client;
  final AccountScopedProjectRepository _fallback;
  final String? accountId;
  final SharedPreferencesAsync _preferences;

  String get _userId {
    final id = accountId ?? _client.auth.currentUser?.id;
    if (id == null) throw StateError('Not signed in.');
    return id;
  }

  @override
  ProjectRepository forAccount(String accountId) => SupabaseProjectRepository(
    _client,
    _fallback,
    accountId: accountId,
    preferences: _preferences,
  );

  ProjectRepository get _local => _fallback.forAccount(_userId);
  String get _deleteQueueKey => 'stickerly.pending_project_deletes.$_userId';

  @override
  Future<List<StickerProject>> list() async {
    final localProjects = await _local.list();
    try {
      await _syncDeletes();
      await _syncLocalProjects(localProjects);
      final remoteProjects = await _loadRemoteProjects();
      for (final project in remoteProjects) {
        await _local.save(project);
      }
      final merged = _mergeProjects(localProjects, remoteProjects);
      merged.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return List.unmodifiable(merged);
    } catch (_) {
      return localProjects;
    }
  }

  @override
  Future<StickerProject?> get(String id) async {
    final localProject = await _local.get(id);
    try {
      final row = await _client
          .from('sticker_projects')
          .select('data,thumbnail_storage_path')
          .eq('user_id', _userId)
          .eq('id', id)
          .maybeSingle();
      if (row == null) return localProject;
      final project = await _projectFromRow(row);
      await _local.save(project);
      return project;
    } catch (_) {
      return localProject;
    }
  }

  @override
  Future<void> save(StickerProject project) async {
    await _local.save(project);
    try {
      await _saveRemote(project);
    } catch (_) {
      // Keep the local copy. The next online list() will sync it.
    }
  }

  @override
  Future<void> delete(String id) async {
    await _local.delete(id);
    await _queueDelete(id);
    try {
      await _deleteRemote(id);
      await _unqueueDelete(id);
    } catch (_) {
      // Keep tombstone. The next online list() will sync it.
    }
  }

  Future<List<StickerProject>> _loadRemoteProjects() async {
    final rows = await _client
        .from('sticker_projects')
        .select('id,data,thumbnail_storage_path,updated_at')
        .eq('user_id', _userId)
        .order('updated_at', ascending: false);
    final projects = <StickerProject>[];
    for (final row in (rows as List<dynamic>).cast<Map<String, dynamic>>()) {
      projects.add(await _projectFromRow(row));
    }
    return projects;
  }

  Future<StickerProject> _projectFromRow(Map<String, dynamic> row) async {
    final json = Map<String, dynamic>.from(row['data'] as Map);
    final thumbnailPath = row['thumbnail_storage_path'] as String?;
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      json['thumbnailPath'] = await _client.storage
          .from('project-thumbnails')
          .createSignedUrl(thumbnailPath, 3600);
    }
    return StickerProject.fromJson(json);
  }

  Future<void> _syncLocalProjects(List<StickerProject> localProjects) async {
    final rows = await _client
        .from('sticker_projects')
        .select('id,updated_at')
        .eq('user_id', _userId);
    final remoteUpdatedAt = {
      for (final row in (rows as List<dynamic>).cast<Map<String, dynamic>>())
        row['id'] as String:
            DateTime.tryParse(row['updated_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
    };
    for (final project in localProjects) {
      final remoteTime = remoteUpdatedAt[project.id];
      if (remoteTime == null || project.updatedAt.isAfter(remoteTime)) {
        await _saveRemote(project);
      }
    }
  }

  Future<void> _saveRemote(StickerProject project) async {
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
    await _unqueueDelete(project.id);
  }

  List<StickerProject> _mergeProjects(
    List<StickerProject> localProjects,
    List<StickerProject> remoteProjects,
  ) {
    final byId = {for (final project in remoteProjects) project.id: project};
    for (final project in localProjects) {
      final remote = byId[project.id];
      if (remote == null || project.updatedAt.isAfter(remote.updatedAt)) {
        byId[project.id] = project;
      }
    }
    return byId.values.toList();
  }

  Future<void> _deleteRemote(String id) async {
    await _client
        .from('sticker_projects')
        .delete()
        .eq('user_id', _userId)
        .eq('id', id);
  }

  Future<void> _syncDeletes() async {
    for (final id in await _pendingDeletes()) {
      await _deleteRemote(id);
      await _unqueueDelete(id);
    }
  }

  Future<Set<String>> _pendingDeletes() async {
    final raw = await _preferences.getString(_deleteQueueKey);
    if (raw == null || raw.isEmpty) return {};
    return raw.split('\n').where((id) => id.isNotEmpty).toSet();
  }

  Future<void> _queueDelete(String id) async {
    final ids = await _pendingDeletes();
    ids.add(id);
    await _preferences.setString(_deleteQueueKey, ids.join('\n'));
  }

  Future<void> _unqueueDelete(String id) async {
    final ids = await _pendingDeletes();
    ids.remove(id);
    await _preferences.setString(_deleteQueueKey, ids.join('\n'));
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
