import 'package:flutter/widgets.dart';
import 'package:stickerly_v2/app/app.dart';
import 'package:stickerly_v2/app/configuration/supabase_configuration.dart';
import 'package:stickerly_v2/features/assets/data/asset_download_store.dart';
import 'package:stickerly_v2/features/assets/data/supabase_asset_catalog_loader.dart';
import 'package:stickerly_v2/features/assets/domain/asset_catalog.dart';
import 'package:stickerly_v2/features/auth/data/supabase_account_repository.dart';
import 'package:stickerly_v2/core/storage/key_value_store.dart';
import 'package:stickerly_v2/features/projects/data/local_project_repository.dart';
import 'package:stickerly_v2/features/projects/data/supabase_project_repository.dart';
import 'package:stickerly_v2/features/projects/domain/project_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final localProjectRepository = LocalProjectRepository(
    SharedPreferencesKeyValueStore(),
  );
  ProjectRepository projectRepository = localProjectRepository;
  AssetCatalogLoader loader = BundledAssetCatalogLoader();
  SupabaseAccountRepository? accountRepository;
  if (SupabaseConfiguration.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfiguration.url,
      publishableKey: SupabaseConfiguration.anonKey,
    );
    final client = Supabase.instance.client;
    accountRepository = SupabaseAccountRepository(client);
    projectRepository = SupabaseProjectRepository(
      client,
      localProjectRepository,
    );
    loader = SupabaseAssetCatalogLoader(
      client,
      loader,
      AssetDownloadStore(client),
    );
  }
  runApp(
    StickerlyApp(
      projectRepository: projectRepository,
      assetCatalogLoader: loader,
      accountRepository: accountRepository,
    ),
  );
}
