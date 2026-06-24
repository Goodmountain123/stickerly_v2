import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stickerly_v2/app/theme/stickerly_colors.dart';
import 'package:stickerly_v2/app/widgets/stickerly_wordmark.dart';
import 'package:stickerly_v2/features/assets/domain/asset_catalog.dart';
import 'package:stickerly_v2/features/auth/domain/account_profile.dart';
import 'package:stickerly_v2/features/projects/domain/project_repository.dart';
import 'package:stickerly_v2/features/projects/presentation/projects_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    required this.repository,
    required this.assetCatalogLoader,
    this.accountRepository,
    super.key,
  });

  final ProjectRepository repository;
  final AssetCatalogLoader assetCatalogLoader;
  final AccountRepository? accountRepository;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  var _loading = true;
  var _signingIn = false;
  AccountProfile? _account;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    AccountProfile? account;
    try {
      account = await widget.accountRepository?.current();
    } catch (_) {
      await widget.accountRepository?.signOut();
      account = null;
    }
    if (!mounted) return;
    setState(() {
      _account = account;
      _loading = false;
    });
  }

  Future<void> _showTestAccountPicker() async {
    final accountNumber = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '로그인할 계정을 선택해 주세요',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.pop(context, 1),
                child: const Text('testaccount1 · 1,000,000 포인트'),
              ),
              const SizedBox(height: 10),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context, 2),
                child: const Text('testaccount2 · 0 포인트'),
              ),
            ],
          ),
        ),
      ),
    );
    if (accountNumber != null) await _signIn(accountNumber);
  }

  Future<void> _signIn(int accountNumber) async {
    final repository = widget.accountRepository;
    if (repository == null) {
      _showMessage('Supabase 연결이 필요해요.');
      return;
    }
    setState(() => _signingIn = true);
    try {
      final account = await repository.signInTestAccount(accountNumber);
      if (!mounted) return;
      setState(() => _account = account);
    } catch (_) {
      await repository.signOut();
      _showMessage('테스트 계정이 아직 생성되지 않았어요.');
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _signOut() async {
    await widget.accountRepository?.signOut();
    if (!mounted) return;
    setState(() => _account = null);
  }

  Future<AccountProfile> _updateDisplayName(String displayName) async {
    final account = await widget.accountRepository!.updateDisplayName(
      displayName,
    );
    if (mounted) setState(() => _account = account);
    return account;
  }

  Future<AccountProfile> _updateAvatarImage(String imagePath) async {
    final account = await widget.accountRepository!.updateAvatarImage(
      imagePath,
    );
    if (mounted) setState(() => _account = account);
    return account;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showPlaceholder(String provider) {
    _showMessage('$provider 로그인은 준비 중이에요.');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _StickerlySplashScreen();
    final account = _account;
    if (account == null) {
      return _LoginScreen(
        signingIn: _signingIn,
        onEmailSignIn: _showTestAccountPicker,
        onProviderPlaceholder: _showPlaceholder,
      );
    }
    return ProjectsScreen(
      key: ValueKey(account.userId),
      repository: widget.repository is AccountScopedProjectRepository
          ? (widget.repository as AccountScopedProjectRepository).forAccount(
              account.userId,
            )
          : widget.repository,
      assetCatalogLoader: widget.assetCatalogLoader,
      account: account,
      onAccountUpdated: _updateDisplayName,
      onAvatarUpdated: _updateAvatarImage,
      onLogout: _signOut,
    );
  }
}

class _StickerlySplashScreen extends StatelessWidget {
  const _StickerlySplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFFFF0DC),
              Color(0xFFFFE2D6),
              Color(0xFFF4E5EA),
              Color(0xFFE8E1F1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StickerlyWordmark(),
              SizedBox(height: 18),
              CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginScreen extends StatelessWidget {
  const _LoginScreen({
    required this.signingIn,
    required this.onEmailSignIn,
    required this.onProviderPlaceholder,
  });

  final bool signingIn;
  final VoidCallback onEmailSignIn;
  final ValueChanged<String> onProviderPlaceholder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFFF5E9), Color(0xFFF6EAF0)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: StickerlyWordmark()),
                    const SizedBox(height: 18),
                    const Text(
                      '스티커북을 열기 전에\n가볍게 로그인할게요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        height: 1.22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 28),
                    for (final provider in [
                      'Google',
                      'Kakao',
                      'Naver',
                      'Apple',
                    ])
                      _LoginButton(
                        label: '$provider로 로그인',
                        color: provider == 'Kakao'
                            ? const Color(0xFFFFE812)
                            : provider == 'Naver'
                            ? const Color(0xFF03C75A)
                            : provider == 'Apple'
                            ? const Color(0xFF241F2E)
                            : Colors.white,
                        foregroundColor:
                            provider == 'Naver' || provider == 'Apple'
                            ? Colors.white
                            : StickerlyColors.ink,
                        onPressed: () => onProviderPlaceholder(provider),
                      ),
                    _LoginButton(
                      label: signingIn ? '로그인 중...' : '이메일로 로그인',
                      color: StickerlyColors.pink,
                      foregroundColor: Colors.white,
                      onPressed: signingIn ? null : onEmailSignIn,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({
    required this.label,
    required this.color,
    required this.onPressed,
    this.foregroundColor = StickerlyColors.ink,
  });

  final String label;
  final Color color;
  final Color foregroundColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: foregroundColor,
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: StickerlyColors.line, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: 17)),
      ),
    );
  }
}
