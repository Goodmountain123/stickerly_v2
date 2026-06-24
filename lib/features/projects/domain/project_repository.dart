import 'package:stickerly_v2/features/projects/domain/sticker_project.dart';

abstract interface class ProjectRepository {
  Future<List<StickerProject>> list();

  Future<StickerProject?> get(String id);

  Future<void> save(StickerProject project);

  Future<void> delete(String id);
}

abstract interface class AccountScopedProjectRepository
    implements ProjectRepository {
  ProjectRepository forAccount(String accountId);
}
