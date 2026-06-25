import 'package:flutter/widgets.dart';
import 'package:stickerly_v2/app/app.dart';
import 'package:stickerly_v2/core/audio/stickerly_sfx.dart';
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
  await StickerlySfx.loadPreferences();
  runApp(const _StickerlyBootstrapApp());
}

class _StickerlyBootstrapApp extends StatefulWidget {
  const _StickerlyBootstrapApp();

  @override
  State<_StickerlyBootstrapApp> createState() => _StickerlyBootstrapAppState();
}

class _StickerlyBootstrapAppState extends State<_StickerlyBootstrapApp> {
  late ProjectRepository _projectRepository;
  late AssetCatalogLoader _loader;
  SupabaseAccountRepository? _accountRepository;
  var _bootstrapKey = 0;

  @override
  void initState() {
    super.initState();
    final localProjectRepository = LocalProjectRepository(
      SharedPreferencesKeyValueStore(),
    );
    _projectRepository = localProjectRepository;
    _loader = BundledAssetCatalogLoader();
    _connectSupabase(localProjectRepository);
  }

  Future<void> _connectSupabase(
    LocalProjectRepository localProjectRepository,
  ) async {
    if (!SupabaseConfiguration.isConfigured) return;
    try {
      await Supabase.initialize(
        url: SupabaseConfiguration.url,
        publishableKey: SupabaseConfiguration.anonKey,
      ).timeout(const Duration(seconds: 5));
      if (!mounted) return;
      final client = Supabase.instance.client;
      setState(() {
        _accountRepository = SupabaseAccountRepository(client);
        _projectRepository = SupabaseProjectRepository(
          client,
          localProjectRepository,
        );
        _loader = SupabaseAssetCatalogLoader(
          client,
          BundledAssetCatalogLoader(),
          AssetDownloadStore(client),
        );
        _bootstrapKey += 1;
      });
    } catch (_) {
      if (mounted) setState(() => _bootstrapKey += 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StickerlyApp(
      key: ValueKey(_bootstrapKey),
      projectRepository: _projectRepository,
      assetCatalogLoader: _loader,
      accountRepository: _accountRepository,
    );
  }
}
