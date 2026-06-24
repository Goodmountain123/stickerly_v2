import 'package:flutter/material.dart';
import 'package:stickerly_v2/app/theme/stickerly_theme.dart';
import 'package:stickerly_v2/core/storage/key_value_store.dart';
import 'package:stickerly_v2/features/assets/domain/asset_catalog.dart';
import 'package:stickerly_v2/features/auth/domain/account_profile.dart';
import 'package:stickerly_v2/features/auth/presentation/auth_gate.dart';
import 'package:stickerly_v2/features/projects/data/local_project_repository.dart';
import 'package:stickerly_v2/features/projects/domain/project_repository.dart';

class StickerlyApp extends StatelessWidget {
  StickerlyApp({
    ProjectRepository? projectRepository,
    AssetCatalogLoader? assetCatalogLoader,
    this.accountRepository,
    super.key,
  }) : projectRepository =
           projectRepository ??
           LocalProjectRepository(SharedPreferencesKeyValueStore()),
       assetCatalogLoader = assetCatalogLoader ?? BundledAssetCatalogLoader();

  final ProjectRepository projectRepository;
  final AssetCatalogLoader assetCatalogLoader;
  final AccountRepository? accountRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stickerly',
      debugShowCheckedModeBanner: false,
      theme: StickerlyTheme.light(),
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 1.3,
        maxScaleFactor: 1.3,
        child: child!,
      ),
      home: AuthGate(
        repository: projectRepository,
        assetCatalogLoader: assetCatalogLoader,
        accountRepository: accountRepository,
      ),
    );
  }
}
