class SupabaseConfiguration {
  const SupabaseConfiguration._();

  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://kdxgbwaexmrjdontvcma.supabase.co',
  );
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_GOAIafaN5GSi-Pk1XwcuhQ_DZ5lBZQZ',
  );

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
