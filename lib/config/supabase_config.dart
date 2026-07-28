/// Credenciais do projeto Supabase.
///
/// Preenchido com os dados do projeto RDS PHORESTAL.
///   Supabase → Project Settings → API
///     - Project URL                  -> supabaseUrl
///     - Project API keys: publishable -> supabasePublishableKey
///
/// A chave "publishable" pode ficar no app cliente (é pública por design).
/// NUNCA coloque aqui a chave "secret" (sb_secret_...).
class SupabaseConfig {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://jkwnynwxxfesaagifkhq.supabase.co',
  );

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_JUUrV_RGS8Cjp3x8r1R5gw_CBVlaygw',
  );

  static bool get isConfigured =>
      supabaseUrl.startsWith('http') &&
      supabasePublishableKey.length > 20 &&
      !supabasePublishableKey.contains('COLE_AQUI');
}
