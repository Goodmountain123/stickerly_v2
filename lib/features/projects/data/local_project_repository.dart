import 'dart:convert';

import 'package:stickerly_v2/core/storage/key_value_store.dart';
import 'package:stickerly_v2/features/projects/domain/project_repository.dart';
import 'package:stickerly_v2/features/projects/domain/sticker_project.dart';

class LocalProjectRepository implements AccountScopedProjectRepository {
  LocalProjectRepository(this._store, {this.accountId});

  static const _storageKeyPrefix = 'stickerly.projects.v2';

  final KeyValueStore _store;
  final String? accountId;

  String get _storageKey => '$_storageKeyPrefix.${accountId ?? 'anonymous'}';

  @override
  ProjectRepository forAccount(String accountId) =>
      LocalProjectRepository(_store, accountId: accountId);

  @override
  Future<List<StickerProject>> list() async {
    final projects = await _readAll();
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(projects);
  }

  @override
  Future<StickerProject?> get(String id) async {
    final projects = await _readAll();
    return projects.where((project) => project.id == id).firstOrNull;
  }

  @override
  Future<void> save(StickerProject project) async {
    final projects = await _readAll();
    final index = projects.indexWhere((item) => item.id == project.id);
    if (index == -1) {
      projects.add(project);
    } else {
      projects[index] = project;
    }
    await _writeAll(projects);
  }

  @override
  Future<void> delete(String id) async {
    final projects = await _readAll();
    projects.removeWhere((project) => project.id == id);
    await _writeAll(projects);
  }

  Future<List<StickerProject>> _readAll() async {
    final value = await _store.read(_storageKey);
    if (value == null || value.isEmpty) return [];

    final rows = jsonDecode(value) as List<dynamic>;
    return rows
        .map((row) => StickerProject.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> _writeAll(List<StickerProject> projects) {
    return _store.write(
      _storageKey,
      jsonEncode(projects.map((project) => project.toJson()).toList()),
    );
  }
}
