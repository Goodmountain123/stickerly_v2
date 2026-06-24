import 'package:flutter_test/flutter_test.dart';
import 'package:stickerly_v2/core/storage/key_value_store.dart';
import 'package:stickerly_v2/features/projects/data/local_project_repository.dart';
import 'package:stickerly_v2/features/projects/domain/canvas_preset.dart';
import 'package:stickerly_v2/features/projects/domain/sticker_project.dart';

void main() {
  group('LocalProjectRepository', () {
    test('saves, restores, sorts and deletes projects', () async {
      final repository = LocalProjectRepository(_MemoryStore());
      final older = StickerProject.create(
        title: '먼저 만든 그림',
        preset: CanvasPreset.story,
        now: DateTime(2026, 6, 22),
      );
      final newer = StickerProject.create(
        title: '최근 그림',
        now: DateTime(2026, 6, 23),
      );

      await repository.save(older);
      await repository.save(newer);

      final projects = await repository.list();
      expect(projects.map((project) => project.title), ['최근 그림', '먼저 만든 그림']);
      expect(projects.last.canvasHeight, CanvasPreset.story.height);
      expect((await repository.get(older.id))?.title, older.title);

      await repository.delete(newer.id);
      expect(await repository.get(newer.id), isNull);
      expect(await repository.list(), hasLength(1));
    });

    test('reads legacy canvas type aliases', () {
      final project = StickerProject.fromJson({
        'id': 'legacy',
        'title': '예전 프로젝트',
        'canvasType': 'phone',
        'createdAt': 1,
        'updatedAt': 1,
        'stickerItems': <Object>[],
      });

      expect(project.canvasWidth, CanvasPreset.story.width);
      expect(project.canvasHeight, CanvasPreset.story.height);
    });
  });
}

class _MemoryStore implements KeyValueStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
