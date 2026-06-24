import 'package:flutter_test/flutter_test.dart';
import 'package:stickerly_v2/app/app.dart';
import 'package:stickerly_v2/features/assets/domain/asset_catalog.dart';
import 'package:stickerly_v2/features/projects/domain/project_repository.dart';
import 'package:stickerly_v2/features/projects/domain/sticker_project.dart';

void main() {
  testWidgets('shows the empty Stickerly project library', (tester) async {
    await tester.pumpWidget(
      StickerlyApp(
        projectRepository: _EmptyRepository(),
        assetCatalogLoader: _EmptyCatalogLoader(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stickerly.'), findsOneWidget);
    expect(find.text('새 프로젝트'), findsOneWidget);
    expect(find.text('아직 프로젝트가 없어요'), findsOneWidget);
  });
}

class _EmptyRepository implements ProjectRepository {
  @override
  Future<void> delete(String id) async {}

  @override
  Future<StickerProject?> get(String id) async => null;

  @override
  Future<List<StickerProject>> list() async => [];

  @override
  Future<void> save(StickerProject project) async {}
}

class _EmptyCatalogLoader implements AssetCatalogLoader {
  @override
  Future<AssetCatalog> load() async {
    return const AssetCatalog(packs: [], backgrounds: []);
  }
}
